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
import 'package:budgetly/src/features/capture/review_fields.dart';
import 'package:budgetly/src/features/capture/sms_parser.dart';
import 'package:budgetly/src/features/capture/transfer_hint.dart';
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
  late CaptureMode _mode;
  late bool _transferSuggested;
  late DateTime _date;
  String? _accountId;
  String? _toAccountId;
  String? _categoryId;

  @override
  void initState() {
    super.initState();
    final parsed = SmsParser.parse(
      sender: 'notification',
      body: widget.notice.rawText,
    );
    _candidate = parsed;
    _mode = CaptureModeHint.suggest(
      rawText: widget.notice.rawText,
      parsed: parsed,
    );
    _transferSuggested = _mode == CaptureMode.transfer;
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

  bool get _isTransfer => _mode == CaptureMode.transfer;

  /// Picks the accounts the two ends of a withdrawal usually mean: money out
  /// of the bank/card the alert came from, into wherever cash is kept.
  void _fillDefaults(List<Account> accounts) {
    if (accounts.isEmpty) return;
    _accountId ??= accounts
        .firstWhere(
          (a) => a.type == AccountType.bank || a.type == AccountType.card,
          orElse: () => accounts.first,
        )
        .id;
    if (!_isTransfer || _toAccountId != null) return;
    final cash = accounts
        .where((a) => a.id != _accountId && a.type == AccountType.cash)
        .firstOrNull;
    _toAccountId =
        (cash ?? accounts.where((a) => a.id != _accountId).firstOrNull)?.id;
  }

  bool _canAdd(List<Account> accounts) {
    if (accounts.isEmpty) return false;
    if ((Money.parse(_amount.text) ?? 0) <= 0) return false;
    if (_accountId == null) return false;
    if (!_isTransfer) return true;
    return _toAccountId != null && _toAccountId != _accountId;
  }

  Future<void> _add() async {
    final minor = Money.parse(_amount.text);
    if (minor == null || minor <= 0 || _accountId == null) return;
    if (_isTransfer && (_toAccountId == null || _toAccountId == _accountId)) {
      return;
    }
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final txn = Txn(
      id: const Uuid().v4(),
      type: _mode.txnType,
      amountMinor: minor,
      date: _date,
      accountId: _accountId!,
      toAccountId: _isTransfer ? _toAccountId : null,
      categoryId: _mode == CaptureMode.expense ? _categoryId : null,
      note: _note.text.trim(),
      createdAt: ref.read(clockProvider)(),
    );
    await ref
        .read(appDataProvider.notifier)
        .addTxnForNotice(txn, widget.notice.id);
    navigator.pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text(_isTransfer ? 'Transfer added.' : 'Transaction added.'),
      ),
    );
  }

  Future<void> _dismiss() async {
    final navigator = Navigator.of(context);
    await ref.read(appDataProvider.notifier).dismissNotice(widget.notice.id);
    navigator.pop();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2015),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
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

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(appDataProvider).valueOrNull;
    final accounts = data?.activeAccounts ?? const <Account>[];
    final categories = data?.categories ?? const <Category>[];
    final code = data?.currencyCode ?? 'PKR';
    _fillDefaults(accounts);
    final sameAccount =
        _isTransfer && _toAccountId != null && _toAccountId == _accountId;

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
            CapturedRawText(text: widget.notice.rawText),
            const SizedBox(height: AppSpacing.md),
            CaptureModeSelector(
              mode: _mode,
              onChanged: (m) => setState(() => _mode = m),
            ),
            if (_transferSuggested) ...[
              const SizedBox(height: AppSpacing.sm),
              const _TransferHintLine(),
            ],
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
            ..._accountFields(accounts, sameAccount),
            if (_mode == CaptureMode.expense) ...[
              const SizedBox(height: AppSpacing.md),
              CategoryPicker(
                categories: categories,
                value: _categoryId,
                onChanged: (v) => setState(() => _categoryId = v),
              ),
            ],
            if (accounts.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: AppSpacing.sm),
                child: Text('Add an account first to save this.'),
              ),
            if (_isTransfer && accounts.length < 2)
              const Padding(
                padding: EdgeInsets.only(top: AppSpacing.sm),
                child: Text(
                  'A transfer needs two accounts — add the one the money went '
                  'into (for example Cash).',
                ),
              ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: _canAdd(accounts) ? _add : null,
              child: Text(_isTransfer ? 'Add transfer' : 'Add transaction'),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(onPressed: _dismiss, child: const Text('Dismiss')),
          ],
        ),
      ),
    );
  }

  List<Widget> _accountFields(List<Account> accounts, bool sameAccount) {
    if (!_isTransfer) {
      return [
        AccountPicker(
          label: 'Account',
          accounts: accounts,
          value: _accountId,
          onChanged: (v) => setState(() => _accountId = v),
        ),
      ];
    }
    return [
      AccountPicker(
        label: 'From account',
        accounts: accounts,
        value: _accountId,
        onChanged: (v) => setState(() => _accountId = v),
      ),
      const SizedBox(height: AppSpacing.md),
      AccountPicker(
        label: 'To account',
        accounts: accounts,
        value: _toAccountId,
        errorText: sameAccount ? 'Pick a different account' : null,
        onChanged: (v) => setState(() => _toAccountId = v),
      ),
    ];
  }

  Widget _header(String code) {
    final c = _candidate;
    final theme = Theme.of(context);
    final title = c == null
        ? 'Fill in this one yourself'
        : '${_mode.label} · ${Money.format(c.amountMinor, code: code)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleLarge),
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
}

/// Why the sheet opened on Transfer. Says it is a guess, so overriding it feels
/// allowed.
class _TransferHintLine extends StatelessWidget {
  const _TransferHintLine();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(Icons.swap_horiz, size: 18, color: scheme.onSurfaceVariant),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            'Looks like a cash withdrawal — your money moved between your own '
            'accounts. Change it above if not.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}
