import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:df_theme/df_theme.dart';
import '../../app/strings.dart';
import '../../platform/platform_services.dart';

class AppearanceTile extends ConsumerWidget {
  const AppearanceTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.df.colors;
    final isComfortable = ref.watch(listDensityComfortableProvider);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(bottom: BorderSide(color: palette.hairline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppStrings.settingsAppearance,
            style: TextStyle(
              fontFamily: 'Public Sans',
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                AppStrings.settingsDensity,
                style: TextStyle(
                  fontFamily: 'Public Sans',
                  fontSize: 13,
                  color: palette.textSecondary,
                ),
              ),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: true,
                    label: Text('Comfortable', style: TextStyle(fontSize: 12)),
                  ),
                  ButtonSegment(
                    value: false,
                    label: Text('Compact', style: TextStyle(fontSize: 12)),
                  ),
                ],
                selected: {isComfortable},
                onSelectionChanged: (set) {
                  ref.read(listDensityComfortableProvider.notifier).set(set.first);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
