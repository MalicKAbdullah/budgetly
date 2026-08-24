import 'package:budgetly/src/core/models/txn.dart';
import 'package:budgetly/src/features/capture/sms_parser.dart';

/// What the review sheet is about to record. A captured alert is not always
/// spending: an ATM withdrawal takes money out of the bank and puts it in the
/// owner's pocket, which is a transfer, not an expense.
enum CaptureMode {
  expense('Expense'),
  income('Income'),
  transfer('Transfer');

  const CaptureMode(this.label);
  final String label;

  TxnType get txnType => switch (this) {
    CaptureMode.expense => TxnType.expense,
    CaptureMode.income => TxnType.income,
    CaptureMode.transfer => TxnType.transfer,
  };
}

/// Pure rules for the mode the review sheet opens on. Only ever a suggestion —
/// the three-way control is always free to override it.
abstract final class CaptureModeHint {
  /// Cash-withdrawal wording. Matched case-insensitively on whole words, so
  /// "Withdrawn", "WITHDRAWAL" and "ATM" all count while an ordinary purchase
  /// ("debited at CHECKOUT") does not.
  static final RegExp _withdrawal = RegExp(
    r'\b(withdraw|withdrew|withdrawn|withdrawal|withdrawals|atm|cash\s+out)\b',
    caseSensitive: false,
  );

  /// True when the alert reads like money the owner took out as cash.
  static bool suggestsTransfer(String? rawText) =>
      rawText != null && _withdrawal.hasMatch(rawText);

  /// The mode to open on: a withdrawal is a transfer, a credit is income,
  /// anything else (including an alert nothing could be read from) is spending.
  static CaptureMode suggest({required String rawText, TxnCandidate? parsed}) {
    if (suggestsTransfer(rawText)) return CaptureMode.transfer;
    return parsed?.direction == TxnDirection.credit
        ? CaptureMode.income
        : CaptureMode.expense;
  }
}
