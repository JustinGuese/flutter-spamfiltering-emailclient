import 'package:material_ui/material_ui.dart';
import 'package:df_theme/df_theme.dart';
import '../../app/strings.dart';
import '../../app/ui_strings.dart';
import '../../theme/app_type.dart';

/// Modal upsell sheet adhering strictly to honest pricing guidelines:
/// - Price and renewal terms clearly visible
/// - Equal prominence close button
/// - Zero fake timers or dark patterns
class AppUpsellSheet extends StatelessWidget {
  final VoidCallback onDismiss;
  final VoidCallback onSubscribed;

  const AppUpsellSheet({
    super.key,
    required this.onDismiss,
    required this.onSubscribed,
  });

  static void show(BuildContext context, {VoidCallback? onSubscribed}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.df.colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => AppUpsellSheet(
        onDismiss: () => Navigator.of(context).pop(),
        onSubscribed: () {
          Navigator.of(context).pop();
          onSubscribed?.call();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.df.colors;
    Widget point(IconData icon, String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(color: c.brand.container, borderRadius: BorderRadius.circular(9)),
              child: Icon(icon, size: 16, color: c.brand.onContainer),
            ),
            const SizedBox(width: 14),
            Expanded(child: Padding(padding: const EdgeInsets.only(top: 5), child: Text(text, style: AppType.ui(c.textSecondary, size: 14, height: 1.4)))),
          ]),
        );

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 14, 28, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(width: 40, height: 4, decoration: BoxDecoration(color: c.border, borderRadius: BorderRadius.circular(2))),
                ),
                const SizedBox(height: 14),
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: c.brand.deep, borderRadius: BorderRadius.circular(6)),
                    child: Text(UiStrings.upsellEyebrow.toUpperCase(), style: AppType.mono(c.textOnBrand, size: 10.5, weight: FontWeight.w700, letterSpacing: 1.6)),
                  ),
                  const Spacer(),
                  IconButton(icon: const Icon(Icons.close_rounded), tooltip: UiStrings.upsellLater, onPressed: onDismiss),
                ]),
                const SizedBox(height: 4),
                Text(UiStrings.upsellHeadline, style: AppType.display(c.textPrimary, size: 36, weight: 550, height: 1.04, letterSpacing: -1)),
                const SizedBox(height: 10),
                Text(UiStrings.upsellSub, style: AppType.ui(c.textSecondary, size: 15.5, height: 1.45)),
                const SizedBox(height: 18),
                point(Icons.sync_rounded, UiStrings.upsellPoint1),
                point(Icons.devices_rounded, UiStrings.upsellPoint2),
                point(Icons.lock_outline_rounded, UiStrings.upsellPoint3),
                point(Icons.key_rounded, UiStrings.upsellPoint4),
                const SizedBox(height: 10),
                Text(UiStrings.upsellFreeNote, style: AppType.ui(c.textTertiary, size: 12.5, height: 1.4)),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(context.df.shape.md),
                    border: Border.all(color: c.brand.base.withValues(alpha: 0.6), width: 1.5),
                    boxShadow: context.df.cardShadow,
                  ),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(UiStrings.upsellAnnual, style: AppType.ui(c.textPrimary, size: 15, weight: FontWeight.w700)),
                        const SizedBox(height: 3),
                        Text(UiStrings.upsellRenewal, style: AppType.ui(c.textTertiary, size: 12, height: 1.35)),
                      ]),
                    ),
                    const SizedBox(width: 12),
                    Text(AppStrings.proAnnual, style: AppType.mono(c.textPrimary, size: 15, weight: FontWeight.w700)),
                  ]),
                ),
                const SizedBox(height: 18),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onDismiss,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: BorderSide(color: c.border),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(context.df.shape.md)),
                      ),
                      child: Text(UiStrings.upsellLater, style: AppType.ui(c.textPrimary, size: 15, weight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: onSubscribed,
                      style: FilledButton.styleFrom(
                        backgroundColor: c.brand.deep,
                        foregroundColor: c.textOnBrand,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(context.df.shape.md)),
                      ),
                      child: Text(AppStrings.proUpgrade, style: AppType.ui(c.textOnBrand, size: 15, weight: FontWeight.w600)),
                    ),
                  ),
                ]),
              ],
            ),
          ),
          ),
        ),
      ),
    );
  }
}
