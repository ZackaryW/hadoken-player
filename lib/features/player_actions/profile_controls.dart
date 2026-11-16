import 'dart:async';
import 'package:uuid/uuid.dart';
import '../input_bindings/domain/combo_input.dart';
import '../profiles/domain/profile_repository.dart';
import '../profiles/domain/profile_catalog.dart';
import '../profiles/domain/effective_bindings.dart';
import 'domain/action_dispatcher.dart';

/// App-lifetime services; a page owns only its input session and subscriptions.
final class ProfileControls {
  final ProfileRepository profiles;
  final PlayerActionDispatcher dispatcher;
  final InputClock clock;
  final EffectiveBindings? effective;
  ProfileControls({
    required this.profiles,
    required this.dispatcher,
    InputClock? clock,
    this.effective,
  }) : clock = clock ?? StopwatchInputClock();

  ProfileCatalog get catalog => effective?.catalog ?? profiles.catalog;
  Stream<ProfileCatalog> get changes => effective?.changes ?? profiles.changes;

  ComboInput createInput({
    InputMode mode = InputMode.runtime,
    InputClock? inputClock,
    void Function()? onChanged,
    void Function(ComboMatch)? onPracticeMatch,
  }) => ComboInput(
    catalog: catalog,
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
          catalogRevision: match.catalogRevision,
          observations: match.observations,
          effort: dispatcher.effortFor(match.binding),
        ),
      ),
    ),
  );
}
