import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:budgetly/src/core/models/txn.dart';

/// The Expense / Income / Transfer choice, shared by the transaction editor
/// and the recurring editor so the two always offer the same wording.
class TxnTypeSelector extends StatelessWidget {
  const TxnTypeSelector({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final TxnType value;
  final ValueChanged<TxnType> onChanged;

  @override
  Widget build(BuildContext context) {
    return AppSegmentedControl<TxnType>(
      height: 48,
      segments: [
        for (final t in TxnType.values) AppSegment(value: t, label: t.label),
      ],
      selected: value,
      onChanged: onChanged,
    );
  }
}
