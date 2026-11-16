import 'dart:async';
import 'package:uuid/uuid.dart';
import '../input_bindings/domain/combo_input.dart';
import '../profiles/domain/profile_repository.dart';
import 'domain/action_dispatcher.dart';

/// App-lifetime services; a page owns only its input session and subscriptions.
final class ProfileControls {
  final ProfileRepository profiles;
  final PlayerActionDispatcher dispatcher;
  final InputClock clock;
  ProfileControls({
    required this.profiles,
    required this.dispatcher,
    InputClock? clock,
  }) : clock = clock ?? StopwatchInputClock();

  ComboInput createInput({
    InputMode mode = InputMode.runtime,
    InputClock? inputClock,
    void Function()? onChanged,
    void Function(ComboMatch)? onPracticeMatch,
  }) => ComboInput(
    catalog: profiles.catalog,
    clock: inputClock ?? clock,
    mode: mode,
    onChanged: onChanged,
    onPracticeMatch: onPracticeMatch,
    onRuntimeMatch: (match) => unawaited(
      dispatcher.dispatch(
        PlayerActionRequest(
          requestId: const Uuid().v4(),
          binding: match.binding,
          recognizedAt: match.recognizedAt,
        ),
      ),
    ),
  );
}
