part of 'just_audio_adapter.dart';

/// One media session owns the primary decoder and all temporary layers.
class MixAudioAdapter extends LoopAudioAdapter
    implements SkillAudioEffectsPort {
  final AudioPlayer Function()? layerFactory;
  final Future<Uri> Function() noiseSource;
  final bool scheduleMixTimers;
  @override
  final bool supportsAudioMix;
  double _duckGain = 1;
  final _userSpeed = BehaviorSubject<double>.seeded(1);
  late final SkillMixer _mixer = SkillMixer(
    primary: _player,
    createPlayer:
        layerFactory ??
        () => AudioPlayer(
          handleInterruptions: false,
          handleAudioSessionActivation: false,
        ),
    sourceFor: (layer) async {
      if (layer.kind == MixLayerKind.noise) {
        return AudioSource.uri(await noiseSource());
      }
      final track =
          await resolveSong?.call(layer.song!.libraryId) ??
          _tracks[layer.song!.libraryId];
      if (track == null || !(await canReadSong?.call(track) ?? true)) {
        throw StateError('Mix song is unavailable.');
      }
      return _toAudioSource(track);
    },
    now: () => elapsedNow(),
    sessionId: () => _loops?.sessionId ?? '',
    sourceIdentity: () => _identity(_loops, _currentQueue?.currentIndex ?? 0),
    currentSong: () => currentTrack?.id,
    playIntent: () => _playIntent.value && !_stoppedAtEnd,
    supported: supportsAudioMix,
    scheduleTimers: scheduleMixTimers,
  );
  MixAudioAdapter({
    super.player,
    super.schedulePlanTimers,
    this.layerFactory,
    this.noiseSource = createNoiseSource,
    this.scheduleMixTimers = true,
    bool? supportsAudioMix,
  }) : supportsAudioMix = supportsAudioMix ?? Platform.isAndroid;

  String _identity(LoopQueue? model, int index) {
    final items = model?.current.occurrences ?? <LoopOccurrence>[];
    return '${model?.sessionId}:${model?.ordinal}:${index < items.length ? items[index].id : "ended"}';
  }

  @override
  Stream<Failure> get errorStream => Rx.merge([
    super.errorStream,
    _mixer.errors.map((message) => PlaybackFailure(message)),
  ]);
  @override
  Stream<double> get speedStream => _userSpeed.stream;
  @override
  Future<void> _applyGain(double gain) =>
      _mixer.applyGain(_volume * gain * _duckGain);
  @override
  Future<void> setDuckGain(double gain) async {
    if (!gain.isFinite || gain < 0 || gain > 1) throw ArgumentError.value(gain);
    _duckGain = gain;
    await _applyGain(_fade.gain);
  }

  @override
  Future<Either<Failure, Unit>> setSpeed(double speed) async {
    try {
      await _mixer.applySpeed(speed);
      _userSpeed.add(speed);
      return right(unit);
    } catch (e, st) {
      return left(ErrorHandler.handle(e, st));
    }
  }

  @override
  Future<AudioMixResult> startAudioMix(
    StartAudioMix request, {
    required String id,
    required String sessionId,
  }) => _orderedQueue(() async {
    await _synchronizeNative();
    return _mixer.start(request, id: id, session: sessionId);
  });
  @override
  Future<void> stopAudioMix(String id) => _mixer.cancel(id);

  @override
  Future<void> _render(
    LoopQueue model, {
    required int index,
    required Duration position,
    required RepeatMode repeat,
    required bool shuffled,
    bool start = false,
    bool? stopAtEnd,
  }) async {
    if (_loops?.sessionId != model.sessionId ||
        stopAtEnd == true ||
        model.current.occurrences.isEmpty) {
      await _mixer.cancel();
    } else {
      await _mixer.sourceChanged(nextIdentity: _identity(model, index));
    }
    await super._render(
      model,
      index: index,
      position: position,
      repeat: repeat,
      shuffled: shuffled,
      start: start,
      stopAtEnd: stopAtEnd,
    );
    await _mixer.synchronize();
  }

  @override
  Future<void> _navigate(
    int index, {
    bool nextLoop = false,
    bool play = false,
  }) async {
    if (!nextLoop) {
      await _mixer.sourceChanged(nextIdentity: _identity(_loops, index));
    }
    await super._navigate(index, nextLoop: nextLoop, play: play);
    await _mixer.synchronize();
  }

  @override
  void _updateQueue(Queue queue) {
    super._updateQueue(queue);
    if (!_windowLoading) _background(_mixer.sourceChanged());
  }

  void _background(Future<void> future) => unawaited(
    future.catchError((Object e, StackTrace st) {
      ErrorHandler.handle(e, st);
    }),
  );
  @override
  void _playInBackground() {
    super._playInBackground();
    _background(_mixer.synchronize());
  }

  @override
  void _onQueueCompleted() {
    super._onQueueCompleted();
    _background(_orderedQueue(() => _mixer.synchronize()));
  }

  @override
  Future<Either<Failure, Unit>> pause({
    Duration fade = AudioServicePort.pauseFade,
  }) async {
    final result = await super.pause(fade: fade);
    await _mixer.synchronize();
    return result;
  }

  @override
  Future<Either<Failure, Unit>> resume() async {
    final result = await super.resume();
    await _mixer.synchronize();
    return result;
  }

  @override
  Future<void> stop() async {
    _playIntent.add(false);
    await _mixer.cancel();
    await super.stop();
  }

  @override
  Future<void> dispose() async {
    _closing = true;
    await _queueTail;
    await _mixer.dispose();
    await _userSpeed.close();
    await super.dispose();
  }
}
