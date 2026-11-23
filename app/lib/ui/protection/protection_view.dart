import 'package:df_funnel/df_funnel.dart';
import 'package:df_theme/df_theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import '../../app/ui_strings.dart';
import '../../db/database.dart';
import '../../filter/protection_stats.dart';
import '../../mail/sync_engine.dart';
import '../../theme/app_type.dart';
import '../common/app_parts.dart';
import '../common/mail_queries.dart';
import 'pro_panel.dart';
import 'protection_story.dart';

enum ProtectionTab { story, caught, learned }

/// Full-screen "Your protection" view opened from the sidebar's filter card:
/// a replay of what each layer catches, the caught list, and what was learned.
class ProtectionView extends ConsumerWidget {
  final ProtectionTab initialTab;
  const ProtectionView({super.key, this.initialTab = ProtectionTab.story});

  static void open(BuildContext context, {ProtectionTab tab = ProtectionTab.story}) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => ProtectionView(initialTab: tab),
    ));
  }

  /// Shown while nothing has been caught yet, and labelled as an example.
  static const sample = ProtectionStats(
    total: 47,
    filterCaught: 36,
    communityOnly: 11,
    corrections: 0,
    learnedTokens: 812,
    spamLeaning: 305,
    hamLeaning: 507,
    blocklistEntries: 0,
    recent: [],
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.df.colors;
    ref.watch(mailRevisionProvider);
    final real = computeProtection(ref.watch(databaseProvider));
    final isSample = real.isEmpty;
    final stats = isSample ? sample : real;
    final isPro = ref.watch(dfEffectivePremiumProvider);
    final narrow = MediaQuery.sizeOf(context).width < 700;

    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).maybePop()},
      child: Focus(
        autofocus: true,
        child: DefaultTabController(
          length: ProtectionTab.values.length,
          initialIndex: initialTab.index,
          child: Scaffold(
            backgroundColor: c.canvas,
            body: SafeArea(
              child: Column(children: [
                Container(
                  height: 68,
                  padding: EdgeInsets.symmetric(horizontal: narrow ? 8 : 24),
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.hairline))),
                  child: Row(children: [
                    IconButton(icon: const Icon(Icons.close_rounded), tooltip: UiStrings.protectionClose, onPressed: () => Navigator.of(context).maybePop()),
                    const SizedBox(width: 4),
                    Text(UiStrings.protectionTitle, style: AppType.display(c.textPrimary, size: 22, weight: 600, letterSpacing: -0.4)),
                  ]),
                ),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 820),
                    child: TabBar(
                      labelStyle: AppType.ui(c.textPrimary, size: 14, weight: FontWeight.w700),
                      unselectedLabelStyle: AppType.ui(c.textTertiary, size: 14, weight: FontWeight.w600),
                      labelColor: c.brand.deep,
                      unselectedLabelColor: c.textTertiary,
                      indicatorColor: c.brand.deep,
                      dividerColor: c.hairline,
                      tabs: const [
                        Tab(text: UiStrings.protectionTabStory),
                        Tab(text: UiStrings.protectionTabCaught),
                        Tab(text: UiStrings.protectionTabLearned),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: TabBarView(children: [
                    _Page(
                      narrow: narrow,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (isSample) const _SampleBanner(),
                        ProtectionStory(stats: stats, proPanel: ProStagePanel(learned: stats.learnedTokens)),
                      ]),
                    ),
                    _Page(narrow: narrow, child: _CaughtList(stats: real)),
                    _Page(narrow: narrow, child: _Learned(stats: stats, isSample: isSample)),
                  ]),
                ),
                if (!isPro)
                  Container(
                    padding: EdgeInsets.fromLTRB(narrow ? 12 : 24, narrow ? 8 : 12, narrow ? 12 : 24, narrow ? 8 : 12),
                    decoration: BoxDecoration(color: c.canvas, border: Border(top: BorderSide(color: c.hairline))),
                    child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 820), child: ProUpsellCard(compact: narrow))),
                  ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _Page extends StatelessWidget {
  final bool narrow;
  final Widget child;
  const _Page({required this.narrow, required this.child});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: narrow ? 20 : 32, vertical: 24),
        child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 756), child: child)),
      );
}

class _SampleBanner extends StatelessWidget {
  const _SampleBanner();

