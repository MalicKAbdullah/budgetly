import 'package:core_theme/core_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:budgetly/src/core/models/account.dart';
import 'package:budgetly/src/core/models/captured_notice.dart';
import 'package:budgetly/src/core/models/category.dart';
import 'package:budgetly/src/core/models/txn.dart';
import 'package:budgetly/src/core/money.dart';
import 'package:budgetly/src/core/providers.dart';
import 'package:budgetly/src/features/capture/sms_parser.dart';
import 'package:uuid/uuid.dart';

/// Opens the review sheet for one captured notification. A modal sheet, never
/// an inline form — the whole point is that the confirm step is unmissable.
Future<void> showCaptureReviewSheet(
  BuildContext context,
  CapturedNotice notice,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => _ReviewSheet(notice: notice),
);

class _ReviewSheet extends ConsumerStatefulWidget {
  const _ReviewSheet({required this.notice});
  final CapturedNotice notice;

  @override
  ConsumerState<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends ConsumerState<_ReviewSheet> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  TxnCandidate? _candidate;
  bool _isExpense = true;
  late DateTime _date;
  String? _accountId;
  String? _categoryId;

  @override
  void initState() {
    super.initState();
    final parsed = SmsParser.parse(
      sender: 'notification',
      body: widget.notice.rawText,
    );
    _candidate = parsed;
    _isExpense = parsed?.direction != TxnDirection.credit;
    _date = parsed?.when ?? widget.notice.capturedAt;
    // Unparseable messages open with a blank amount for manual entry, so there
    // is always a path to add rather than a dead end.
    if (parsed != null) _amount.text = Money.toInput(parsed.amountMinor);
    if (parsed?.merchant != null) _note.text = parsed!.merchant!;
    _amount.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2015),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(
        () => _date = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _date.hour,
          _date.minute,
        ),
      );
    }
  }

  Future<void> _add() async {
    final minor = Money.parse(_amount.text);
    if (minor == null || minor <= 0 || _accountId == null) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final txn = Txn(
      id: const Uuid().v4(),
      type: _isExpense ? TxnType.expense : TxnType.income,
      amountMinor: minor,
      date: _date,
      accountId: _accountId!,
      categoryId: _isExpense ? _categoryId : null,
      note: _note.text.trim(),
      createdAt: ref.read(clockProvider)(),
    );
    await ref
        .read(appDataProvider.notifier)
        .addTxnForNotice(txn, widget.notice.id);
    navigator.pop();
    messenger.showSnackBar(const SnackBar(content: Text('Transaction added.')));
  }

  Future<void> _dismiss() async {
    final navigator = Navigator.of(context);
    await ref.read(appDataProvider.notifier).dismissNotice(widget.notice.id);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(appDataProvider).valueOrNull;
    final accounts = data?.activeAccounts ?? const <Account>[];
    final categories = data?.categories ?? const <Category>[];
    final code = data?.currencyCode ?? 'PKR';
    if (_accountId == null && accounts.isNotEmpty) {
      _accountId = accounts.first.id;
    }
    final canAdd = accounts.isNotEmpty && (Money.parse(_amount.text) ?? 0) > 0;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(code),
            const SizedBox(height: AppSpacing.md),
            _rawText(),
            const SizedBox(height: AppSpacing.md),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Expense')),
                ButtonSegment(value: false, label: Text('Income')),
              ],
              selected: {_isExpense},
              onSelectionChanged: (s) => setState(() => _isExpense = s.first),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Amount',
                prefixText: Money.symbol(code),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _note,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Purpose / note',
                hintText: 'What was this for?',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.event_outlined),
              label: Text(DateFormat.yMMMd().add_jm().format(_date)),
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _accountId,
              decoration: const InputDecoration(
                labelText: 'Account',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final a in accounts)
                  DropdownMenuItem(value: a.id, child: Text(a.name)),
              ],
              onChanged: (v) => setState(() => _accountId = v),
            ),
            if (_isExpense) ...[
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<String?>(
                isExpanded: true,
                initialValue: _categoryId,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('Uncategorized'),
                  ),
                  for (final c in categories)
                    DropdownMenuItem(value: c.id, child: Text(c.name)),
                ],
                onChanged: (v) => setState(() => _categoryId = v),
              ),
            ],
            if (accounts.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: AppSpacing.sm),
                child: Text('Add an account first to save this.'),
              ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: canAdd ? _add : null,
              child: const Text('Add transaction'),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(onPressed: _dismiss, child: const Text('Dismiss')),
          ],
        ),
      ),
    );
  }

  Widget _header(String code) {
    final c = _candidate;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          c == null
              ? 'Fill in this one yourself'
              : '${c.direction == TxnDirection.debit ? 'Expense' : 'Income'} · '
                    '${Money.format(c.amountMinor, code: code)}',
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 2),
        Text(
          c == null
              ? "Budgetly couldn't read an amount here — type it below."
              : c.merchant ?? 'Detected from your bank alert',
          style: theme.textTheme.bodyMedium,
        ),
      ],
    );
  }

  Widget _rawText() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(AppSpacing.sm),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      widget.notice.rawText,
      style: Theme.of(context).textTheme.bodySmall,
    ),
  );
}
