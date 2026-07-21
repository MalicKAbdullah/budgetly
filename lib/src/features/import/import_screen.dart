import 'package:core_theme/core_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tally/src/core/models/account.dart';
import 'package:tally/src/core/models/category.dart';
import 'package:tally/src/core/models/txn.dart';
import 'package:tally/src/core/money.dart';
import 'package:tally/src/core/providers.dart';
import 'package:tally/src/features/import/sms_parser.dart';
import 'package:uuid/uuid.dart';

/// Paste a bank SMS / wallet notification → parse it → confirm → save.
/// This is the verifiable core of auto-capture; a live SMS/notification
/// listener (Android) can feed the same parser + confirm flow later.
class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key});

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  final _text = TextEditingController();
  TxnCandidate? _candidate;
  bool _parsed = false;
  String? _accountId;
  String? _categoryId;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _parse() {
    final candidate = SmsParser.parse(
      sender: 'pasted',
      body: _text.text.trim(),
    );
    setState(() {
      _candidate = candidate;
      _parsed = true;
    });
  }

  Future<void> _save() async {
    final c = _candidate;
    if (c == null || _accountId == null) return;
    final isExpense = c.direction == TxnDirection.debit;
    final txn = Txn(
      id: const Uuid().v4(),
      type: isExpense ? TxnType.expense : TxnType.income,
      amountMinor: c.amountMinor,
      date: c.when ?? DateTime.now(),
      accountId: _accountId!,
      categoryId: isExpense ? _categoryId : null,
      note: c.merchant ?? '',
      createdAt: DateTime.now(),
    );
    await ref.read(appDataProvider.notifier).saveTxn(txn);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Transaction added.')));
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(appDataProvider).valueOrNull;
    final accounts = data?.accounts ?? const <Account>[];
    final categories = data?.categories ?? const <Category>[];
    final code = data?.currencyCode ?? 'PKR';
    _accountId ??= accounts.isNotEmpty ? accounts.first.id : null;
    final c = _candidate;

    return Scaffold(
      appBar: AppBar(title: const Text('Import from message')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          const Text(
            'Paste a bank SMS or wallet notification. Tally reads it on-device '
            'and pulls out the transaction for you to confirm.',
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _text,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'e.g. Your account was debited PKR 2,400 at FOODPANDA',
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          FilledButton.tonal(onPressed: _parse, child: const Text('Read it')),
          const SizedBox(height: AppSpacing.md),
          if (_parsed && c == null)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.md),
                child: Text(
                  "Couldn't find a transaction in that message. It may be an "
                  'OTP or promo — or the format needs adding.',
                ),
              ),
            ),
          if (c != null) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${c.direction == TxnDirection.debit ? 'Expense' : 'Income'}'
                      ' · ${Money.format(c.amountMinor, code: code)}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (c.merchant != null) Text(c.merchant!),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String>(
              initialValue: _accountId,
              decoration: const InputDecoration(labelText: 'Account'),
              items: [
                for (final a in accounts)
                  DropdownMenuItem(value: a.id, child: Text(a.name)),
              ],
              onChanged: (v) => setState(() => _accountId = v),
            ),
            if (c.direction == TxnDirection.debit) ...[
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<String?>(
                initialValue: _categoryId,
                decoration: const InputDecoration(labelText: 'Category'),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('Uncategorized'),
                  ),
                  for (final cat in categories)
                    DropdownMenuItem(value: cat.id, child: Text(cat.name)),
                ],
                onChanged: (v) => setState(() => _categoryId = v),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: accounts.isEmpty ? null : _save,
              child: const Text('Add transaction'),
            ),
          ],
        ],
      ),
    );
  }
}
