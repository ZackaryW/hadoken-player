import 'dart:async';
import '../../profiles/domain/profile_catalog.dart';

enum ActionStatus { success, denied, noOp, failure }

final class CommandResult {
  final ActionStatus status;
  final String message;
  const CommandResult(this.status, this.message);
  bool get succeeded => status == ActionStatus.success;
}

final class PlayerActionRequest {
  final String requestId;
  final ActionBinding binding;
  final Duration recognizedAt;
  const PlayerActionRequest({
    required this.requestId,
    required this.binding,
    required this.recognizedAt,
  });
  ProfileId get profile => binding.profile;
  PlayerAction get action => binding.action;
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
  });

  Stream<PlayerActionOutcome> get outcomes => _outcomes.stream;

  Future<PlayerActionOutcome> dispatch(PlayerActionRequest request) {
    final previous = _requests[request.requestId];
    if (previous != null) return previous;
    // Snapshot validity at arrival, not after earlier commands finish. Saved
    // bindings are immutable, so a later edit cannot change this owner.
    final saved = catalog().bindingFor(request.profile, request.action);
    final valid =
        saved?.id == request.bindingId &&
        saved?.comboKey == request.binding.comboKey;
    final result = _tail.then((_) async {
      CommandResult result;
      try {
        if (!valid) {
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
          } else {
            result = await playback.execute(request.action);
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
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> dispose() async {
    await _tail;
    await _outcomes.close();
  }
}
