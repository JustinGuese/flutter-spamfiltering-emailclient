import 'dart:math' as math;

import 'package:df_theme/df_theme.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/ui_strings.dart';
import '../../theme/app_type.dart';
import '../common/app_parts.dart';

/// Page 1: a small stack of ruled papers sealed in brass.
class PaperStackArt extends StatelessWidget {
  const PaperStackArt({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.df.colors;
    Widget sheet(double angle, double dx, double dy, {bool front = false}) => Transform.translate(
          offset: Offset(dx, dy),
          child: Transform.rotate(
            angle: angle * math.pi / 180,
            child: Container(
              width: 250,
              height: 190,
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(context.df.shape.md),
                border: Border.all(color: c.hairline),
                boxShadow: context.df.cardShadow,
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(children: [
                LedgerPaper(lineGap: 22, offset: 58, margin: true, child: const SizedBox.shrink()),
                if (front)
                  Padding(
                    padding: const EdgeInsets.all(18),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Monogram(name: 'Mara Lindqvist', seed: 'mara', size: 34),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Container(height: 9, width: 90, decoration: BoxDecoration(color: c.textPrimary.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(5))),
                          const SizedBox(height: 7),
                          Container(height: 7, width: 140, decoration: BoxDecoration(color: c.hairline, borderRadius: BorderRadius.circular(4))),
                        ]),
                      ),
                    ]),
                  ),
              ]),
            ),
          ),
        );
    return SizedBox(
      width: 320,
      height: 280,
      child: Stack(alignment: Alignment.center, children: [
        sheet(-7, -18, -6),
        sheet(4, 14, 8),
        sheet(-1.5, 0, 0, front: true),
        Positioned(
          right: 22,
          bottom: 30,
          child: Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [c.brand.base, c.brand.deep]),
              boxShadow: [BoxShadow(color: c.brand.deep.withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, 8))],
              border: Border.all(color: c.brand.soft, width: 2),
            ),
            child: Icon(Icons.lock_outline_rounded, color: c.textOnBrand, size: 26),
          ),
        ),
      ]),
    );
  }
}

/// Page 2: one click teaches the filter; the verdict is stamped onto the message.
class VerdictDemoArt extends StatelessWidget {
  const VerdictDemoArt({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.df.colors;
    Widget pill(String text, IconData icon, {bool on = false}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: on ? c.error.bg : Colors.transparent,
            borderRadius: BorderRadius.circular(context.df.shape.pill),
            border: Border.all(color: on ? c.error.base.withValues(alpha: 0.4) : c.border),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 14, color: on ? c.error.deep : c.textSecondary),
            const SizedBox(width: 5),
            Text(text, style: AppType.ui(on ? c.error.deep : c.textSecondary, size: 12, weight: FontWeight.w600)),
          ]),
        );
    return SizedBox(
      width: 330,
      height: 280,
      child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
        Container(
          width: 310,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(context.df.shape.md),
            border: Border.all(color: c.hairline),
            boxShadow: context.df.cardShadow,
          ),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Monogram(name: UiStrings.artSender, seed: 'prize', size: 34),
              const SizedBox(width: 10),
              Text(UiStrings.artSender, style: AppType.ui(c.textPrimary, size: 14, weight: FontWeight.w700)),
            ]),
            const SizedBox(height: 12),
            Text(UiStrings.artSubject, style: AppType.display(c.textPrimary, size: 19, weight: 600, height: 1.15, letterSpacing: -0.3)),
            const SizedBox(height: 16),
            Wrap(spacing: 6, runSpacing: 6, children: [
              pill(UiStrings.artVerdictInbox, Icons.inbox_outlined),
              pill(UiStrings.artVerdictNewsletter, Icons.auto_stories_outlined),
              pill(UiStrings.artVerdictSpam, Icons.block_rounded, on: true),
            ]),
          ]),
        ),
        Positioned(
          right: -2,
          top: 6,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: context.df.motion.slow,
            curve: context.df.motion.emphasis,
            builder: (context, t, child) =>
                Transform.rotate(angle: -8 * math.pi / 180, child: Transform.scale(scale: 1.4 - 0.4 * t, child: child)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                border: Border.all(color: c.error.base, width: 3),
                borderRadius: BorderRadius.circular(8),
                color: c.surface.withValues(alpha: 0.9),
              ),
              child: Text(UiStrings.artStamp, style: AppType.display(c.error.base, size: 26, weight: 800, letterSpacing: 3, height: 1)),
            ),
          ),
        ),
        Positioned(
          right: 8,
          bottom: 14,
          child: Text(UiStrings.artLearned, style: AppType.mono(c.error.deep, size: 10.5, weight: FontWeight.w700)),
        ),
      ]),
    );
  }
}

/// Page 3: what actually leaves the device: fingerprints, never mail.
class HashLedgerArt extends StatelessWidget {
  const HashLedgerArt({super.key});

  static String _hex(String s) {
    var h = 0xcbf29ce484222325 & 0xFFFFFFFF;
    for (final u in s.codeUnits) {
      h = ((h ^ u) * 0x01000193) & 0xFFFFFFFF;
    }
    final x = h.toRadixString(16).padLeft(8, '0');
    return '${x.substring(0, 4)} ${x.substring(4)}';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.df.colors;
    final rows = [
      (UiStrings.artKindBody, 'selected reward luxury'),
      (UiStrings.artKindUrl, 'claim-now-today.example'),
      (UiStrings.artKindDomain, 'claim-now-today.example/redeem'),
      (UiStrings.artKindBody, 'verify your account now'),
    ];
    return SizedBox(
      width: 320,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(context.df.shape.md),
            border: Border.all(color: c.hairline),
            boxShadow: context.df.cardShadow,
          ),
          child: Column(children: [
            for (var i = 0; i < rows.length; i++) ...[
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: Duration(milliseconds: 300 + 120 * i),
                curve: context.df.motion.standard,
                builder: (context, t, child) => Transform.translate(offset: Offset(0, 8 * (1 - t)), child: child),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                  child: Row(children: [
                    SizedBox(width: 56, child: Text(rows[i].$1.toUpperCase(), style: AppType.mono(c.accent.base, size: 10, weight: FontWeight.w700, letterSpacing: 1.2))),
                    Text(_hex(rows[i].$2), style: AppType.mono(c.textPrimary, size: 15, weight: FontWeight.w600)),
                    const Spacer(),
                    Icon(Icons.check_rounded, size: 16, color: c.accent.base),
                  ]),
                ),
              ),
              if (i < rows.length - 1) Divider(height: 1, color: c.hairline),
            ],
          ]),
        ),
        const SizedBox(height: 18),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.shield_outlined, size: 16, color: c.accent.base),
          const SizedBox(width: 8),
          Flexible(child: Text(UiStrings.artHashCaption, style: AppType.ui(c.textSecondary, size: 13.5, weight: FontWeight.w600))),
        ]),
      ]),
    );
  }
}