  @override
  Widget build(BuildContext context) {
    final c = context.df.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: c.warning.bg, borderRadius: BorderRadius.circular(context.df.shape.md)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.info_outline_rounded, size: 18, color: c.warning.deep),
        const SizedBox(width: 10),
        Expanded(
          child: Text.rich(TextSpan(children: [
            TextSpan(text: '${UiStrings.storySampleTitle}. ', style: AppType.ui(c.warning.deep, size: 13, weight: FontWeight.w700)),
            TextSpan(text: UiStrings.storySampleBody, style: AppType.ui(c.warning.deep, size: 13, height: 1.4)),
          ])),
        ),
      ]),
    );
  }
}

class _CaughtList extends StatelessWidget {
  final ProtectionStats stats;
  const _CaughtList({required this.stats});

  @override
  Widget build(BuildContext context) {
    final c = context.df.colors;
    if (stats.recent.isEmpty) {
      return Padding(padding: const EdgeInsets.only(top: 40), child: Center(child: Text(UiStrings.caughtEmpty, style: AppType.ui(c.textTertiary, size: 15))));
    }
    Widget chip(CaughtMessage m) {
      final (label, color) = m.byYou
          ? (UiStrings.caughtByYou, c.brand.deep)
          : m.by == CaughtBy.community
              ? (UiStrings.caughtByCommunity, c.accent.base)
              : (UiStrings.caughtByFilter, c.success.deep);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
        child: Text(label.toUpperCase(), style: AppType.mono(color, size: 10, weight: FontWeight.w700, letterSpacing: 1)),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Eyebrow(UiStrings.caughtShowing(stats.recent.length, stats.total)),
      const SizedBox(height: 8),
      for (final m in stats.recent)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.hairline))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(m.subject.isEmpty ? UiStrings.caughtNoSubject : m.subject,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.ui(c.textPrimary, size: 14.5, weight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(m.sender, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.mono(c.textTertiary, size: 11)),
              ]),
            ),
            const SizedBox(width: 12),
            chip(m),
          ]),
        ),
    ]);
  }
}

class _Learned extends StatelessWidget {
  final ProtectionStats stats;
  final bool isSample;
  const _Learned({required this.stats, required this.isSample});

  @override
  Widget build(BuildContext context) {
    final c = context.df.colors;
    final total = stats.spamLeaning + stats.hamLeaning;

    Widget bar(String label, int n, Color color) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(label, style: AppType.ui(c.textSecondary, size: 13.5))),
              Text(groupThousands(n), style: AppType.mono(c.textPrimary, size: 13, weight: FontWeight.w700)),
            ]),
            const SizedBox(height: 6),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: total == 0 ? 0 : n / total),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (_, v, _) => ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: v, minHeight: 8, color: color, backgroundColor: c.surfaceSunken),
              ),
            ),
          ]),
        );

    Widget fact(int n, String label) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            SizedBox(width: 72, child: Text(groupThousands(n), style: AppType.display(c.textPrimary, size: 24, weight: 600, height: 1, letterSpacing: -0.4))),
            Expanded(child: Text(label, style: AppType.ui(c.textSecondary, size: 13.5))),
          ]),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (isSample) const _SampleBanner(),
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: stats.learnedTokens.toDouble()),
          duration: const Duration(milliseconds: 1100),
          curve: Curves.easeOutCubic,
          builder: (_, v, _) => Text(groupThousands(v.round()), style: AppType.display(c.brand.deep, size: 64, weight: 600, height: 1, letterSpacing: -2)),
        ),
        const SizedBox(width: 12),
        Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(UiStrings.learnedHeadline, style: AppType.mono(c.textTertiary, size: 11.5, weight: FontWeight.w600))),
      ]),
      const SizedBox(height: 12),
      Text(UiStrings.learnedBody, style: AppType.ui(c.textSecondary, size: 15, height: 1.45)),
      const SizedBox(height: 18),
      bar(UiStrings.learnedSpamWords, stats.spamLeaning, c.error.base),
      bar(UiStrings.learnedHamWords, stats.hamLeaning, c.success.base),
      const SizedBox(height: 10),
      fact(stats.corrections, UiStrings.learnedCorrections),
      fact(stats.blocklistEntries, UiStrings.learnedBlocklist),
      const SizedBox(height: 10),
      Text(UiStrings.learnedPrivacy, style: AppType.ui(c.textTertiary, size: 12, height: 1.4)),
    ]);
  }
}
