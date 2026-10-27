// Benchmarks print their numbers; CI only checks loose sanity.
// ignore_for_file: avoid_print

/// Median wall time of [runs] calls after [warmup] unmeasured ones, in ms.
Future<double> medianMs(
  Future<void> Function() body, {
  int warmup = 3,
  int runs = 9,
}) async {
  for (var i = 0; i < warmup; i++) {
    await body();
  }
  final times = <double>[];
  for (var i = 0; i < runs; i++) {
    final watch = Stopwatch()..start();
    await body();
    times.add(watch.elapsedMicroseconds / 1000);
  }
  times.sort();
  return times[times.length ~/ 2];
}

/// The longest stretch, in ms, during which the calling isolate's event loop
/// could not run while [body] was in flight — how long a frame or a platform
/// reply would have waited. Median over [runs] after one warm-up.
Future<double> longestStallMs(
  Future<void> Function() body, {
  int runs = 7,
}) async {
  await _stallOnce(body);
  final stalls = [for (var i = 0; i < runs; i++) await _stallOnce(body)];
  stalls.sort();
  return stalls[stalls.length ~/ 2];
}

Future<double> _stallOnce(Future<void> Function() body) async {
  var longest = 0;
  var last = Stopwatch()..start();
  var running = true;
  Future<void> ticker() async {
    while (running) {
      await Future<void>.delayed(Duration.zero);
      final gap = last.elapsedMicroseconds;
      if (gap > longest) longest = gap;
      last = Stopwatch()..start();
    }
  }

  final ticking = ticker();
  await body();
  running = false;
  await ticking;
  return longest / 1000;
}

void report(String title, Map<String, double> rows) {
  print('== $title');
  for (final MapEntry(:key, :value) in rows.entries) {
    print('  ${key.padRight(52)} ${value.toStringAsFixed(2).padLeft(9)} ms');
  }
}
