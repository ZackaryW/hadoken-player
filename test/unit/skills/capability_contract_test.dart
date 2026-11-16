import 'package:flutter_test/flutter_test.dart';
import 'package:troona/skills/skill.dart';

void main() {
  const second = Duration(seconds: 1);
  test(
    'six input types, immutable one-to-five macros and timing validation',
    () {
      expect(SkillStroke.values.length, 6);
      final source = [SkillStroke.forwardTap];
      final combo = SkillCombo(source);
      source.add(SkillStroke.backwardHold);
      expect(combo.strokes, [SkillStroke.forwardTap]);
      expect(() => combo.strokes.clear(), throwsUnsupportedError);
      expect(
        SkillCombo(List.filled(5, SkillStroke.pauseHold)).strokes.length,
        5,
      );
      expect(() => SkillCombo([]), throwsArgumentError);
      expect(() => SkillCombo(SkillStroke.values), throwsArgumentError);
      expect(
        () => SkillStrokeObservation(
          stroke: SkillStroke.pauseTap,
          downAt: second,
          upAt: Duration.zero,
          gapBefore: Duration.zero,
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'selectors resolve against added players without exposing mutable state',
    () {
      final added = ['p1', 'p2'];
      expect(PlayerSelector(PlayerScope.owner).resolve('p1', added), {'p1'});
      expect(PlayerSelector(PlayerScope.others).resolve('p1', added), {'p2'});
      expect(PlayerSelector(PlayerScope.all).resolve('p1', added), {
        'p1',
        'p2',
      });
      expect(
        PlayerSelector(PlayerScope.explicit, ['p2', 'p3']).resolve('p1', added),
        {'p2'},
      );
      expect(() => PlayerSelector(PlayerScope.explicit), throwsArgumentError);
      expect(
        () => PlayerSelector(PlayerScope.all, ['p1']),
        throwsArgumentError,
      );
    },
  );

  test(
    'future queue plans have bounded lives and preserve occurrence references',
    () {
      final operations = <QueueOperation>[RemoveOccurrence('duplicate-2')];
      final plan = EditLoopQueue(
        'plan',
        loops: FutureLoopRange(2, 4),
        expectedRevision: 3,
        operations: operations,
        lifetime: second,
      );
      operations.clear();
      expect(
        (plan.operations.single as RemoveOccurrence).occurrenceId,
        'duplicate-2',
      );
      expect(
        () => EditLoopQueue(
          'bad',
          loops: FutureLoop(2),
          expectedRevision: 0,
          operations: [RemoveOccurrence('one')],
        ),
        throwsArgumentError,
      );
      expect(() => FutureLoopRange(4, 2), throwsArgumentError);
      expect(
        () => EditLoopQueue(
          'bad',
          loops: const CurrentLoop(),
          expectedRevision: -1,
          operations: [RemoveOccurrence('one')],
        ),
        throwsArgumentError,
      );
      expect(
        () => EditLoopQueue(
          'bad',
          loops: const CurrentLoop(),
          expectedRevision: 0,
          operations: [],
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'audio validates shape, finite gains, positive transforms and lifetime',
    () {
      final a = SongReference('a');
      final b = SongReference('b');
      final mix = StartAudioMix(
        'mix',
        lifetime: second,
        layers: [
          MixLayer(kind: MixLayerKind.song, song: a, speed: 1.2, pitch: 0.8),
          MixLayer(kind: MixLayerKind.song, song: b, gain: 0.4),
        ],
      );
      expect(mix.capability, SkillCapability.audioMix);
      expect(() => MixLayer(kind: MixLayerKind.song), throwsArgumentError);
      expect(
        () => MixLayer(kind: MixLayerKind.noise, gain: double.nan),
        throwsArgumentError,
      );
      expect(
        () => MixLayer(kind: MixLayerKind.noise, speed: 0),
        throwsArgumentError,
      );
      expect(
        () => StartAudioMix('mix', layers: mix.layers, lifetime: Duration.zero),
        throwsArgumentError,
      );
      expect(
        () =>
            StartAudioMix('mix', layers: [mix.layers.first], lifetime: second),
        throwsArgumentError,
      );
    },
  );

  test('restrictions, overlays and listeners are typed, bounded requests', () {
    final combo = SkillCombo([SkillStroke.forwardHold]);
    final target = const PlaybackSkillTarget(SkillAction.nextTrack);
    final restrict = RestrictActions(
      'block',
      players: PlayerSelector(PlayerScope.others),
      actions: [target, ActivationSkillTarget('manual')],
      lifetime: second,
    );
    final overlay = OverrideCombos(
      'override',
      replacements: [ComboReplacement('p2', SkillAction.nextTrack, combo)],
      lifetime: second,
    );
    final listen = ArmComboListener(
      'listen',
      listenerKey: 'watch',
      combo: combo,
      players: PlayerSelector(PlayerScope.all),
      lifetime: second,
      once: true,
    );
    expect(
      [restrict.capability, overlay.capability, listen.capability],
      [
        SkillCapability.restriction,
        SkillCapability.comboOverride,
        SkillCapability.listener,
      ],
    );
    expect(
      () => RestrictActions(
        'bad',
        players: PlayerSelector(PlayerScope.all),
        actions: [],
        lifetime: second,
      ),
      throwsArgumentError,
    );
    expect(
      () => OverrideCombos(
        'bad',
        replacements: [
          overlay.replacements.single,
          overlay.replacements.single,
        ],
        lifetime: second,
      ),
      throwsArgumentError,
    );
    expect(
      () => ArmComboListener(
        'bad',
        listenerKey: '',
        combo: combo,
        players: PlayerSelector(PlayerScope.all),
        lifetime: second,
      ),
      throwsArgumentError,
    );
  });

  test('immutable context and result truth prevent invented applied state', () {
    final players = ['p1'];
    final context = SkillContext(
      sessionId: 'session',
      owner: 'p1',
      elapsed: Duration.zero,
      players: players,
      support: [SkillCapability.audioMix],
    );
    players.add('p2');
    expect(context.players, {'p1'});
    expect(() => context.support.clear(), throwsUnsupportedError);
    final origin = SkillOrigin(
      owner: 'p1',
      skillKey: 'test',
      invocationId: 'call',
      sessionId: 'session',
    );
    final handle = EffectHandle(id: 'mix', origin: origin, deadline: second);
    expect(
      () => CapabilityResult(
        effectId: 'mix',
        status: CapabilityStatus.failed,
        handle: handle,
      ),
      throwsArgumentError,
    );
    expect(
      CapabilityResult(
        effectId: 'mix',
        status: CapabilityStatus.applied,
        handle: handle,
      ).handle,
      same(handle),
    );
    expect(
      () => SkillOrigin(
        owner: '',
        skillKey: 'test',
        invocationId: 'call',
        sessionId: 's',
      ),
      throwsArgumentError,
    );
  });

  test('reaction bounds prohibit duplicate effects and unbounded batches', () {
    final effect = RevokeSkillEffect('one', 'handle');
    expect(
      () => SkillReaction(requests: [effect, effect]),
      throwsArgumentError,
    );
    expect(
      () => SkillReaction(
        requests: List.generate(
          17,
          (i) => RevokeSkillEffect('effect-$i', 'handle-$i'),
        ),
      ),
      throwsArgumentError,
    );
    expect(() => SkillManualActivation('manual', []), throwsArgumentError);
  });
}
