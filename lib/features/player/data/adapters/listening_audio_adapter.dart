part of 'just_audio_adapter.dart';

/// Native decoder transitions own the clock; widgets only consume snapshots.
mixin _ListeningAudio on JustAudioAdapter {
  final _listening = ListeningClock();
  final _listeningElapsed = Stopwatch()..start();
  late Duration Function() listeningNow = () => _listeningElapsed.elapsed;
  final _listeningChanges = StreamController<void>.broadcast(sync: true);
  final _listeningSubscriptions = <StreamSubscription<dynamic>>[];
  SkillPlaybackSnapshot _lastListening = const SkillPlaybackSnapshot();
  bool _trackingListening = false;
  int _naturalPlay = 0;

  String? get listeningOccurrence;
  bool get listeningTransaction;

  void _startListening() {
    if (_trackingListening) return;
    _trackingListening = true;
    _listeningSubscriptions.addAll([
      _player.playerStateStream.listen((_) => _sampleListening(notify: true)),
      _playIntent.listen((_) => _sampleListening(notify: true)),
      _queueSubject.listen((_) => _sampleListening(notify: true)),
      _sessionGenerations.listen((_) => _sampleListening(notify: true)),
      _player.positionDiscontinuityStream.listen((event) {
        if (!listeningTransaction &&
            event.reason == PositionDiscontinuityReason.autoAdvance) {
          _naturalPlay++;
          _sampleListening(notify: true);
        }
      }),
    ]);
    _sampleListening();
  }

  SkillPlaybackSnapshot _sampleListening({bool notify = false}) {
    if (!_trackingListening) return _lastListening;
    final native = _player.playerState;
    final occurrence = listeningTransaction ? null : listeningOccurrence;
    // Preserve the current play while a queue transaction rebuilds sources.
    final playId = listeningTransaction
        ? _lastListening.playId
        : occurrence == null ||
              native.processingState == ProcessingState.completed
        ? null
        : '$occurrence:$_naturalPlay';
    _lastListening = _listening.sample(
      playId: playId,
      playing:
          !listeningTransaction &&
          native.playing &&
          _playIntent.value &&
          native.processingState == ProcessingState.ready,
      elapsed: listeningNow(),
    );
    if (notify && !_listeningChanges.isClosed) _listeningChanges.add(null);
    return _lastListening;
  }

  SkillPlaybackSnapshot get skillPlayback {
    _startListening();
    return _sampleListening();
  }

  Stream<void> get skillPlaybackChanges {
    _startListening();
    return _listeningChanges.stream;
  }

  Future<void> _disposeListening() async {
    for (final subscription in _listeningSubscriptions) {
      await subscription.cancel();
    }
    await _listeningChanges.close();
  }
}
