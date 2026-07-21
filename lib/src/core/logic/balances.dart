import 'package:tally/src/core/data/app_data.dart';
import 'package:tally/src/core/models/txn.dart';

/// Derives account balances from the opening balance + every transaction that
/// touches the account. Transfers move money between the owner's own accounts,
/// so they never change net worth.
abstract final class Balances {
  static int accountBalanceMinor(AppData data, String accountId) {
    final account = data.accountById(accountId);
    var balance = account?.openingBalanceMinor ?? 0;
    for (final t in data.txns) {
      switch (t.type) {
        case TxnType.expense:
          if (t.accountId == accountId) balance -= t.amountMinor;
        case TxnType.income:
          if (t.accountId == accountId) balance += t.amountMinor;
        case TxnType.transfer:
          if (t.accountId == accountId) balance -= t.amountMinor;
          if (t.toAccountId == accountId) balance += t.amountMinor;
      }
    }
    return balance;
  }

  /// Sum of balances across all non-archived accounts.
  static int netWorthMinor(AppData data) => data.activeAccounts.fold(
    0,
    (sum, a) => sum + accountBalanceMinor(data, a.id),
  );
}
