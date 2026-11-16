import 'dart:async';
import 'package:just_audio/just_audio.dart';
import 'package:troona/features/library/domain/entities/track.dart';

final class LoopPlayer implements AudioPlayer {
  final states = StreamController<PlayerState>.broadcast(sync: true);
  final discontinuities = StreamController<PositionDiscontinuity>.broadcast(
    sync: true,
  );
  ProcessingState state = ProcessingState.ready;
  void setProcessing(ProcessingState value) {
    state = value;
    processing.add(value);
    states.add(playerState);
  }

  void repeatNaturally() {
    final previous = PlaybackEvent(
      currentIndex: index,
      updatePosition: position,
    );
    position = Duration.zero;
    discontinuities.add(
      PositionDiscontinuity(
        PositionDiscontinuityReason.autoAdvance,
        previous,
        PlaybackEvent(currentIndex: index, updatePosition: position),
      ),
    );
  }

  @override
  Stream<PlayerState> get playerStateStream => states.stream;
  @override
  Stream<PositionDiscontinuity> get positionDiscontinuityStream =>
      discontinuities.stream;
  final indices = StreamController<int?>.broadcast(sync: true);
  final processing = StreamController<ProcessingState>.broadcast(sync: true);
  List<Track> tracks = [];
  final loads = <List<String>>[];
  Completer<void>? loadGate;
  bool failNextLoad = false;
  bool disposed = false;
  int stops = 0;
  int? index = 0;
  LoopMode mode = LoopMode.off;
  @override
  double volume = 1;
  @override
  double speed = 1;
  @override
  double pitch = 1;
  bool failDispose = false;
  final sources = <AudioSource>[];
  @override
  bool playing = false;
  @override
  Duration position = Duration.zero;
  @override
  Duration? get duration => const Duration(minutes: 1);
  @override
  PlayerState get playerState => PlayerState(playing, state);
  @override
  Stream<int?> get currentIndexStream => indices.stream;
  @override
  Stream<ProcessingState> get processingStateStream => processing.stream;
  @override
  int? get currentIndex => index;
  void advance(int value) {
    index = value;
    position = Duration.zero;
    indices.add(value);
  }

  void complete() => setProcessing(ProcessingState.completed);
  @override
  Future<Duration?> setAudioSources(
    List<AudioSource> sources, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
    ShuffleOrder? shuffleOrder,
  }) async {
    final gate = loadGate;
    loadGate = null;
    if (gate != null) await gate.future;
    if (failNextLoad) {
      failNextLoad = false;
      throw StateError('load failed');
    }
    tracks = sources
        .map((s) => (s as IndexedAudioSource).tag as Track)
        .toList();
    loads.add(tracks.map((t) => t.id).toList());
    position = initialPosition ?? Duration.zero;
    advance(initialIndex ?? 0);
    position = initialPosition ?? Duration.zero;
    return duration;
  }

  @override
  Future<void> removeAudioSourceRange(int start, int end) async =>
      tracks.removeRange(start, end);
  @override
  Future<void> addAudioSources(List<AudioSource> sources) async =>
      tracks.addAll(sources.map((s) => (s as IndexedAudioSource).tag as Track));
  @override
  Future<void> setLoopMode(LoopMode mode) async => this.mode = mode;
  @override
  Future<void> setVolume(double volume) async => this.volume = volume;
  @override
  Future<void> setSpeed(double speed) async => this.speed = speed;
  @override
  Future<void> setPitch(double pitch) async => this.pitch = pitch;
  @override
  Future<Duration?> setAudioSource(
    AudioSource source, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
  }) async {
    sources.add(source);
    final gate = loadGate;
    loadGate = null;
    if (gate != null) await gate.future;
    if (failNextLoad) {
      failNextLoad = false;
      throw StateError('load failed');
    }
    position = initialPosition ?? Duration.zero;
    return duration;
  }

  @override
  Future<void> play() async {
    playing = true;
    states.add(playerState);
  }

  @override
  Future<void> pause() async {
    playing = false;
    states.add(playerState);
  }

  @override
  Future<void> stop() async {
    playing = false;
    stops++;
    states.add(playerState);
  }

  @override
  Future<void> seek(Duration? position, {int? index}) async {
    if (index != null) advance(index);
    this.position = position ?? Duration.zero;
  }

  @override
  Future<void> dispose() async {
    if (failDispose) throw StateError('dispose failed');
    disposed = true;
    await indices.close();
    await processing.close();
    await states.close();
    await discontinuities.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
