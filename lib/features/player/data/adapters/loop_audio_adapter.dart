part of 'just_audio_adapter.dart';

final class _NativeLoopItem {
  final int loop;
  final LoopOccurrence occurrence;
  const _NativeLoopItem(this.loop, this.occurrence);
}

/// Keeps a bounded current/next native window while exposing only the current
/// materialized loop to ordinary player UI and the media notification.
class LoopAudioAdapter extends JustAudioAdapter
    with _ListeningAudio
    implements LoopQueuePort, SkillPlaybackPort {
  LoopQueue? _loops;
  final _tracks = <String, Track>{};
  List<String> _originalIds = [];
  List<_NativeLoopItem> _window = [];
  int _windowRevision = 0;
  int _occurrenceSequence = 0;
  bool _windowLoading = false;
  bool _closing = false;
  bool _stoppedAtEnd = false;
  final _ended = BehaviorSubject<bool>.seeded(false);
  void _setEnded(bool value) {
    _stoppedAtEnd = value;
    _ended.add(value);
  }

  Future<void> _queueTail = Future.value();
  Timer? _planTimer;
  int _planScheduleVersion = 0;
  final bool schedulePlanTimers;
  final _elapsed = Stopwatch()..start();
  late Future<Duration> Function() elapsedNow = () async => _elapsed.elapsed;
  Future<Track?> Function(String id)? resolveSong;
  Future<bool> Function(Track track)? canReadSong;
  Future<List<Track>> Function(String query, int limit)? searchSongs;

  LoopAudioAdapter({super.player, this.schedulePlanTimers = true});

  @override
  bool get listeningTransaction => _windowLoading;
  @override
  String? get listeningOccurrence {
    final index = _player.currentIndex;
    if (_loops == null ||
        _stoppedAtEnd ||
        index == null ||
        index < 0 ||
        index >= _window.length) {
      return null;
    }
    final item = _window[index];
    return '$sessionGeneration:${item.loop}:${item.occurrence.id}';
  }

  Future<T> _orderedQueue<T>(Future<T> Function() operation) {
    final result = _queueTail.then((_) => operation());
    _queueTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<Either<Failure, Unit>> _queueCommand(
    Future<void> Function() operation,
  ) => _orderedQueue(() async {
    try {
      await operation();
      return right(unit);
    } catch (e, st) {
      return left(ErrorHandler.handle(e, st));
    }
  });

  Future<Either<Failure, Unit>> _transportCommand(
    Future<void> Function() operation,
  ) {
    _intentRevision++;
    return _queueCommand(operation);
  }

  @override
  Track? get currentTrack => _stoppedAtEnd ? null : _currentQueue?.currentTrack;
  @override
  PlaybackStatus get currentStatus =>
      _stoppedAtEnd ? PlaybackStatus.stopped : super.currentStatus;
  @override
  Stream<PlaybackStatus> get statusStream => Rx.combineLatest2(
    super.statusStream,
    _ended.stream,
    (status, ended) => ended ? PlaybackStatus.stopped : status,
  );
  @override
  Stream<Track?> get currentTrackStream =>
      Rx.combineLatest2(
            _queueSubject.stream,
            _ended.stream,
            (queue, ended) => (
              sessionGeneration,
              _loops?.ordinal,
              queue.currentIndex,
              ended ? null : queue.currentTrack,
            ),
          )
          .distinct(
            (a, b) =>
                a.$1 == b.$1 &&
                a.$2 == b.$2 &&
                a.$3 == b.$3 &&
                a.$4?.id == b.$4?.id,
          )
          .map((value) => value.$4);
  @override
  LoopSnapshot? get currentLoop => _loops?.current;
  @override
  LoopSnapshot? previewLoop(int ordinal, Duration elapsed) =>
      _loops?.preview(ordinal, elapsed);

  LoopOccurrence _newOccurrence(Track track) {
    _tracks[track.id] = track;
    return LoopOccurrence(
      'base:$sessionGeneration:${_occurrenceSequence++}',
      SongReference(track.id),
    );
  }

  Track _track(LoopOccurrence item) => _tracks[item.song.libraryId]!;

  List<LoopOccurrence> _orderedLike(
    List<Track> tracks,
    List<LoopOccurrence> items,
  ) {
    final remaining = List<LoopOccurrence>.of(items);
    return [
      for (final track in tracks)
        remaining.removeAt(
          remaining.indexWhere((o) => o.song.libraryId == track.id),
        ),
    ];
  }

  Queue _visibleQueue(
    LoopQueue model,
    int index,
    bool shuffled,
    RepeatMode repeat,
  ) {
    final live = model.current.occurrences;
    final original = [
      for (final id in _originalIds) ...live.where((o) => o.id == id),
      ...live.where((o) => !_originalIds.contains(o.id)),
    ];
    return Queue(
      originalTracks: List.unmodifiable(
        (shuffled ? original : live).map(_track),
      ),
      playbackTracks: List.unmodifiable(live.map(_track)),
      currentIndex: index,
      shuffleEnabled: shuffled,
      repeatMode: repeat,
    );
  }

  /// Pause the native decoder during playlist transactions: an automatic
  /// boundary cannot cross a half-rebuilt provisional window. Playback intent
  /// remains authoritative if the user pauses while preparation is pending.
  Future<void> _render(
    LoopQueue model, {
    required int index,
    required Duration position,
    required RepeatMode repeat,
    required bool shuffled,
    bool start = false,
    bool? stopAtEnd,
  }) async {
    final expectedIndex = _player.currentIndex;
    final now = await elapsedNow();
    model.retireDue(now);
    final live = model.current.occurrences;
    final next = repeat == RepeatMode.all && live.isNotEmpty
        ? model.preview(model.ordinal + 1, now).occurrences
        : <LoopOccurrence>[];
    final window = [
      for (final item in live) _NativeLoopItem(model.ordinal, item),
      for (final item in next) _NativeLoopItem(model.ordinal + 1, item),
    ];
    final previous = _currentQueue;
    final oldWindow = _window;
    final oldPosition = _player.position;
    final oldIndex = _player.currentIndex ?? 0;
    final oldLive = _loops?.current.occurrences ?? <LoopOccurrence>[];
    final preserveDecoder =
        _loops?.sessionId == model.sessionId &&
        _loops?.ordinal == model.ordinal &&
        index == oldIndex &&
        oldLive.length == live.length &&
        List.generate(
          live.length,
          (i) => live[i].id == oldLive[i].id,
        ).every((same) => same);
    _windowLoading = true;
    var touchedSources = false;
    try {
      await _player.pause();
      if (_player.currentIndex != expectedIndex) {
        throw StateError(
          'Native playback advanced before the queue transaction.',
        );
      }
      _windowRevision++;
      touchedSources = true;
      _updateQueue(
        _visibleQueue(model, live.isEmpty ? 0 : index, shuffled, repeat),
      );
      if (live.isEmpty) {
        _fade.stop();
        await _player.stop();
        await _player.setAudioSources([]);
      } else {
        if (preserveDecoder) {
          if (oldWindow.length > live.length) {
            await _player.removeAudioSourceRange(live.length, oldWindow.length);
          }
          if (next.isNotEmpty) {
            await _player.addAudioSources(
              next.map((o) => _toAudioSource(_track(o))).toList(),
            );
          }
        } else {
          await _player.setAudioSources(
            window.map((i) => _toAudioSource(_track(i.occurrence))).toList(),
            initialIndex: index,
            initialPosition: position,
          );
        }
        await _player.setLoopMode(
          repeat == RepeatMode.one ? LoopMode.one : LoopMode.off,
        );
      }
      _loops = model;
      _window = window;
      _setEnded(live.isEmpty || (stopAtEnd ?? (!start && _stoppedAtEnd)));
      _updateQueue(
        _visibleQueue(model, live.isEmpty ? 0 : index, shuffled, repeat),
      );
      if (_stoppedAtEnd) {
        _setPlayIntent(false);
        await _player.stop();
      } else if (start || _playIntent.value) {
        if (start) {
          await _play();
        } else {
          _playInBackground();
        }
      }
    } catch (_) {
      if (!touchedSources) {
        if (_playIntent.value) _playInBackground();
      } else if (previous != null) {
        _updateQueue(previous);
        try {
          await _player.setAudioSources(
            oldWindow.map((i) => _toAudioSource(_track(i.occurrence))).toList(),
            initialIndex: oldIndex,
            initialPosition: oldPosition,
          );
          if (_playIntent.value) _playInBackground();
        } catch (_) {
          _setPlayIntent(false);
          await _player.stop();
        }
      }
      rethrow;
    } finally {
      _windowLoading = false;
      _sampleListening(notify: true);
      if (!touchedSources) _onNativeIndex(_player.currentIndex);
      _schedulePlans();
    }
  }

  void _schedulePlans() {
    _planTimer?.cancel();
    final scheduleVersion = ++_planScheduleVersion;
    final deadline = _loops?.nextDeadline;
    if (_closing || !schedulePlanTimers || deadline == null) return;
    unawaited(
      elapsedNow().then((now) {
        if (_closing ||
            scheduleVersion != _planScheduleVersion ||
            _loops?.nextDeadline != deadline) {
          return;
        }
        _planTimer = Timer(
          deadline > now ? deadline - now : const Duration(seconds: 1),
          () {
            unawaited(
              _queueCommand(() async {
                final model = _loops?.copy();
                if (model == null || !model.retireDue(await elapsedNow())) {
                  return;
                }
                await _render(
                  model,
                  index: _currentQueue!.currentIndex,
                  position: _player.position,
                  repeat: _currentQueue!.repeatMode,
                  shuffled: _currentQueue!.shuffleEnabled,
                );
              }),
            );
          },
        );
      }),
    );
  }

  @override
  void _onNativeIndex(int? index) {
    if (_windowLoading ||
        _closing ||
        index == null ||
        index < 0 ||
        index >= _window.length) {
      return;
    }
    final version = _windowRevision;
    final item = _window[index];
    unawaited(
      _queueCommand(() async {
        if (version != _windowRevision || _loops == null) return;
        final model = _loops!;
        if (item.loop == model.ordinal) {
          _updateQueue(_currentQueue!.copyWith(currentIndex: index));
        } else if (item.loop == model.ordinal + 1) {
          final draft = model.copy()..enterNext(await elapsedNow());
          final at = draft.current.occurrences.indexWhere(
            (o) => o.id == item.occurrence.id,
          );
          // A deadline crossed before this native observation was processed.
          // Never map the obsolete native index onto another occurrence.
          await _render(
            draft,
            index: at < 0 ? 0 : at,
            position: at < 0 ? Duration.zero : _player.position,
            repeat: _currentQueue!.repeatMode,
            shuffled: _currentQueue!.shuffleEnabled,
          );
        }
      }),
    );
  }

  @override
  void _onQueueCompleted() {
    if (_windowLoading || _closing) return;
    final version = _windowRevision;
    unawaited(
      _queueCommand(() async {
        if (version != _windowRevision) return;
        if (_currentQueue?.repeatMode == RepeatMode.all &&
            _loops != null &&
            _playIntent.value) {
          await _render(
            _loops!.copy()..enterNext(await elapsedNow()),
            index: 0,
            position: Duration.zero,
            repeat: RepeatMode.all,
            shuffled: _currentQueue!.shuffleEnabled,
          );
        } else {
          super._onQueueCompleted();
        }
      }),
    );
  }

  @override
  Future<Either<Failure, Unit>> setQueue(
    List<Track> tracks, {
    int startIndex = 0,
    bool? shuffle,
  }) => _transportCommand(() async {
    if (tracks.isEmpty || startIndex < 0 || startIndex >= tracks.length) {
      throw ArgumentError('Queue is empty or index is invalid.');
    }
    final queue = Queue.fromTracks(
      tracks,
      startIndex: startIndex,
      shuffleEnabled: shuffle ?? _currentQueue?.shuffleEnabled ?? false,
      repeatMode: _currentQueue?.repeatMode ?? RepeatMode.off,
    );
    await _startSession(queue, Duration.zero, true);
  });

  Future<void> _startSession(Queue queue, Duration position, bool play) async {
    _planTimer?.cancel();
    final previousOriginalIds = _originalIds;
    final originals = queue.originalTracks.map(_newOccurrence).toList();
    _originalIds = originals.map((o) => o.id).toList();
    final model = LoopQueue(
      'playback-${sessionGeneration + 1}',
      _orderedLike(queue.playbackTracks, originals),
    );
    if (!play) _setPlayIntent(false);
    try {
      await _render(
        model,
        index: queue.currentIndex,
        position: position,
        repeat: queue.repeatMode,
        shuffled: queue.shuffleEnabled,
        start: play,
        stopAtEnd: false,
      );
      _replaceSession();
    } catch (_) {
      _originalIds = previousOriginalIds;
      rethrow;
    }
  }

  @override
  Future<Either<Failure, Unit>> playTrack(Track track, {Queue? queue}) =>
      queue == null
      ? setQueue([track])
      : setQueue(queue.originalTracks, startIndex: queue.currentIndex);
  @override
  Future<Either<Failure, Unit>> restoreQueue(
    Queue queue, {
    required Duration position,
    required bool play,
    required double volume,
    required double speed,
  }) => _transportCommand(() async {
    await _startSession(queue, position, play);
    await setVolume(volume.clamp(0, 1));
    await setSpeed(speed.clamp(0.5, 2));
  });

  Future<void> _navigate(
    int index, {
    bool nextLoop = false,
    bool play = false,
  }) async {
    if (_loops == null || _currentQueue!.isEmpty) return;
    if (nextLoop) {
      await _render(
        _loops!.copy()..enterNext(await elapsedNow()),
        index: 0,
        position: Duration.zero,
        repeat: _currentQueue!.repeatMode,
        shuffled: _currentQueue!.shuffleEnabled,
        start: play,
        stopAtEnd: false,
      );
    } else {
      _setEnded(false);
      await _switchTrack(() => _player.seek(Duration.zero, index: index));
      // Native seek can re-emit the previous index before its target. Those
      // observations wait behind this command; discard them before publishing
      // the completed transition so callers never see it temporarily undone.
      _windowRevision++;
      _updateQueue(_currentQueue!.copyWith(currentIndex: index));
      if (play) await _play();
    }
  }

  @override
  Future<Either<Failure, Unit>> skipToNext() => _transportCommand(() async {
    final q = _currentQueue;
    if (q == null || q.isEmpty) return;
    if (q.currentIndex + 1 < q.length) {
      await _navigate(q.currentIndex + 1);
    } else if (q.repeatMode == RepeatMode.all) {
      await _navigate(0, nextLoop: true);
    }
  });
  @override
  Future<Either<Failure, Unit>> skipToPrevious() => _transportCommand(() async {
    final q = _currentQueue;
    if (q == null || q.isEmpty) return;
    if (q.currentIndex > 0) {
      await _navigate(q.currentIndex - 1);
    } else if (q.repeatMode == RepeatMode.all) {
      await _navigate(q.length - 1);
    }
  });
  @override
  Future<Either<Failure, Unit>> skipToIndex(int index) =>
      _transportCommand(() async {
        if (_currentQueue == null ||
            index < 0 ||
            index >= _currentQueue!.length) {
          throw ArgumentError('Queue index is invalid.');
        }
        await _navigate(index, play: true);
      });

  Future<void> _ordinaryEdit(
    List<LoopOccurrence> baseline,
    List<LoopOccurrence> live, {
    String? removed,
  }) async {
    final old = _loops!.current.occurrences;
    final oldIndex = _currentQueue!.currentIndex;
    final currentId = old.isEmpty ? null : old[oldIndex].id;
    var index = live.indexWhere((o) => o.id == currentId);
    var stopAtEnd = false;
    if (index < 0) {
      final successors = old.skip(oldIndex + 1).map((o) => o.id).toSet();
      index = live.indexWhere((o) => successors.contains(o.id));
      if (index < 0) {
        stopAtEnd = true;
        index = live.isEmpty ? 0 : live.length - 1;
      }
    }
    final draft = _loops!.copy()..replaceBaseline(baseline, live);
    await _render(
      draft,
      index: index,
      position: currentId == removed ? Duration.zero : _player.position,
      repeat: _currentQueue!.repeatMode,
      shuffled: _currentQueue!.shuffleEnabled,
      stopAtEnd: stopAtEnd,
    );
  }

  @override
  Future<Either<Failure, Unit>> addToQueue(Track track, {int? index}) =>
      _queueCommand(() async {
        if (_loops == null) throw StateError('No queue.');
        final live = List<LoopOccurrence>.of(_loops!.current.occurrences);
        final baseline = List<LoopOccurrence>.of(_loops!.baseline);
        final at = (index ?? live.length).clamp(0, live.length);
        final anchor = at < live.length
            ? baseline.indexWhere((o) => o.id == live[at].id)
            : -1;
        final item = _newOccurrence(track);
        live.insert(at, item);
        baseline.insert(anchor < 0 ? baseline.length : anchor, item);
        await _ordinaryEdit(baseline, live);
        _originalIds.add(item.id);
      });
  @override
  Future<Either<Failure, Unit>> removeFromQueue(int index) =>
      _queueCommand(() async {
        final live = List<LoopOccurrence>.of(_loops?.current.occurrences ?? []);
        if (index < 0 || index >= live.length) return;
        final removed = live.removeAt(index);
        await _ordinaryEdit(
          _loops!.baseline.where((o) => o.id != removed.id).toList(),
          live,
          removed: removed.id,
        );
        _originalIds.remove(removed.id);
      });
  @override
  Future<Either<Failure, Unit>> moveQueueItem(int oldIndex, int newIndex) =>
      _queueCommand(() async {
        final live = List<LoopOccurrence>.of(_loops!.current.occurrences);
        final item = live.removeAt(oldIndex);
        live.insert(newIndex, item);
        final byId = {for (final o in _loops!.baseline) o.id: o};
        final baseline = [
          for (final o in live)
            if (byId.containsKey(o.id)) byId.remove(o.id)!,
          ...byId.values,
        ];
        await _ordinaryEdit(baseline, live);
        if (!_currentQueue!.shuffleEnabled) {
          _originalIds = baseline.map((o) => o.id).toList();
        }
      });
  @override
  Future<Either<Failure, Unit>> setRepeatMode(RepeatMode mode) =>
      _queueCommand(() async {
        if (_loops == null) return;
        await _render(
          _loops!.copy(),
          index: _currentQueue!.currentIndex,
          position: _player.position,
          repeat: mode,
          shuffled: _currentQueue!.shuffleEnabled,
        );
      });
  @override
  Future<Either<Failure, Unit>> setShuffleEnabled(bool enabled) =>
      _queueCommand(() async {
        if (_loops == null ||
            _currentQueue!.shuffleEnabled == enabled ||
            _currentQueue!.isEmpty) {
          return;
        }
        final live = List<LoopOccurrence>.of(_loops!.current.occurrences);
        final current = live[_currentQueue!.currentIndex];
        final baseline = List<LoopOccurrence>.of(_loops!.baseline);
        if (enabled) {
          live.remove(current);
          live.shuffle(Random());
          live.insert(0, current);
          baseline.shuffle(Random());
        } else {
          int rank(LoopOccurrence o) {
            final i = _originalIds.indexOf(o.id);
            return i < 0 ? _originalIds.length : i;
          }

          live.sort((a, b) => rank(a).compareTo(rank(b)));
          baseline.sort((a, b) => rank(a).compareTo(rank(b)));
        }
        final draft = _loops!.copy()..replaceBaseline(baseline, live);
        await _render(
          draft,
          index: live.indexOf(current),
          position: _player.position,
          repeat: _currentQueue!.repeatMode,
          shuffled: enabled,
        );
      });

  @override
  Future<List<SongReference>> findSkillSongs(
    String query, {
    int limit = 50,
  }) async {
    if (limit < 1 || limit > 200) throw ArgumentError.value(limit, 'limit');
    final found =
        await searchSongs?.call(query, limit) ??
        _tracks.values
            .where((t) => t.title.toLowerCase().contains(query.toLowerCase()))
            .take(limit)
            .toList();
    return List.unmodifiable(
      found.take(limit).map((t) {
        _tracks[t.id] = t;
        return SongReference(t.id);
      }),
    );
  }

  @override
  Future<LoopEditResult> editLoopQueue(
    EditLoopQueue request, {
    required String sessionId,
    required int expectedLoop,
    required String planId,
    required Duration elapsed,
  }) => _orderedQueue(() async {
    if (_loops == null) {
      return const LoopEditResult(
        CapabilityStatus.denied,
        'No playback session.',
        0,
      );
    }
    for (final insertion in request.operations.whereType<InsertSong>()) {
      final track =
          await resolveSong?.call(insertion.song.libraryId) ??
          _tracks[insertion.song.libraryId];
      if (track == null ||
          (track.path.isEmpty && track.uri.isEmpty) ||
          !(await canReadSong?.call(track) ?? true)) {
        return LoopEditResult(
          CapabilityStatus.failed,
          'The requested song is unavailable.',
          _loops!.revision,
        );
      }
      _tracks[track.id] = track;
    }
    await _synchronizeNative();
    final model = _loops!;
    final draft = model.copy();
    final result = draft.edit(
      session: sessionId,
      expectedLoop: expectedLoop,
      planId: planId,
      request: request,
      elapsed: await elapsedNow(),
    );
    if (result.status != CapabilityStatus.applied) return result;
    final old = model.current.occurrences;
    final oldIndex = _currentQueue!.currentIndex;
    final live = draft.current.occurrences;
    final currentId = old.isEmpty ? null : old[oldIndex].id;
    var index = live.indexWhere((o) => o.id == currentId);
    final removedCurrent = index < 0;
    var stopAtEnd = false;
    if (index < 0) {
      final successors = old.skip(oldIndex + 1).map((o) => o.id).toSet();
      index = live.indexWhere((o) => successors.contains(o.id));
      if (index < 0) {
        stopAtEnd = true;
        index = live.isEmpty ? 0 : live.length - 1;
      }
    }
    try {
      await _render(
        draft,
        index: index,
        position: removedCurrent ? Duration.zero : _player.position,
        repeat: _currentQueue!.repeatMode,
        shuffled: _currentQueue!.shuffleEnabled,
        stopAtEnd: stopAtEnd,
      );
      return LoopEditResult(
        result.status,
        result.reason,
        draft.revision,
        deadline: result.deadline,
      );
    } catch (_) {
      return LoopEditResult(
        CapabilityStatus.failed,
        'Native queue preparation failed.',
        model.revision,
      );
    }
  });
  Future<void> _synchronizeNative() async {
    final index = _player.currentIndex;
    if (_loops == null ||
        index == null ||
        index < 0 ||
        index >= _window.length) {
      return;
    }
    final item = _window[index];
    if (item.loop == _loops!.ordinal) {
      _updateQueue(_currentQueue!.copyWith(currentIndex: index));
    } else if (item.loop == _loops!.ordinal + 1) {
      final draft = _loops!.copy()..enterNext(await elapsedNow());
      final at = draft.current.occurrences.indexWhere(
        (o) => o.id == item.occurrence.id,
      );
      await _render(
        draft,
        index: at < 0 ? 0 : at,
        position: at < 0 ? Duration.zero : _player.position,
        repeat: _currentQueue!.repeatMode,
        shuffled: _currentQueue!.shuffleEnabled,
      );
    }
  }

  @override
  Future<void> revokeLoopPlan(
    String sessionId,
    String planId,
    Duration elapsed,
  ) => _orderedQueue(() async {
    if (_loops?.sessionId != sessionId) return;
    final draft = _loops!.copy();
    if (!draft.revoke(planId)) return;
    draft.retireDue(elapsed);
    await _render(
      draft,
      index: _currentQueue!.currentIndex,
      position: _player.position,
      repeat: _currentQueue!.repeatMode,
      shuffled: _currentQueue!.shuffleEnabled,
    );
  });
  @override
  Future<void> stop() {
    _setPlayIntent(false);
    return _orderedQueue(() async {
      _planTimer?.cancel();
      _loops = null;
      _setEnded(true);
      await super.stop();
    });
  }

  @override
  Future<Either<Failure, Unit>> resume() => _transportCommand(() async {
    if (_currentQueue == null || _currentQueue!.isEmpty) return;
    if (_loops == null) {
      await _startSession(_currentQueue!, _player.position, true);
    } else if (_stoppedAtEnd) {
      await _navigate(0, play: true);
    } else {
      (await super.resume()).fold((failure) => throw failure, (_) {});
    }
  });
  @override
  Future<void> dispose() async {
    _closing = true;
    _planTimer?.cancel();
    await _queueTail;
    await _disposeListening();
    await _ended.close();
    await super.dispose();
  }
}
