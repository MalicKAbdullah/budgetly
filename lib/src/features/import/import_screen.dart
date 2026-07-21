import 'package:core_theme/core_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tally/src/core/models/account.dart';
import 'package:tally/src/core/models/category.dart';
import 'package:tally/src/core/models/txn.dart';
import 'package:tally/src/core/money.dart';
import 'package:tally/src/core/providers.dart';
import 'package:tally/src/features/import/sms_parser.dart';
import 'package:uuid/uuid.dart';

/// Auto-capture inbox + manual import. Bank/wallet notifications captured
/// on-device (Android) are parsed here for one-tap confirmation; you can also
/// paste a message manually. The parser is the single source of truth — the
/// native listener only queues raw text, so this flow works either way.
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
  String? _currentRaw;
  List<String> _pending = const [];
  bool _captureSupported = false;
  bool _captureEnabled = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final cap = ref.read(captureServiceProvider);
    final supported = cap.supported;
    final enabled = supported && await cap.isEnabled();
    final pending = enabled ? await cap.getPending() : const <String>[];
    if (mounted) {
      setState(() {
        _captureSupported = supported;
        _captureEnabled = enabled;
        _pending = pending;
      });
    }
  }

  void _review(String raw) {
    _text.text = raw;
    _currentRaw = raw;
    _parse();
  }

  void _parse() {
    setState(() {
      _candidate = SmsParser.parse(
        sender: _currentRaw != null ? 'notification' : 'pasted',
        body: _text.text.trim(),
      );
      _parsed = true;
    });
  }

  Future<void> _dismiss(String raw) async {
    await ref.read(captureServiceProvider).remove(raw);
    await _refresh();
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
    final raw = _currentRaw;
    if (raw != null) await ref.read(captureServiceProvider).remove(raw);
    _text.clear();
    setState(() {
      _candidate = null;
      _parsed = false;
      _currentRaw = null;
    });
    await _refresh();
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Transaction added.')));
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
      appBar: AppBar(
        title: const Text('Auto-capture & import'),
        actions: [
          if (_captureEnabled)
            IconButton(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          if (_captureSupported) _captureStatusCard(),
          if (_pending.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              'Captured (${_pending.length})',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final raw in _pending) _capturedCard(raw, code),
          ],
          const SizedBox(height: AppSpacing.md),
          Text('Add manually', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'Paste a bank SMS or wallet notification. Tally reads it on-device '
            'and pulls out the transaction for you to confirm.',
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _text,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'e.g. PKR 2,400.00 sent to FOODPANDA …',
            ),
            onChanged: (_) => _currentRaw = null,
          ),
          const SizedBox(height: AppSpacing.sm),
          FilledButton.tonal(onPressed: _parse, child: const Text('Read it')),
          if (_parsed && c == null)
            const Padding(
              padding: EdgeInsets.only(top: AppSpacing.md),
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.md),
                  child: Text(
                    "Couldn't find a transaction in that message. It may be an "
                    'OTP or promo — or the format needs adding.',
                  ),
                ),
              ),
            ),
          if (c != null) ...[
            const SizedBox(height: AppSpacing.md),
            _confirmForm(c, accounts, categories, code),
          ],
        ],
      ),
    );
  }

  Widget _captureStatusCard() {
    if (_captureEnabled) {
      return Card(
        color: Theme.of(context).colorScheme.secondaryContainer,
        child: const ListTile(
          leading: Icon(Icons.notifications_active_outlined),
          title: Text('Auto-capture is on'),
          subtitle: Text('New bank/wallet alerts show up here to confirm.'),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Turn on auto-capture',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'Let Tally read bank/wallet transaction alerts on-device (e.g. '
              'Meezan SMS) so they appear here to confirm — nothing is '
              'uploaded. Grant "notification access" to Tally.',
            ),
            const SizedBox(height: AppSpacing.sm),
            FilledButton.tonalIcon(
              onPressed: () async {
                await ref.read(captureServiceProvider).openSettings();
              },
              icon: const Icon(Icons.settings),
              label: const Text('Grant notification access'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _capturedCard(String raw, String code) {
    final cand = SmsParser.parse(sender: 'notification', body: raw);
    final title = cand == null
        ? 'Unrecognized message'
        : '${cand.direction == TxnDirection.debit ? 'Expense' : 'Income'} · '
              '${Money.format(cand.amountMinor, code: code)}'
              '${cand.merchant != null ? ' · ${cand.merchant}' : ''}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              raw,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => _dismiss(raw),
                  child: const Text('Dismiss'),
                ),
                if (cand != null)
                  FilledButton(
                    onPressed: () => _review(raw),
                    child: const Text('Review'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _confirmForm(
    TxnCandidate c,
    List<Account> accounts,
    List<Category> categories,
    String code,
  ) {
    final isExpense = c.direction == TxnDirection.debit;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${isExpense ? 'Expense' : 'Income'} · '
                  '${Money.format(c.amountMinor, code: code)}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (c.merchant != null) Text(c.merchant!),
                if (c.when != null)
                  Text(
                    DateFormat.yMMMd().add_jm().format(c.when!),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: _accountId,
          decoration: const InputDecoration(labelText: 'Account'),
          items: [
            for (final a in accounts)
              DropdownMenuItem(value: a.id, child: Text(a.name)),
          ],
          onChanged: (v) => setState(() => _accountId = v),
        ),
        if (isExpense) ...[
          const SizedBox(height: AppSpacing.md),
          DropdownButtonFormField<String?>(
            isExpanded: true,
            initialValue: _categoryId,
            decoration: const InputDecoration(labelText: 'Category'),
            items: [
              const DropdownMenuItem(value: null, child: Text('Uncategorized')),
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
    );
  }
}
