import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:df_settings/df_settings.dart';
import 'package:df_theme/df_theme.dart';
import '../../app/unsubscribe_strings.dart';
import '../../db/database.dart';

class AutoUnsubscribeNotifier extends Notifier<bool> {
  @override
  bool build() {
    final db = ref.watch(databaseProvider);
    return db.isAutoUnsubscribeEnabled;
  }

  void toggle([bool? val]) {
    final next = val ?? !state;
    state = next;
    final db = ref.read(databaseProvider);
    db.setSetting('auto_unsubscribe', next.toString());
  }

  void set(bool val) => toggle(val);
}

final autoUnsubscribeProvider =
    NotifierProvider<AutoUnsubscribeNotifier, bool>(AutoUnsubscribeNotifier.new);

class UnsubscribeTile extends ConsumerWidget {
  const UnsubscribeTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(autoUnsubscribeProvider);
    final palette = context.df.colors;

    return DfSettingsTile(
      title: const Text(UnsubscribeStrings.settingTitle),
      subtitle: const Text(UnsubscribeStrings.settingSubtitle),
      trailing: Switch(
        value: enabled,
        activeThumbColor: palette.brand.base,
        onChanged: (val) => ref.read(autoUnsubscribeProvider.notifier).toggle(val),
      ),
      onTap: () => ref.read(autoUnsubscribeProvider.notifier).toggle(!enabled),
    );
  }
}
