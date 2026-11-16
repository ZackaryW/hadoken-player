import 'dart:async';
import 'package:just_audio/just_audio.dart';
import 'package:troona/skills/skill.dart';
import '../../domain/ports/skill_audio_effects_port.dart';

final class _MixPlayer {
  final AudioPlayer player;
  final MixLayer layer;
  const _MixPlayer(this.player, this.layer);
}

final class _Mix {
  final String id;
  final String source;
  final Duration deadline;
  final StartAudioMix request;
  final MixLayer? primary;
  final List<_MixPlayer> layers;
  const _Mix(
    this.id,
    this.source,
    this.deadline,
    this.request,
    this.primary,
    this.layers,
  );
}

/// Service-owned secondary decoders. UI pages never own a player or timer.
final class SkillMixer {
  final AudioPlayer primary;
  final AudioPlayer Function() createPlayer;
  final Future<AudioSource> Function(MixLayer) sourceFor;
  final Future<Duration> Function() now;
  final String Function() sessionId;
  final String Function() sourceIdentity;
  final String? Function() currentSong;
  final bool Function() playIntent;
  final bool supported;
  final bool scheduleTimers;
  final _errors = StreamController<String>.broadcast();
  Stream<String> get errors => _errors.stream;
  final _owned = <AudioPlayer>[];
  _Mix? _active;
  bool _preparing = false;
  String? _ownerId;
  Future<void>? _cleanup;
  Completer<void>? _preparationDone;
  bool _cleanupFailed = false;
  int _generation = 0;
  double _gain = 1;
  double _baseSpeed = 1;
  Timer? _timer;
  bool _disposed = false;
  SkillMixer({
    required this.primary,
    required this.createPlayer,
    required this.sourceFor,
    required this.now,
    required this.sessionId,
    required this.sourceIdentity,
    required this.currentSong,
    required this.playIntent,
    required this.supported,
    this.scheduleTimers = true,
  });
  String? get activeId => _active?.id;
  int get ownedLayerCount => _owned.length;

  Future<void> applyGain(double gain) async {
    _gain = gain;
    final mix = _active;
    final factor =
        mix == null ||
            mix.request.layers.singleOrNull?.kind == MixLayerKind.noise
        ? 1.0
        : mix.primary?.gain ?? 0.0;
    await primary.setVolume(gain * factor);
    for (final layer in mix?.layers ?? <_MixPlayer>[]) {
      if (_active != mix) break;
      await layer.player.setVolume(_gain * layer.layer.gain);
    }
  }

  Future<void> applySpeed(double value) async {
    _baseSpeed = value;
    await primary.setSpeed(_active?.primary?.speed ?? value);
  }

  Future<AudioMixResult> start(
    StartAudioMix request, {
    required String id,
    required String session,
  }) async {
    if (!supported) {
      return const AudioMixResult(
        CapabilityStatus.unsupported,
        'Audio mixing is unavailable on this backend.',
      );
    }
    if (_disposed ||
        _active != null ||
        _preparing ||
        _cleanup != null ||
        _cleanupFailed ||
        _owned.isNotEmpty) {
      return const AudioMixResult(
        CapabilityStatus.denied,
        'Another mix is active or cleanup is pending.',
      );
    }
    if (request.lifetime > const Duration(minutes: 5) ||
        request.layers.any(
          (l) => l.speed < 0.5 || l.speed > 2 || l.pitch < 0.5 || l.pitch > 2,
        )) {
      return const AudioMixResult(
        CapabilityStatus.unsupported,
        'Mix limits: five minutes; speed and pitch 0.5–2×.',
      );
    }
    if (session != sessionId() || currentSong() == null) {
      return const AudioMixResult(
        CapabilityStatus.denied,
        'No matching playback session.',
      );
    }
    _preparing = true;
    _preparationDone = Completer<void>();
    _ownerId = id;
    final generation = ++_generation;
    final source = sourceIdentity();
    final prepared = <_MixPlayer>[];
    MixLayer? reused;
    bool valid() =>
        !_disposed &&
        generation == _generation &&
        session == sessionId() &&
        source == sourceIdentity();
    try {
      for (final layer in request.layers) {
        final audioSource = await sourceFor(layer);
        if (!valid()) {
          throw StateError('Mix source changed during preparation.');
        }
        // Continuing mixes keep both sources independent: a new primary track
        // cannot inherit an old layer's pitch, speed or identity.
        if (reused == null &&
            request.sourceChange == MixSourceChange.cancel &&
            layer.kind == MixLayerKind.song &&
            layer.song!.libraryId == currentSong()) {
          if (primary.duration != null && layer.offset >= primary.duration!) {
            throw ArgumentError('Mix offset is beyond the song.');
          }
          reused = layer;
          continue;
        }
        final player = createPlayer();
        _owned.add(player);
        final duration = await player.setAudioSource(audioSource);
        if (!valid()) throw StateError('Mix canceled during preparation.');
        if (duration != null && layer.offset >= duration) {
          throw ArgumentError('Mix offset is beyond the song.');
        }
        await player.setSpeed(layer.speed);
        await player.setPitch(layer.pitch);
        await player.seek(layer.offset);
        if (layer.kind == MixLayerKind.noise) {
          await player.setLoopMode(LoopMode.one);
        }
        prepared.add(_MixPlayer(player, layer));
      }
      if (!valid()) throw StateError('Mix source changed during preparation.');
      final deadline = (await now()) + request.lifetime;
      if (!valid()) throw StateError('Mix canceled during preparation.');
      _active = _Mix(id, source, deadline, request, reused, prepared);
      if (reused != null) {
        await primary.setSpeed(reused.speed);
        if (!valid()) throw StateError('Mix canceled.');
        await primary.setPitch(reused.pitch);
        if (!valid()) throw StateError('Mix canceled.');
        await primary.seek(reused.offset);
      }
      await applyGain(_gain);
      if (!valid() || (await now()) >= deadline) {
        throw StateError('Mix ended during preparation.');
      }
      await _syncLayers();
      if (_active?.id != id) {
        return const AudioMixResult(
          CapabilityStatus.denied,
          'Mix ended before activation.',
        );
      }
      if (scheduleTimers) _schedule(deadline, generation);
      return AudioMixResult(
        CapabilityStatus.applied,
        'Mix active.',
        deadline: deadline,
      );
    } catch (_) {
      try {
        _active = null;
        await _release();
      } catch (_) {
        _report('Mix preparation failed; cleanup is pending.');
        _retryCleanup(id);
      }
      return const AudioMixResult(
        CapabilityStatus.failed,
        'Mix source or preparation failed.',
      );
    } finally {
      _preparing = false;
      _preparationDone!.complete();
      _preparationDone = null;
      if (_active == null && _owned.isEmpty && !_cleanupFailed) _ownerId = null;
    }
  }

