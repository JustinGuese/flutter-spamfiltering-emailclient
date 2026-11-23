import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:df_funnel/df_funnel.dart';
import 'package:df_theme/df_theme.dart';
import '../../app/strings.dart';
import '../../app/ui_strings.dart';
import 'upsell_sheet.dart';

class AppSubscriptionSection extends ConsumerWidget {
  const AppSubscriptionSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPro = ref.watch(dfEffectivePremiumProvider);
    final palette = context.df.colors;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(bottom: BorderSide(color: palette.hairline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                AppStrings.settingsPremium,
                style: TextStyle(
                  fontFamily: 'Public Sans',
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: palette.textPrimary,
                ),
              ),
              if (isPro)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: palette.brand.base.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    AppStrings.proActive,
                    style: TextStyle(
                      fontFamily: 'JetBrains Mono',
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: palette.brand.base,
                    ),
                  ),
                )
              else
                TextButton(
                  onPressed: () => AppUpsellSheet.show(context),
                  child: const Text(AppStrings.proUpgrade, style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            isPro ? UiStrings.proSectionActive : UiStrings.proSectionWhy,
            style: TextStyle(
              fontFamily: 'Public Sans',
              fontSize: 12,
              height: 1.4,
              color: palette.textSecondary,
            ),
          ),
          if (!isPro) ...[
            const SizedBox(height: 8),
            for (final b in const [
              UiStrings.proSectionBullet1,
              UiStrings.proSectionBullet2,
              UiStrings.proSectionBullet3,
            ])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check_rounded, size: 15, color: palette.accent.base),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        b,
                        style: TextStyle(fontFamily: 'Public Sans', fontSize: 12, height: 1.35, color: palette.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
