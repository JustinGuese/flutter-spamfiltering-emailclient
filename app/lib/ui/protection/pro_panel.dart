import 'package:df_funnel/df_funnel.dart';
import 'package:df_theme/df_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import '../../app/strings.dart';
import '../../app/ui_strings.dart';
import '../../theme/app_type.dart';
import '../common/mail_queries.dart';
import '../premium/app_upsell.dart';

/// Pro stage of the story: what a new device knows with and without Pro.
/// Only sync is claimed here; the neural scorer is not shipped yet.
class ProStagePanel extends ConsumerWidget {
  /// Words this device has learned. Pro would carry that to a new device.
  final int learned;
  const ProStagePanel({super.key, required this.learned});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.df.colors;
    final isPro = ref.watch(dfEffectivePremiumProvider);

    Widget column(String label, int words, String caption, Color color, {required bool highlighted}) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(context.df.shape.md),
              border: Border.all(color: highlighted ? c.brand.base : c.hairline, width: highlighted ? 1.5 : 1),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label.toUpperCase(), style: AppType.mono(c.textTertiary, size: 10.5, weight: FontWeight.w700, letterSpacing: 1.4)),
              const SizedBox(height: 8),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: words.toDouble()),
                duration: const Duration(milliseconds: 1100),
                curve: Curves.easeOutCubic,
                builder: (_, v, _) => Text(groupThousands(v.round()), style: AppType.display(color, size: 38, weight: 600, height: 1, letterSpacing: -1)),
              ),
              const SizedBox(height: 2),
              Text(UiStrings.proPanelWords, style: AppType.mono(c.textTertiary, size: 10.5)),
              const SizedBox(height: 10),
              Text(caption, style: AppType.ui(c.textSecondary, size: 13, height: 1.35)),
            ]),
          ),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(UiStrings.proPanelTitle, style: AppType.display(c.textPrimary, size: 20, weight: 600, letterSpacing: -0.3)),
      const SizedBox(height: 12),
      IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          column(UiStrings.proPanelFree, 0, UiStrings.proPanelFreeBody, c.textTertiary, highlighted: false),
          const SizedBox(width: 12),
          column(UiStrings.proPanelProLabel, learned, UiStrings.proPanelProBody, c.brand.deep, highlighted: true),
        ]),
      ),
      const SizedBox(height: 12),
      Text(UiStrings.proPanelFootnote, style: AppType.ui(c.textTertiary, size: 12, height: 1.4)),
      if (isPro) ...[const SizedBox(height: 16), _ActiveNote()],
    ]);
  }
}

class _ActiveNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.df.colors;
    return Row(children: [
      Icon(Icons.verified_rounded, size: 18, color: c.brand.deep),
      const SizedBox(width: 8),
      Expanded(child: Text(UiStrings.proPanelActive, style: AppType.ui(c.textPrimary, size: 14, weight: FontWeight.w600))),
    ]);
  }
}

/// Compact upsell pinned to the bottom of the protection screen for non-Pro users. The sheet it
/// opens carries the price and renewal terms and an equal-weight "Maybe later".
class ProUpsellCard extends StatelessWidget {
  /// Title and button only, for phone-width footers.
  final bool compact;
  const ProUpsellCard({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final c = context.df.colors;
    return Container(
      padding: EdgeInsets.all(compact ? 12 : 18),
      decoration: BoxDecoration(
        color: c.brand.container,
        borderRadius: BorderRadius.circular(context.df.shape.md),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(UiStrings.proCtaTitle, style: AppType.display(c.brand.onContainer, size: compact ? 16 : 20, weight: 600, letterSpacing: -0.3)),
            if (!compact) ...[
              const SizedBox(height: 4),
              Text(UiStrings.proCtaBody, style: AppType.ui(c.brand.onContainer, size: 13.5, height: 1.4)),
            ],
          ]),
        ),
        const SizedBox(width: 14),
        FilledButton(
          onPressed: () => AppUpsell.show(context),
          style: FilledButton.styleFrom(
            backgroundColor: c.brand.deep,
            foregroundColor: c.textOnBrand,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(context.df.shape.pill)),
          ),
          child: Text(AppStrings.proUpgrade, style: AppType.ui(c.textOnBrand, size: 14, weight: FontWeight.w600)),
        ),
      ]),
    );
  }
}