  void _schedule(Duration deadline, int generation) {
    _timer?.cancel();
    unawaited(
      now().then((elapsed) {
        if (_disposed || generation != _generation) return;
        _timer = Timer(
          deadline > elapsed ? deadline - elapsed : Duration.zero,
          () {
            unawaited(
              synchronize().catchError((Object _) {
                _report('Mix expiry cleanup is pending.');
                final id = _ownerId;
                if (id != null) _retryCleanup(id);
              }),
            );
          },
        );
      }),
    );
  }

  Future<void> synchronize() async {
    final mix = _active;
    if (mix == null) return;
    if (await now() >= mix.deadline) {
      await cancel(mix.id);
      return;
    }
    await _syncLayers();
  }

  Future<void> _syncLayers() async {
    final mix = _active;
    if (mix == null) return;
    for (final layer in mix.layers) {
      if (_active != mix) return;
      if (playIntent()) {
        if (!layer.player.playing) {
          unawaited(
            layer.player.play().catchError((Object _) async {
              _report('A mix layer failed during playback.');
              try {
                await cancel(mix.id);
              } catch (_) {
                _retryCleanup(mix.id);
              }
            }),
          );
        }
      } else {
        await layer.player.pause();
      }
    }
  }

  Future<void> sourceChanged({String? nextIdentity}) async {
    final mix = _active;
    if (mix != null &&
        mix.source != (nextIdentity ?? sourceIdentity()) &&
        mix.request.sourceChange == MixSourceChange.cancel) {
      await cancel(mix.id);
    }
  }

  void _report(String message) {
    if (!_errors.isClosed) _errors.add(message);
  }

  void _retryCleanup(String id) {
    if (_disposed || !scheduleTimers || _ownerId != id) return;
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 1), () {
      unawaited(
        cancel(id).catchError((Object _) {
          _retryCleanup(id);
        }),
      );
    });
  }

  Future<void> cancel([String? id]) async {
    if (_ownerId == null || (id != null && _ownerId != id)) return;
    _generation++;
    _timer?.cancel();
    _active = null;
    if (_cleanup != null) return _cleanup;
    final cleanup = () async {
      await _preparationDone?.future;
      await _release();
    }();
    _cleanup = cleanup;
    try {
      await cleanup;
    } finally {
      _cleanup = null;
    }
  }

  Future<void> _release() async {
    _cleanupFailed = true;
    Object? failure;
    for (final player in _owned.toList()) {
      try {
        await player.stop();
        await player.dispose();
        _owned.remove(player);
      } catch (error) {
        failure = error;
      }
    }
    await primary.setPitch(1);
    await primary.setSpeed(_baseSpeed);
    await applyGain(_gain);
    if (failure != null) {
      throw StateError('Mix resource cleanup failed: $failure');
    }
    _cleanupFailed = false;
    // Keep the identity through preparation so its catch can clean any player
    // that completed an asynchronous load after cancellation.
    if (!_preparing) _ownerId = null;
  }

  Future<void> dispose() async {
    _disposed = true;
    await cancel();
    await _errors.close();
  }
}
