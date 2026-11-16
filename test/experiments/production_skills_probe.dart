// Android-only acceptance. Uses in-memory profiles; never edits saved setup.
import 'dart:async';
import 'dart:convert';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:troona/features/player/data/adapters/audio_handler_impl.dart';
import 'package:troona/features/player/data/adapters/just_audio_adapter.dart';
import 'package:troona/features/player_actions/data/playback_commands_adapter.dart';
import 'package:troona/features/player_actions/domain/action_dispatcher.dart';
import 'package:troona/features/player_skills/data/android_skill_clock.dart';
import 'package:troona/features/player_skills/domain/skill_assignments.dart';
import 'package:troona/features/player_skills/domain/skill_policy.dart';
import 'package:troona/features/profiles/domain/profile_catalog.dart';
import 'package:troona/features/profiles/domain/profile_repository.dart';
import 'package:troona/features/profiles/domain/effective_bindings.dart';
import 'package:troona/features/input_bindings/domain/combo_input.dart';
import 'package:troona/features/settings/domain/entities/app_settings.dart';
import 'package:troona/services/audio/audio_session_service.dart';
import 'package:troona/skills/skill.dart';
import 'integrated_mixer_probe.dart' show track;
import 'mixer_probe.dart' show tone;

class _Profiles implements ProfileDocumentStore {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String document) async {}
}

class _Skills implements SkillAssignmentStore {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String document) async {}
}

final label = ValueNotifier<String>('Starting production skills probe');
void report(String phase, Map<String, Object?> data) {
  label.value = phase;
  debugPrint('PRODUCTION_SKILLS ${jsonEncode({'phase': phase, ...data})}');
}

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final audio = MixAudioAdapter()..elapsedNow = const AndroidSkillClock().now;
  await AudioService.init(
    builder: () => AudioHandlerImpl(audio),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.hadoken.player.skillsprobe',
      androidNotificationChannelName: 'Production skills probe',
    ),
  );
  final session = AudioSessionService(audio, const AppSettings());
  await session.init();
  runApp(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: ValueListenableBuilder<String>(
            valueListenable: label,
            builder: (_, value, _) => Text(value),
          ),
        ),
      ),
    ),
  );
  unawaited(
    runProbe(audio).then((_) => session.dispose()).catchError((
      Object e,
      StackTrace st,
    ) {
      report('failed', {'error': '$e', 'stack': '$st'});
    }),
  );
}

Future<void> runProbe(MixAudioAdapter audio) async {
  final profiles = await ProfileRepository.open(_Profiles());
  await profiles.addProfile();
  await profiles.addProfile();
  for (final player in ProfileId.values) {
    await profiles.setBinding(player, PlayerAction.nextTrack, [
      Stroke(InputButton.values[player.index], StrokeKind.tap),
    ]);
  }
  await profiles.setSkillMacro(ProfileId.p2, 'force-skip', const [
    Stroke(InputButton.pause, StrokeKind.hold),
  ]);
  final assignments = await SkillAssignmentRepository.open(
    _Skills(),
    profileExists: (_) => true,
  );
  await assignments.setAssigned(ProfileId.p1, SkillId.songCommitment, true);
  await assignments.setAssigned(ProfileId.p2, SkillId.forceSkip, true);
  final policy =
      SkillPolicy(assignments: assignments, clock: const AndroidSkillClock())
        ..bindPlaybackObservations(audio)
        ..observeSessions(audio.sessionGenerations, audio.sessionGeneration);
  final effective = EffectiveBindings(
    profiles: profiles,
    macroEnabled: policy.macroEnabled,
  );
  final dispatcher = PlayerActionDispatcher(
    playback: PlaybackCommandsAdapter(audio),
    catalog: () => effective.catalog,
    abilities: policy,
  );
  var sequence = 0;
  PlayerActionRequest input(ExecutableBinding binding) => PlayerActionRequest(
    requestId: 'probe-${sequence++}',
    binding: binding,
    recognizedAt: Duration.zero,
    effort: dispatcher.effortFor(binding),
    observations: [
      for (final stroke in binding.strokes)
        StrokeObservation(
          stroke,
          Duration.zero,
          const Duration(milliseconds: 800),
          null,
        ),
    ],
  );
  final directory = await getTemporaryDirectory();
  final a = track('a', await tone(directory, 'skill-440', frequency: 440));
  final b = track('b', await tone(directory, 'skill-880', frequency: 880));
  await audio.setQueue([a, b]);
  await Future<void>.delayed(const Duration(seconds: 3));
  final beforePause = audio.skillPlayback.listened;
  await audio.pause(fade: Duration.zero);
  await Future<void>.delayed(const Duration(seconds: 2));
  await audio.seekTo(const Duration(seconds: 30));
  check(
    (audio.skillPlayback.listened - beforePause).inMilliseconds.abs() < 500,
    'Pause or seek counted as listening',
  );
  await audio.seekTo(Duration.zero);
  await audio.resume();
  report('listening', {
    'listenedMs': audio.skillPlayback.listened.inMilliseconds,
  });
  final timeout = DateTime.now().add(const Duration(seconds: 35));
  while (audio.skillPlayback.listened < const Duration(seconds: 21)) {
    if (DateTime.now().isAfter(timeout)) {
      throw StateError('Listening threshold timed out');
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  final lockedPlay = audio.skillPlayback.playId;
  final results = <String, String>{};
  for (final player in ProfileId.values) {
    final outcome = await dispatcher.dispatch(
      input(effective.catalog.bindingFor(player, PlayerAction.nextTrack)!),
    );
    results[player.name] = outcome.result.status.name;
    check(
      outcome.result.status == ActionStatus.denied,
      'Ordinary skip escaped lock',
    );
  }
  check(audio.currentTrack?.id == 'a', 'Denied skip changed track');
  report('locked', {
    'players': results,
    'listenedMs': audio.skillPlayback.listened.inMilliseconds,
  });
  final force = input(effective.catalog.macroFor(ProfileId.p2, 'force-skip')!);
  report('before-force', {
    'status': audio.currentStatus.name,
    'index': audio.currentQueue?.currentIndex,
    'order': audio.currentQueue?.playbackTracks.map((t) => t.id).toList(),
    'playId': audio.skillPlayback.playId,
  });
  final outcome = await dispatcher.dispatch(force);
  report('force-result', {
    'status': outcome.result.status.name,
    'message': outcome.result.message,
    'nativeStatus': audio.currentStatus.name,
    'index': audio.currentQueue?.currentIndex,
    'order': audio.currentQueue?.playbackTracks.map((t) => t.id).toList(),
    'playId': audio.skillPlayback.playId,
  });

  check(
    outcome.result.succeeded,
    'Force Skip failed: ${outcome.result.message}',
  );
  await dispatcher.dispatch(force);
  check(audio.currentTrack?.id == 'b', 'Force Skip did not advance once');
  check(
    audio.skillPlayback.playId != lockedPlay &&
        audio.skillPlayback.listened < const Duration(seconds: 2),
    'New song retained lock',
  );
  final end = await dispatcher.dispatch(
    input(effective.catalog.macroFor(ProfileId.p2, 'force-skip')!),
  );
  check(end.result.status == ActionStatus.noOp, 'End of queue claimed success');
  report('passed', {
    'forceEffort': force.effort.value,
    'track': audio.currentTrack?.id,
    'newListenedMs': audio.skillPlayback.listened.inMilliseconds,
    'endOfQueue': end.result.status.name,
  });
  await audio.stop();
  await dispatcher.dispose();
  await policy.dispose();
  await effective.dispose();
  await assignments.dispose();
  await profiles.dispose();
}
