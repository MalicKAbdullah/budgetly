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

/// On-device parser for bank SMS / wallet notifications. Tuned to **Meezan Bank
/// (sender 8079)** — the three message shapes are:
///   • "PKR X sent to NAME … from your A/C …"        → debit
///   • "PKR X received from NAME … to your AC# …"     → credit
///   • "PKR X has been debited at HH:MM on DD-Mon…"   → debit (card/ATM)
/// Generic keyword fallback covers other senders. Returns null for anything
/// that isn't a money movement (OTPs, promos, balance alerts).
abstract final class SmsParser {
  static final RegExp _amountRe = RegExp(
    r'(?:PKR|Rs\.?)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)',
    caseSensitive: false,
  );

  static final RegExp _sentTo = RegExp(
    r'sent to\s+(.+?)(?=\s*\(|\s+PK[0-9A-Za-z]|\s+as\s|\s+from your|\s+AC#|$)',
    caseSensitive: false,
  );
  static final RegExp _receivedFrom = RegExp(
    r'received from\s+(.+?)(?=\s*\(|\s+AC#|\s+as\s|\s+to your|$)',
    caseSensitive: false,
  );
  static final RegExp _dateRe = RegExp(
    r'on\s+(\d{1,2})-([A-Za-z]{3})-(\d{4})\s+at\s+(\d{1,2}):(\d{2})',
    caseSensitive: false,
  );

  static const Map<String, int> _months = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };

  static const List<String> _creditWords = ['received', 'credited'];
  static const List<String> _debitWords = [
    'sent to',
    'debited',
    'withdrawn',
    'withdrawal',
    'spent',
    'purchase',
    ' paid ',
  ];

  static TxnCandidate? parse({
    required String sender,
    required String body,
    DateTime? when,
  }) {
    final amount = _amountMinor(body);
    if (amount == null) return null;

    final lower = body.toLowerCase();
    final TxnDirection direction;
    String? merchant;
    if (_creditWords.any(lower.contains)) {
      direction = TxnDirection.credit;
      merchant = _capture(_receivedFrom, body);
    } else if (_debitWords.any(lower.contains)) {
      direction = TxnDirection.debit;
      merchant = _capture(_sentTo, body); // null for plain "debited"
    } else {
      return null;
    }

    return TxnCandidate(
      amountMinor: amount,
      direction: direction,
      source: sender,
      raw: body,
      merchant: merchant,
      when: _date(body) ?? when,
    );
  }

  static int? _amountMinor(String body) {
    final m = _amountRe.firstMatch(body);
    if (m == null) return null;
    final value = double.tryParse(m.group(1)!.replaceAll(',', ''));
    if (value == null || value <= 0) return null;
    return (value * 100).round();
  }

  static String? _capture(RegExp re, String body) {
    final raw = re.firstMatch(body)?.group(1)?.trim();
    if (raw == null || raw.isEmpty) return null;
    return raw.replaceAll(RegExp(r'\s+'), ' ');
  }

  static DateTime? _date(String body) {
    final m = _dateRe.firstMatch(body);
    if (m == null) return null;
    final month = _months[m.group(2)!.toLowerCase()];
    if (month == null) return null;
    return DateTime(
      int.parse(m.group(3)!),
      month,
      int.parse(m.group(1)!),
      int.parse(m.group(4)!),
      int.parse(m.group(5)!),
    );
  }
}
