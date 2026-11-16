import 'dart:async';
import '../../profiles/domain/profile_catalog.dart';
import 'package:troona/skills/skill.dart';
import '../../input_bindings/domain/combo_input.dart';

enum ActionStatus { success, denied, noOp, failure }

final class CommandResult {
  final ActionStatus status;
  final String message;
  final List<CapabilityResult> effects;
  const CommandResult(this.status, this.message, {this.effects = const []});
  bool get succeeded => status == ActionStatus.success;
}

final class PlayerActionRequest {
  final String requestId;
  final ExecutableBinding binding;
  final Duration recognizedAt;
  final Effort effort;
  final int? catalogRevision;
  final List<StrokeObservation> observations;
  PlayerActionRequest({
    required this.requestId,
    required this.binding,
    required this.recognizedAt,
    this.effort = Effort.normal,
    this.catalogRevision,
    Iterable<StrokeObservation> observations = const [],
  }) : observations = List.unmodifiable(observations);
  ProfileId get profile => binding.profile;
  PlayerAction? get action => switch (binding) {
    ActionBinding(:final action) => action,
    _ => null,
  };
  String get bindingId => binding.id;
}

final class PlayerActionOutcome {
  final PlayerActionRequest request;
  final CommandResult result;
  const PlayerActionOutcome(this.request, this.result);
}

abstract interface class PlaybackCommands {
  Future<CommandResult> execute(PlayerAction action);
}

abstract interface class PlayerAbilityPolicy {
  /// Null permits the action; otherwise the text explains why it is denied.
  Future<String?> denialFor(PlayerActionRequest request);

  /// Called only after an observed successful playback effect, before the next
  /// request is evaluated. Stage 2 owns its hardcoded skill state here.
  Future<void> recordSuccess(PlayerActionRequest request, CommandResult result);
}

abstract interface class OrderedPlayerAbilityPolicy
    implements PlayerAbilityPolicy {
  void bindOrder(Future<T> Function<T>(Future<T> Function()) runOrdered);
}

abstract interface class ExecutablePlayerAbilityPolicy
    implements OrderedPlayerAbilityPolicy {
  Effort effortFor(ExecutableBinding binding);
  Future<CommandResult> activate(PlayerActionRequest request);
}

final class AllowAllAbilities implements PlayerAbilityPolicy {
  const AllowAllAbilities();
  @override
  Future<String?> denialFor(PlayerActionRequest request) async => null;
  @override
  Future<void> recordSuccess(
    PlayerActionRequest request,
    CommandResult result,
  ) async {}
}

final class PlayerActionDispatcher {
  final PlaybackCommands playback;
  final PlayerAbilityPolicy abilities;
  final ProfileCatalog Function() catalog;
  final _outcomes = StreamController<PlayerActionOutcome>.broadcast(sync: true);
  final _requests = <String, Future<PlayerActionOutcome>>{};
  Future<void> _tail = Future.value();
  bool _policyFailed = false;

  PlayerActionDispatcher({
    required this.playback,
    required this.catalog,
    this.abilities = const AllowAllAbilities(),
  }) {
    final policy = abilities;
    if (policy is OrderedPlayerAbilityPolicy) policy.bindOrder(runOrdered);
  }

  Stream<PlayerActionOutcome> get outcomes => _outcomes.stream;

  Effort effortFor(ExecutableBinding binding) {
    final policy = abilities;
    return policy is ExecutablePlayerAbilityPolicy
        ? policy.effortFor(binding)
        : Effort.normal;
  }

  Future<PlayerActionOutcome> dispatch(PlayerActionRequest request) {
    final previous = _requests[request.requestId];
    if (previous != null) return previous;
    final arrival = catalog();
    final revision = request.catalogRevision ?? arrival.revision;
    bool validNow() {
      final current = catalog();
      final saved = current.executableById(request.bindingId);
      return current.revision == revision &&
          saved?.comboKey == request.binding.comboKey;
    }

    final validAtArrival = validNow();
    final result = runOrdered(() async {
      CommandResult result;
      try {
        if (!validAtArrival || !validNow()) {
          result = const CommandResult(
            ActionStatus.denied,
            'This binding is no longer saved.',
          );
        } else if (_policyFailed) {
          result = const CommandResult(
            ActionStatus.failure,
            'Skill state could not be updated. Restart the player before more combo actions.',
          );
        } else {
          final denial = await abilities.denialFor(request);
          if (denial != null) {
            result = CommandResult(ActionStatus.denied, denial);
          } else if (!validNow()) {
            result = const CommandResult(
              ActionStatus.denied,
              'This combination changed before execution.',
            );
          } else if (request.binding is SkillMacroBinding) {
            final policy = abilities;
            result = policy is ExecutablePlayerAbilityPolicy
                ? await policy.activate(request)
                : const CommandResult(
                    ActionStatus.denied,
                    'Skill activation is unavailable.',
                  );
          } else {
            result = await playback.execute(request.action!);
            if (result.succeeded) {
              try {
                await abilities.recordSuccess(request, result);
              } catch (_) {
                // Playback already happened: preserve its success and stop
                // later requests rather than allowing inconsistent skill state.
                _policyFailed = true;
                result = CommandResult(
                  ActionStatus.success,
                  '${result.message} Skill update failed; restart before more combo actions.',
                );
              }
            }
          }
        }
      } catch (_) {
        result = const CommandResult(
          ActionStatus.failure,
          'The playback action failed.',
        );
      }
      final outcome = PlayerActionOutcome(request, result);
      _outcomes.add(outcome);
      return outcome;
    });
    _requests[request.requestId] =
        result; // Includes denied/no-op/failure results.
    return result;
  }

  /// Skill assignment mutations use the same queue as check/playback/success.
  /// Operations must not recursively enqueue and await another operation.
  Future<T> runOrdered<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> dispose() async {
    await _tail;
    await _outcomes.close();
  }
}
