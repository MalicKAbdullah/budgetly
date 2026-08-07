import 'package:budgetly/src/core/models/captured_notice.dart';

/// Pure rules for the capture history: how drained native-queue text becomes
/// [CapturedNotice]s, and how a notice changes status. The encrypted app data
/// is the source of truth — the native queue is only a transient inbox.
abstract final class CaptureIngest {
  /// The encrypted vault is rewritten in full on every change, so history is
  /// capped; oldest notices fall off first.
  static const int maxHistory = 200;

  /// Appends every raw text not already in [existing] as a pending notice.
  /// Returns [existing] unchanged when nothing is new, so callers can skip a
  /// pointless write.
  static List<CapturedNotice> merge({
    required List<CapturedNotice> existing,
    required List<String> rawTexts,
    required DateTime now,
    required String Function() newId,
  }) {
    final seen = existing.map((n) => n.rawText).toSet();
    final fresh = <CapturedNotice>[];
    for (final raw in rawTexts) {
      final text = raw.trim();
      if (text.isEmpty || !seen.add(text)) continue;
      fresh.add(CapturedNotice(id: newId(), rawText: text, capturedAt: now));
    }
    if (fresh.isEmpty) return existing;
    return bound([...existing, ...fresh]);
  }

  /// Keeps only the newest [maxHistory] notices. The list is append-ordered
  /// (oldest first), so the excess comes off the front.
  static List<CapturedNotice> bound(List<CapturedNotice> notices) =>
      notices.length <= maxHistory
      ? notices
      : notices.sublist(notices.length - maxHistory);

  /// Moves one notice to [status]. [txnId] is recorded when the notice became
  /// a transaction. Any status can move to any other — a dismissed notice can
  /// be re-reviewed and added later.
  static List<CapturedNotice> withStatus(
    List<CapturedNotice> notices,
    String noticeId,
    CaptureStatus status, {
    String? txnId,
  }) => [
    for (final n in notices)
      if (n.id == noticeId) n.copyWith(status: status, txnId: txnId) else n,
  ];
}
