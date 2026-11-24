import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:df_app_shell/df_app_shell.dart';
import 'package:df_settings/df_settings.dart';
import 'package:df_theme/df_theme.dart';
import '../../app/strings.dart';
import '../../platform/platform_services.dart';

class AppearanceTile extends ConsumerWidget {
  const AppearanceTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.df.colors;
    final themeMode = ref.watch(dfThemeModeProvider);
    final isComfortable = ref.watch(listDensityComfortableProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DfThemeModeTile(
          currentMode: themeMode,
          onModeChanged: (mode) {
            ref.read(dfThemeModeProvider.notifier).setThemeMode(mode);
          },
        ),
        Divider(height: 1, thickness: 1, color: palette.hairline),
        DfSettingsTile(
          title: const Text(AppStrings.settingsDensity),
          subtitle: Text(
            isComfortable
                ? AppStrings.densityComfortable
                : AppStrings.densityCompact,
          ),
          trailing: Switch(
            value: isComfortable,
            activeThumbColor: palette.brand.base,
            onChanged: (val) {
              ref.read(listDensityComfortableProvider.notifier).set(val);
            },
          ),
          onTap: () {
            ref.read(listDensityComfortableProvider.notifier).toggle();
          },
        ),
      ],
    );
  }
}
