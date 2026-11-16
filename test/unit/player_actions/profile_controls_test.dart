import 'package:flutter_test/flutter_test.dart';
import 'package:troona/features/input_bindings/domain/combo_input.dart';
import 'package:troona/features/player_actions/data/playback_commands_adapter.dart';
import 'package:troona/features/player_actions/domain/action_dispatcher.dart';
import 'package:troona/features/player_actions/profile_controls.dart';
import 'package:troona/features/profiles/domain/profile_repository.dart';
import '../../helpers/fake_player.dart';

class EmptyStore implements ProfileDocumentStore {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String value) async {}
}

void main() {
  test(
    'navigation-owned input sessions never dispose or replace the shared player',
    () async {
      final audio = FakeAudioPort();
      final profiles = await ProfileRepository.open(EmptyStore());
      final adapter = PlaybackCommandsAdapter(audio);
      final dispatcher = PlayerActionDispatcher(
        playback: adapter,
        catalog: () => profiles.catalog,
      );
      final controls = ProfileControls(
        profiles: profiles,
        dispatcher: dispatcher,
      );
      final outcomes = <PlayerActionOutcome>[];
      final sub = dispatcher.outcomes.listen(outcomes.add);
      final recorder = controls.createInput(mode: InputMode.recording);
      recorder.dispose();
      final pad = controls.createInput();
      pad.dispose();
      expect(adapter.audio, same(audio));
      expect(audio.queueCtrl.isClosed, isFalse);
      // System/ordinary transports address the port directly, not the dispatcher.
      await audio.skipToNext();
      await audio.pause();
      expect(outcomes, isEmpty);
      await sub.cancel();
      await dispatcher.dispose();
      await profiles.dispose();
      await audio.close();
    },
  );
}
