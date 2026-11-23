import 'package:df_theme/df_theme.dart';
import 'package:material_ui/material_ui.dart';
import 'package:spam_core/spam_core.dart';

import '../../app/ui_strings.dart';
import '../../theme/app_type.dart';

/// The filter shows its work: verdict as a large figure, a stacked bar of how much
/// each signal contributed, and one ledger line per signal. All numbers come from
/// the stored `Verdict.evidence`; nothing here is invented.
class LedgerCard extends StatefulWidget {
  final Verdict verdict;
  const LedgerCard({super.key, required this.verdict});

  @override
  State<LedgerCard> createState() => _LedgerCardState();
}

enum _Kind { spam, possible, newsletter, clean }

class _LedgerCardState extends State<LedgerCard> {
  late bool _open;

  _Kind get _kind {
    final v = widget.verdict;
    if (v.label == Label.spam) return _Kind.spam;
    if (v.spamScore >= 0.6) return _Kind.possible;
    if (v.label == Label.newsletter) return _Kind.newsletter;
    return _Kind.clean;
  }

  @override
  void initState() {
    super.initState();
    _open = false;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.df.colors;
    final v = widget.verdict;
    final kind = _kind;
    final (Color tone, Color wash, String headline) = switch (kind) {
      _Kind.spam => (c.error.base, c.error.bg, UiStrings.ledgerSpam),
      _Kind.possible => (c.warning.deep, c.warning.bg, UiStrings.ledgerPossible),
      _Kind.newsletter => (c.accent.base, c.accent.container, UiStrings.ledgerNewsletter),
      _Kind.clean => (c.success.deep, c.success.bg, UiStrings.ledgerClean),
    };
    final pct = (v.spamScore * 100).round();
    final narrow = MediaQuery.sizeOf(context).width < 520;

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(context.df.shape.md),
        border: Border.all(color: tone.withValues(alpha: 0.28)),
        ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: EdgeInsets.fromLTRB(narrow ? 12 : 14, 9, 8, 9),
              child: Row(
                children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(color: tone, shape: BoxShape.circle)),
                  const SizedBox(width: 10),
                  Text('$pct%', style: AppType.mono(tone, size: 13, weight: FontWeight.w700)),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      narrow ? headline : '${UiStrings.ledgerScoreCaption} · $headline',
                      style: AppType.ui(c.textSecondary, size: 12.5, weight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: narrow ? 56 : 96,
                    child: _SignalBar(evidence: v.evidence, score: v.spamScore, spamTone: c.error.base, hamTone: c.accent.base, track: wash),
                  ),
                  const Spacer(),
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: context.df.motion.fast,
                    child: Icon(Icons.expand_more_rounded, size: 18, color: c.textTertiary),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: context.df.motion.normal,
            curve: context.df.motion.standard,
            alignment: Alignment.topCenter,
            child: _open
                ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Divider(height: 1, color: c.hairline),
                    for (var i = 0; i < v.evidence.length; i++) ...[
                      _Line(e: v.evidence[i], index: i, narrow: narrow),
                      if (i < v.evidence.length - 1) Divider(height: 1, indent: narrow ? 16 : 22, color: c.hairline),
                    ],
                    Container(
                      color: c.surfaceSunken,
                      padding: EdgeInsets.symmetric(horizontal: narrow ? 16 : 22, vertical: 10),
                      child: Text(UiStrings.ledgerFooter, style: AppType.mono(c.textTertiary, size: 10.5)),
                    ),
                  ])
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

/// A meter: the track is the full 0-100 range, the filled part is the spam score,
/// and the segments inside it show how much each signal contributed.
class _SignalBar extends StatelessWidget {
  final List<Evidence> evidence;
  final double score;
  final Color spamTone;
  final Color hamTone;
  final Color track;
  const _SignalBar({required this.evidence, required this.score, required this.spamTone, required this.hamTone, required this.track});

  @override
  Widget build(BuildContext context) {
    final items = evidence.where((e) => e.weight != 0).toList();
    final clamped = score.clamp(0.0, 1.0);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: context.df.motion.medium,
      curve: context.df.motion.standard,
      builder: (context, t, _) => LayoutBuilder(
        builder: (context, cons) {
          final fill = clamped == 0 ? 0.0 : (cons.maxWidth * clamped * t).clamp(6.0, cons.maxWidth);
          return ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 4,
              child: Stack(children: [
                Positioned.fill(child: ColoredBox(color: track)),
                if (items.isNotEmpty && fill > 0)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: fill,
                    child: Row(children: [
                      for (var i = 0; i < items.length; i++)
                        Expanded(
                          flex: (items[i].weight.abs() * 1000).round().clamp(1, 100000),
                          child: Container(
                            margin: EdgeInsets.only(right: i == items.length - 1 ? 0 : 1.5),
                            color: (items[i].weight >= 0 ? spamTone : hamTone).withValues(alpha: (0.95 - i * 0.16).clamp(0.35, 1.0)),
                          ),
                        ),
                    ]),
                  ),
              ]),
            ),
          );
        },
      ),
    );
  }
}

class _Line extends StatelessWidget {
  final Evidence e;
  final int index;
  final bool narrow;
  const _Line({required this.e, required this.index, required this.narrow});

  @override
  Widget build(BuildContext context) {
    final c = context.df.colors;
    final towardsSpam = e.weight >= 0;
    final tone = towardsSpam ? c.error.base : c.accent.base;
    final sign = towardsSpam ? '+' : '−';
    final label = Text(UiStrings.signalLabel(e.id), style: AppType.ui(c.textPrimary, size: 13, weight: FontWeight.w600));
    final detail = Text(e.detail, style: AppType.ui(c.textSecondary, size: 12.5, height: 1.4));
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: narrow ? 16 : 22, vertical: 11),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Container(width: 8, height: 8, decoration: BoxDecoration(color: tone, shape: BoxShape.circle)),
        ),
        const SizedBox(width: 12),
        if (narrow)
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [label, const SizedBox(height: 2), detail]))
        else ...[
          SizedBox(width: 176, child: label),
          Expanded(child: detail),
        ],
        const SizedBox(width: 12),
        Text('$sign${e.weight.abs().toStringAsFixed(2)}', style: AppType.mono(tone, size: 12, weight: FontWeight.w700)),
      ]),
    );
  }
}
