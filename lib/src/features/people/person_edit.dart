import 'package:core_theme/core_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:budgetly/src/core/data/app_data.dart';
import 'package:budgetly/src/core/logic/people.dart';
import 'package:budgetly/src/core/models/person.dart';
import 'package:budgetly/src/core/providers.dart';

/// Adds a person to the registry.
Future<void> showAddPersonDialog(BuildContext context, WidgetRef ref) async {
  final name = await _askForName(context, title: 'Add person');
  if (name == null || name.trim().isEmpty) return;
  final data = ref.read(appDataProvider).valueOrNull ?? const AppData();
  final already = data.personByName(name);
  await ref.read(appDataProvider.notifier).addPerson(name);
  if (already != null && context.mounted) {
    _say(context, '${already.name} is already on your list.');
  }
}

/// Renames a person — the record and the name shown on their transactions.
Future<void> showRenamePersonDialog(
  BuildContext context,
  WidgetRef ref,
  Person person,
) async {
  final name = await _askForName(
    context,
    title: 'Rename',
    initial: person.name,
  );
  if (name == null || name.trim().isEmpty) return;
  final data = ref.read(appDataProvider).valueOrNull ?? const AppData();
  final clash = data.personByName(name);
  if (clash != null && clash.id != person.id) {
    if (context.mounted) {
      _say(context, '${clash.name} is already on your list.');
    }
    return;
  }
  await ref.read(appDataProvider.notifier).renamePerson(person.id, name);
}

/// Deletes a person — **only when nothing references them**.
///
/// Policy: a person who still appears on a transaction cannot be deleted. The
/// alternative (reassigning their splits to somebody else) would silently move
/// real money between people, so the app blocks instead and says how many
/// transactions to clear first.
Future<void> confirmDeletePerson(
  BuildContext context,
  WidgetRef ref,
  Person person,
) async {
  final data = ref.read(appDataProvider).valueOrNull ?? const AppData();
  final used = PeopleLedger.txnCountFor(data, person.id);
  if (used > 0) {
    _say(
      context,
      '${person.name} is on $used transaction${used == 1 ? '' : 's'}. '
      'Remove them from those first — deleting now would lose who owes what.',
    );
    return;
  }
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Delete ${person.name}?'),
      content: const Text('Nothing is recorded with them, so nothing is lost.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  await ref.read(appDataProvider.notifier).deletePerson(person.id);
}

void _say(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

Future<String?> _askForName(
  BuildContext context, {
  required String title,
  String initial = '',
}) => Navigator.of(context).push<String>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => _PersonNameScreen(title: title, initial: initial),
  ),
);

/// A name is typed on its own page, not in a dialog box: the keyboard never
/// covers the field, and the save action stays where every other form in the
/// app puts it.
class _PersonNameScreen extends StatefulWidget {
  const _PersonNameScreen({required this.title, required this.initial});

  final String title;
  final String initial;

  @override
  State<_PersonNameScreen> createState() => _PersonNameScreenState();
}

class _PersonNameScreenState extends State<_PersonNameScreen> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [TextButton(onPressed: _submit, child: const Text('Save'))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'e.g. Ali',
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton(onPressed: _submit, child: const Text('Save')),
        ],
      ),
    );
  }
}
