import 'package:df_theme/df_theme.dart';
import 'package:material_ui/material_ui.dart';
import 'package:spam_core/spam_core.dart';

import '../../app/ui_strings.dart';
import '../../theme/app_type.dart';
import 'formats.dart';

/// Round avatar with initials. Tint is derived from a seed so a sender is always the
/// same colour, drawn only from palette roles (no hardcoded hues).
class Monogram extends StatelessWidget {
  final String name;
  final String seed;
  final double size;

  const Monogram({super.key, required this.name, required this.seed, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final c = context.df.colors;
    final tints = <(Color, Color)>[
      (c.brand.container, c.brand.onContainer),
      (c.accent.container, c.accent.onContainer),
      (c.warning.bg, c.warning.deep),
      (c.success.bg, c.success.deep),
      (c.surfaceSunken, c.textSecondary),
    ];
    final (bg, fg) = tints[seed.hashCode.abs() % tints.length];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: bg,
        border: Border.all(color: fg.withValues(alpha: 0.12)),
      ),
      child: Text(
        initialsOf(name),
        style: AppType.display(fg, size: size * 0.4, weight: 600, letterSpacing: 0, height: 1),
      ),
    );
  }
}

/// Classification pill. Never colour alone: icon + word.
/// Plain inbox mail gets no pill at all (silence is the default).
class ClassPill extends StatelessWidget {
  final Label label;
  final double spamScore;

  const ClassPill({super.key, required this.label, required this.spamScore});

  static bool shows(Label label, double score) =>
      label == Label.spam || label == Label.newsletter || score >= 0.6;

  @override
  Widget build(BuildContext context) {
    if (!shows(label, spamScore)) return const SizedBox.shrink();
    final c = context.df.colors;
    final (Color bg, Color fg, IconData icon, String text) = switch (label) {
      Label.spam => (c.error.bg, c.error.deep, Icons.block_rounded, UiStrings.pillSpam),
      Label.newsletter => (c.accent.container, c.accent.onContainer, Icons.auto_stories_outlined, UiStrings.pillNewsletter),
      _ => (c.warning.bg, c.warning.deep, Icons.help_outline_rounded, UiStrings.pillPossible),
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 2, 8, 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(context.df.shape.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(text, style: AppType.ui(fg, size: 11, weight: FontWeight.w600, height: 1.2, letterSpacing: 0.1)),
        ],
      ),
    );
  }
}

/// Small keyboard hint, e.g. [J] [K].
class KeyCap extends StatelessWidget {
  final String keys;
  const KeyCap(this.keys, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.df.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.surfaceSunken,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: c.border),
        boxShadow: [BoxShadow(color: c.border.withValues(alpha: 0.7), offset: const Offset(0, 1))],
      ),
      child: Text(keys, style: AppType.mono(c.textSecondary, size: 11, weight: FontWeight.w600)),
    );
  }
}

/// Section eyebrow used in the sidebar and settings.
class Eyebrow extends StatelessWidget {
  final String text;
  const Eyebrow(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: AppType.mono(context.df.colors.textTertiary, size: 10.5, weight: FontWeight.w600, letterSpacing: 1.4),
      );
}

/// Faint ruled-paper background: horizontal hairlines with an optional brass margin
/// rule. Fills the space it is given. [offset] is the y of the first rule, so text
/// can be made to sit on the lines; [opacity] fades the ruling.
class LedgerPaper extends StatelessWidget {
  final Widget child;
  final double lineGap;
  final double? offset;
  final double opacity;
  final bool margin;

  const LedgerPaper({super.key, required this.child, this.lineGap = 32, this.offset, this.opacity = 1, this.margin = false});

  @override
  Widget build(BuildContext context) {
    final c = context.df.colors;
    return SizedBox.expand(
      child: CustomPaint(
        painter: _PaperPainter(
          c.hairline.withValues(alpha: 0.55 * opacity),
          c.brand.soft.withValues(alpha: 0.45),
          lineGap,
          offset ?? lineGap,
          margin,
        ),
        child: child,
      ),
    );
  }
}

class _PaperPainter extends CustomPainter {
  final Color line;
  final Color rule;
  final double gap;
  final double offset;
  final bool margin;
  _PaperPainter(this.line, this.rule, this.gap, this.offset, this.margin);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = line
      ..strokeWidth = 1;
    for (double y = offset; y < size.height; y += gap) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
    if (margin) {
      final r = Paint()
        ..color = rule
        ..strokeWidth = 1.5;
      canvas.drawLine(const Offset(56, 0), Offset(56, size.height), r);
    }
  }

  @override
  bool shouldRepaint(_PaperPainter old) =>
      old.line != line || old.rule != rule || old.gap != gap || old.offset != offset || old.margin != margin;
}
