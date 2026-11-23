import 'dart:async';
import 'dart:math' as math;
import 'package:df_theme/df_theme.dart';
import 'package:material_ui/material_ui.dart';
import '../../app/ui_strings.dart';
import '../../filter/protection_stats.dart';
import '../../theme/app_type.dart';
import '../common/mail_queries.dart';

/// The four-stage replay: no filter, our app, app + community, Pro.
class ProtectionStory extends StatefulWidget {
  final ProtectionStats stats;

  /// Pro stage content (device comparison + upsell), supplied by the screen.
  final Widget proPanel;

  const ProtectionStory({super.key, required this.stats, required this.proPanel});

  @override
  State<ProtectionStory> createState() => _ProtectionStoryState();
}

enum _Square { inbox, filter, community }

class _ProtectionStoryState extends State<ProtectionStory> with SingleTickerProviderStateMixin {
  static const _maxSquares = 48;
  static const _autoplayStep = Duration(milliseconds: 3200);

  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));
  Timer? _autoplay;
  var _from = 0;
  var _stage = 0;
  var _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.disableAnimationsOf(context);
    if (reduce != _reduceMotion || _autoplay == null && _anim.status == AnimationStatus.dismissed) {
      _reduceMotion = reduce;
      _restart();
    }
  }

  @override
  void dispose() {
    _autoplay?.cancel();
    _anim.dispose();
    super.dispose();
  }

  void _restart() {
    _autoplay?.cancel();
    _from = 0;
    _stage = 0;
    if (_reduceMotion) {
      _stage = 2;
      _from = 2;
      _anim.value = 1;
      return;
    }
    _anim.value = 1;
    _autoplay = Timer(const Duration(milliseconds: 900), () => _go(1, auto: true));
  }

  void _go(int stage, {bool auto = false}) {
    if (!mounted) return;
    _autoplay?.cancel();
    setState(() {
      _from = _stage;
      _stage = stage;
    });
    if (_reduceMotion) {
      _anim.value = 1;
    } else {
      _anim.forward(from: 0);
    }
    if (auto && stage < 3) _autoplay = Timer(_autoplayStep, () => _go(stage + 1, auto: true));
  }

  /// Squares standing in for the spam, proportional to the real split.
  List<_Square> _squares(ProtectionStats s) {
    final n = math.min(s.total, _maxSquares);
    if (n == 0) return const [];
    var cN = (s.communityOnly * n / s.total).round();
    if (s.communityOnly > 0 && cN == 0) cN = 1;
    var fN = (s.filterCaught * n / s.total).round();
    if (fN + cN > n) fN = n - cN;
    return [
      for (var i = 0; i < n; i++)
        i < fN ? _Square.filter : (i < fN + cN ? _Square.community : _Square.inbox),
    ];
  }

  /// What square [target] looks like once [stage] is reached.
  _Square _at(int stage, _Square target) => switch (stage) {
        0 => _Square.inbox,
        1 => target == _Square.filter ? _Square.filter : _Square.inbox,
        _ => target,
      };

  int _reach(int stage) => switch (stage) {
        0 => widget.stats.reachInboxNoFilter,
        1 => widget.stats.reachInboxFilter,
        _ => widget.stats.reachInboxCommunity,
      };

  @override
  Widget build(BuildContext context) {
    final c = context.df.colors;
    final s = widget.stats;
    final squares = _squares(s);
    final shownStage = math.min(_stage, 2);
    final fromStage = math.min(_from, 2);
    final k = s.total > _maxSquares ? (s.total / _maxSquares).ceil() : 1;

    Color colorOf(_Square q) => switch (q) {
          _Square.inbox => c.error.base,
          _Square.filter => c.success.base,
          _Square.community => c.accent.base,
        };

    final stages = [UiStrings.stageNoFilter, UiStrings.stageFilter, UiStrings.stageCommunity, UiStrings.stagePro];
    final body = switch (_stage) {
      0 => UiStrings.storyNoFilterBody,
      1 => UiStrings.storyFilterBody(s.filterCaught),
      2 => UiStrings.storyCommunityBody(s.communityOnly),
      _ => UiStrings.storyProBody,
    };

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (var i = 0; i < stages.length; i++)
          ChoiceChip(
            label: Text(stages[i], style: AppType.ui(_stage == i ? c.textOnBrand : c.textPrimary, size: 13, weight: FontWeight.w600)),
            selected: _stage == i,
            showCheckmark: false,
            selectedColor: c.brand.deep,
            onSelected: (_) => _go(i),
          ),
      ]),
      const SizedBox(height: 22),
      AnimatedBuilder(
        animation: _anim,
        builder: (context, _) {
          final t = Curves.easeOutCubic.transform(_anim.value);
          final reach = (_reach(fromStage) + (_reach(shownStage) - _reach(fromStage)) * t).round();
          return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(groupThousands(reach), style: AppType.display(reach == 0 ? c.success.deep : c.error.base, size: 64, weight: 600, height: 1, letterSpacing: -2)),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(UiStrings.storyReachInbox, style: AppType.mono(c.textTertiary, size: 11.5, weight: FontWeight.w600, letterSpacing: 0.4)),
              ),
            ),
          ]);
        },
      ),
      const SizedBox(height: 18),
      if (_stage < 3) ...[
        AnimatedBuilder(
          animation: _anim,
          builder: (context, _) => Wrap(spacing: 6, runSpacing: 6, children: [
            for (var i = 0; i < squares.length; i++)
              _SquareTile(
                color: Color.lerp(
                  colorOf(_at(fromStage, squares[i])),
                  colorOf(_at(shownStage, squares[i])),
                  // Stagger so the stage change sweeps across the grid.
                  ((_anim.value * (squares.length + 8) - i) / 8).clamp(0.0, 1.0),
                )!,
                caught: _at(shownStage, squares[i]) != _Square.inbox,
              ),
          ]),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 18, runSpacing: 6, children: [
          _Legend(color: c.error.base, label: UiStrings.storyLegendInbox),
          if (_stage >= 1) _Legend(color: c.success.base, label: UiStrings.storyLegendFilter),
          if (_stage >= 2) _Legend(color: c.accent.base, label: UiStrings.storyLegendCommunity),
        ]),
        if (k > 1) Padding(padding: const EdgeInsets.only(top: 6), child: Text(UiStrings.storySquareScale(k), style: AppType.ui(c.textTertiary, size: 12))),
      ] else
        widget.proPanel,
      const SizedBox(height: 18),
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: Text(body, key: ValueKey(_stage), style: AppType.ui(c.textSecondary, size: 15, height: 1.45)),
      ),
      const SizedBox(height: 14),
      Row(children: [
        TextButton.icon(
          onPressed: _restart,
          icon: const Icon(Icons.replay_rounded, size: 18),
          label: Text(UiStrings.storyReplay),
        ),
      ]),
      Text(UiStrings.storyBasis, style: AppType.ui(c.textTertiary, size: 12, height: 1.4)),
    ]);
  }
}

class _SquareTile extends StatelessWidget {
  final Color color;
  final bool caught;
  const _SquareTile({required this.color, required this.caught});

  @override
  Widget build(BuildContext context) => Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(5)),
        child: caught ? Icon(Icons.check_rounded, size: 14, color: context.df.colors.textOnBrand) : null,
      );
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 6),
        Text(label, style: AppType.ui(context.df.colors.textSecondary, size: 12.5)),
      ]);
}
