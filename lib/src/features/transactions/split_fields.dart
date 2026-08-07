import 'package:core_theme/core_theme.dart';
import 'package:flutter/material.dart';
import 'package:budgetly/src/core/logic/people.dart';
import 'package:budgetly/src/core/money.dart';

/// The split section of the transaction editor: which way the split points,
/// who it is with, and how much — with a running "your share" so the owner
/// always sees the number that will count as their spending.
class SplitFields extends StatefulWidget {
  const SplitFields({
    required this.kind,
    required this.onKind,
    required this.person,
    required this.share,
    required this.knownNames,
    required this.paidMinor,
    required this.code,
    required this.onChanged,
    super.key,
  });

  final DebtKind kind;
  final ValueChanged<DebtKind> onKind;
  final TextEditingController person;
  final TextEditingController share;
  final List<String> knownNames;

  /// What the owner paid out of their own account (the Amount field).
  final int paidMinor;
  final String code;
  final VoidCallback onChanged;

  @override
  State<SplitFields> createState() => _SplitFieldsState();
}

class _SplitFieldsState extends State<SplitFields> {
  final _personFocus = FocusNode();

  @override
  void dispose() {
    _personFocus.dispose();
    super.dispose();
  }

  int get _shareMinor => Money.parse(widget.share.text) ?? 0;

  /// Their share of what the owner paid, or the owner's share someone else
  /// fronted — the same arithmetic the model uses.
  String get _yourShare {
    final owed = widget.kind == DebtKind.owedToYou ? _shareMinor : 0;
    final owe = widget.kind == DebtKind.youOwe ? _shareMinor : 0;
    final share = (widget.paidMinor - owed + owe).clamp(0, 1 << 62);
    return Money.format(share, code: widget.code);
  }

  @override
  Widget build(BuildContext context) {
    final receivable = widget.kind == DebtKind.owedToYou;
    final who = widget.person.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<DebtKind>(
          segments: const [
            ButtonSegment(
              value: DebtKind.owedToYou,
              label: Text('They owe me'),
            ),
            ButtonSegment(value: DebtKind.youOwe, label: Text('I owe them')),
          ],
          selected: {widget.kind},
          onSelectionChanged: (s) => widget.onKind(s.first),
        ),
        const SizedBox(height: AppSpacing.md),
        _PersonField(
          controller: widget.person,
          focusNode: _personFocus,
          names: widget.knownNames,
          onChanged: () {
            setState(() {});
            widget.onChanged();
          },
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: widget.share,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: receivable
                ? 'Amount owed back to you'
                : 'Amount you owe${who.isEmpty ? '' : ' $who'}',
            prefixText: '${widget.code} ',
            helperText: receivable
                ? 'The part of what you paid that comes back to you'
                : 'Your share that they fronted — no cash left your account',
          ),
          onChanged: (_) {
            setState(() {});
            widget.onChanged();
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Your share: $_yourShare — this is what counts as your spending.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}

/// Free-text name with suggestions from names already used. Deliberately not
/// a contacts integration — nothing leaves the app.
class _PersonField extends StatelessWidget {
  const _PersonField({
    required this.controller,
    required this.focusNode,
    required this.names,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final List<String> names;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<String>(
      textEditingController: controller,
      focusNode: focusNode,
      optionsBuilder: (value) {
        final q = value.text.trim().toLowerCase();
        if (q.isEmpty) return names;
        return names.where((n) => n.toLowerCase().contains(q));
      },
      onSelected: (_) => onChanged(),
      fieldViewBuilder: (context, textController, node, onSubmit) => TextField(
        controller: textController,
        focusNode: node,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(
          labelText: 'With whom',
          hintText: 'e.g. Ali',
          prefixIcon: Icon(Icons.person_outline),
        ),
        onChanged: (_) => onChanged(),
        onSubmitted: (_) => onSubmit(),
      ),
      optionsViewBuilder: (context, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 3,
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 200, maxWidth: 320),
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              children: [
                for (final o in options)
                  ListTile(
                    dense: true,
                    title: Text(o),
                    onTap: () => onSelected(o),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
