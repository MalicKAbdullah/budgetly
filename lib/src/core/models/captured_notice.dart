import 'package:flutter/foundation.dart' show immutable;

/// Where a captured notification is in its review lifecycle.
enum CaptureStatus {
  pending('Needs review'),
  added('Added'),
  dismissed('Dismissed');

  const CaptureStatus(this.label);
  final String label;

  static CaptureStatus parse(String? raw) => CaptureStatus.values.firstWhere(
    (s) => s.name == raw,
    orElse: () => CaptureStatus.pending,
  );
}

/// A bank/wallet notification Budgetly captured on-device, kept forever (up to
/// the history bound) so the user always has a record of what was seen and
/// what became a transaction. The raw text is the identity used for dedupe —
/// the same alert is never queued twice.
@immutable
final class CapturedNotice {
  const CapturedNotice({
    required this.id,
    required this.rawText,
    required this.capturedAt,
    this.status = CaptureStatus.pending,
    this.txnId,
  });

  factory CapturedNotice.fromJson(Map<String, dynamic> json) => CapturedNotice(
    id: json['id'] as String,
    rawText: json['rawText'] as String,
    capturedAt: DateTime.parse(json['capturedAt'] as String),
    status: CaptureStatus.parse(json['status'] as String?),
    txnId: json['txnId'] as String?,
  );

  final String id;
  final String rawText;
  final DateTime capturedAt;
  final CaptureStatus status;

  /// The transaction this notice became — set only when [status] is
  /// [CaptureStatus.added].
  final String? txnId;

  bool get isPending => status == CaptureStatus.pending;

  CapturedNotice copyWith({CaptureStatus? status, String? txnId}) =>
      CapturedNotice(
        id: id,
        rawText: rawText,
        capturedAt: capturedAt,
        status: status ?? this.status,
        txnId: txnId ?? this.txnId,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'rawText': rawText,
    'capturedAt': capturedAt.toIso8601String(),
    'status': status.name,
    if (txnId != null) 'txnId': txnId,
  };
}
