import 'package:flutter/foundation.dart' show immutable;

enum TxnDirection { debit, credit }

/// A transaction extracted from a bank/wallet message, awaiting the user's
/// confirmation before it becomes a real transaction.
@immutable
final class TxnCandidate {
  const TxnCandidate({
    required this.amountMinor,
    required this.direction,
    required this.source,
    required this.raw,
    this.merchant,
    this.when,
  });

  final int amountMinor;
  final TxnDirection direction;
  final String source; // sender id / app package
  final String raw;
  final String? merchant;
  final DateTime? when;
}

/// On-device parser for Pakistani bank SMS and wallet notifications. Generic
/// and keyword-based so it works across senders; per-source tuning can be added
/// once real samples are available. Returns null for anything that isn't a
/// money movement (OTPs, promos, balance-only alerts).
///
/// NOTE: this is a best-effort starting point — accuracy improves with real
/// sample messages from the owner's actual banks/wallets.
abstract final class SmsParser {
  static const _debit = [
    'debited',
    'debit ',
    'spent',
    'withdrawn',
    'withdrawal',
    'purchase',
    ' paid ',
    'payment of',
    'sent ',
    'transferred to',
  ];
  static const _credit = [
    'credited',
    'credit ',
    'received',
    'deposited',
    'refund',
    'added to',
  ];

  static final RegExp _amountRe = RegExp(
    r'(?:PKR|Rs\.?)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)',
    caseSensitive: false,
  );

  static TxnCandidate? parse({
    required String sender,
    required String body,
    DateTime? when,
  }) {
    final amount = _amountMinor(body);
    if (amount == null) return null;

    final lower = body.toLowerCase();
    final isDebit = _debit.any(lower.contains);
    final isCredit = _credit.any(lower.contains);
    if (isDebit == isCredit) return null; // neither, or ambiguous → skip

    return TxnCandidate(
      amountMinor: amount,
      direction: isDebit ? TxnDirection.debit : TxnDirection.credit,
      source: sender,
      raw: body,
      merchant: _merchant(body),
      when: when,
    );
  }

  static int? _amountMinor(String body) {
    final m = _amountRe.firstMatch(body);
    if (m == null) return null;
    final digits = m.group(1)!.replaceAll(',', '');
    final value = double.tryParse(digits);
    if (value == null || value <= 0) return null;
    return (value * 100).round();
  }

  /// Best-effort merchant/counterparty after "at" / "to" / "from".
  static String? _merchant(String body) {
    final m = RegExp(
      r'\b(?:at|to|from)\s+([A-Za-z0-9][A-Za-z0-9 &._\-]{1,30})',
      caseSensitive: false,
    ).firstMatch(body);
    final raw = m?.group(1)?.trim();
    if (raw == null || raw.isEmpty) return null;
    // Trim trailing filler words.
    return raw.replaceAll(
      RegExp(r'\s+(on|dated|ref).*$', caseSensitive: false),
      '',
    );
  }
}
