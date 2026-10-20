/// Dividing an amount of minor units into parts that always add back up to it.
///
/// Every method returns whole minor units and the parts sum to the total
/// exactly — the rounding remainder is handed out one minor unit at a time,
/// never dropped and never invented.
abstract final class SplitAllocation {
  /// One whole percent, in the basis points [byBasisPoints] works in.
  static const int percent = 100;

  /// All of an amount, in basis points.
  static const int whole = 100 * percent;

  /// [totalMinor] in [parts] equal shares. The remainder goes to the earliest
  /// parts, one minor unit each, so the order of the parts decides who absorbs
  /// the rounding.
  static List<int> equal(int totalMinor, int parts) {
    assert(parts > 0, 'an equal split needs at least one part');
    assert(totalMinor >= 0, 'only non-negative amounts are divided');
    final base = totalMinor ~/ parts;
    final extra = totalMinor - base * parts;
    return [for (var i = 0; i < parts; i++) base + (i < extra ? 1 : 0)];
  }

  /// [totalMinor] in proportion to [basisPoints], which must add up to
  /// [whole]. Largest-remainder rounding: each part gets the floor of its exact
  /// share, then the leftover minor units go to the parts whose exact share
  /// lost the most to the floor, earliest first on a tie.
  static List<int> byBasisPoints(int totalMinor, List<int> basisPoints) {
    assert(
      basisPoints.fold(0, (s, b) => s + b) == whole,
      'the weights must cover the whole amount',
    );
    assert(basisPoints.every((b) => b >= 0), 'weights are never negative');
    final floors = <int>[];
    final lost = <int>[];
    for (final b in basisPoints) {
      final exact = totalMinor * b;
      floors.add(exact ~/ whole);
      lost.add(exact % whole);
    }
    var leftover = totalMinor - floors.fold(0, (s, f) => s + f);
    final order = [for (var i = 0; i < basisPoints.length; i++) i]
      ..sort((a, b) {
        final byLost = lost[b].compareTo(lost[a]);
        return byLost != 0 ? byLost : a.compareTo(b);
      });
    for (final i in order) {
      if (leftover == 0) break;
      floors[i]++;
      leftover--;
    }
    return floors;
  }
}
