import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:budgetly/src/core/money.dart';

/// Full-page editor for the amount that should be held back as savings.
/// Pops the new target in minor units, or nothing when cancelled.
class SavingsTargetScreen extends StatefulWidget {
  const SavingsTargetScreen({
    required this.initialMinor,
    required this.code,
    super.key,
  });

  final int initialMinor;
  final String code;

  @override
  State<SavingsTargetScreen> createState() => _SavingsTargetScreenState();
}

class _SavingsTargetScreenState extends State<SavingsTargetScreen> {
  late final TextEditingController _amount = TextEditingController(
    text: widget.initialMinor == 0 ? '' : Money.toInput(widget.initialMinor),
  );
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _save() {
    final text = _amount.text.trim();
    // An empty field is the deliberate way to say "no target".
    if (text.isEmpty) {
      Navigator.pop(context, 0);
      return;
    }
    final minor = Money.parse(text);
    if (minor == null) {
      setState(() => _error = 'Enter a valid amount.');
      return;
    }
    Navigator.pop(context, minor);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Savings target'),
        actions: [TextButton(onPressed: _save, child: const Text('Save'))],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          AppSpacing.sm,
          AppSpacing.gutter,
          AppSpacing.xl,
        ),
        children: [
          AppTextField(
            controller: _amount,
            autofocus: true,
            label: 'Target amount',
            prefixText: Money.symbol(widget.code),
            helper: 'Leave blank for no target',
            errorText: _error,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textStyle: AppTextStyles.numberMedium,
            onChanged: (_) => setState(() => _error = null),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'This is how much you want held back as savings across all your '
            'accounts. Budgetly compares it with what you have actually '
            'earmarked and shows the difference, plus or minus.',
            style: AppTextStyles.bodyMedium.copyWith(
              color: SuiteColors.of(context).textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          VaultButton(label: 'Save target', onPressed: _save),
        ],
      ),
    );
  }
}
