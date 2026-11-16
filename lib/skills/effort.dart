/// Ordered levels, not a consumable resource. The endpoints represent infinity
/// sentinels and are compared directly, never added to other effort values.
final class Effort implements Comparable<Effort> {
  static const minimum = Effort._(-1);
  static const normal = Effort._(50);
  static const maximum = Effort._(100);
  final int value;
  const Effort._(this.value);
  factory Effort(int value) {
    if (value < -1 || value > 100) {
      throw RangeError.range(value, -1, 100, 'effort');
    }
    return Effort._(value);
  }
  bool overcomes(Effort block) => value > block.value;
  @override
  int compareTo(Effort other) => value.compareTo(other.value);
  @override
  bool operator ==(Object other) => other is Effort && value == other.value;
  @override
  int get hashCode => value.hashCode;
  @override
  String toString() => '$value';
}

final class SkillActionBlock {
  final String reason;
  final Effort effort;
  const SkillActionBlock(this.reason, {this.effort = Effort.normal});
}
