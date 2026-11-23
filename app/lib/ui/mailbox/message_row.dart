import 'package:material_ui/material_ui.dart';
import 'package:df_theme/df_theme.dart';
import 'package:spam_core/spam_core.dart';
import '../../theme/app_type.dart';
import '../common/app_parts.dart';
import '../common/formats.dart';

class MessageSummary {
  final String id;
  final String sender;
  final String? senderDomain;
  final String subject;
  final String snippet;
  final DateTime date;
  final bool isRead;
  final bool isFlagged;
  final bool hasAttachments;
  final Label label;
  final double spamScore;

  const MessageSummary({
    required this.id,
    required this.sender,
    this.senderDomain,
    required this.subject,
    required this.snippet,
    required this.date,
    required this.isRead,
    this.isFlagged = false,
    this.hasAttachments = false,
    required this.label,
    required this.spamScore,
  });
}

class MessageRow extends StatefulWidget {
  final MessageSummary message;
  final bool isSelected;
  final bool isComfortable;
  final VoidCallback onTap;

  const MessageRow({
    super.key,
    required this.message,
    required this.isSelected,
    required this.isComfortable,
    required this.onTap,
  });

  @override
  State<MessageRow> createState() => _MessageRowState();
}

class _MessageRowState extends State<MessageRow> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final c = context.df.colors;
    final m = widget.message;
    final who = parseSender(m.sender);
    final unread = !m.isRead;
    final comfortable = widget.isComfortable;
    final isSpam = m.label == Label.spam;

    final Color bg = widget.isSelected
        ? c.surface
        : _isHovered
            ? c.surfaceSunken.withValues(alpha: 0.7)
            : isSpam
                ? c.error.bg.withValues(alpha: 0.28)
                : Colors.transparent;

    final avatar = Stack(
      clipBehavior: Clip.none,
      children: [
        Monogram(name: who.name, seed: who.email, size: comfortable ? 42 : 32),
        if (unread)
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: c.brand.base,
                shape: BoxShape.circle,
                border: Border.all(color: c.canvas, width: 2),
              ),
            ),
          ),
      ],
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: Semantics(
        label: '${unread ? "Unread " : ""}from ${who.name}, ${m.subject}, classified as ${m.label.name}',
        selected: widget.isSelected,
        button: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: context.df.motion.fast,
            curve: context.df.motion.standard,
            decoration: BoxDecoration(
              color: bg,
              border: Border(
                left: BorderSide(color: widget.isSelected ? c.brand.base : Colors.transparent, width: 3),
                bottom: BorderSide(color: c.hairline.withValues(alpha: 0.7)),
              ),
            ),
            padding: EdgeInsets.fromLTRB(13, comfortable ? 14 : 9, 16, comfortable ? 14 : 9),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                avatar,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                          child: Text(
                            who.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.ui(c.textPrimary, size: 14.5, weight: unread ? FontWeight.w700 : FontWeight.w500),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(formatListDate(m.date), style: AppType.mono(unread ? c.brand.deep : c.textTertiary, size: 11, weight: unread ? FontWeight.w700 : FontWeight.w500)),
                      ]),
                      const SizedBox(height: 2),
                      Row(children: [
                        Expanded(
                          child: Text(
                            m.subject,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.ui(unread ? c.textPrimary : c.textSecondary, size: 13.5, weight: unread ? FontWeight.w600 : FontWeight.w400),
                          ),
                        ),
                        if (m.hasAttachments) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.attach_file_rounded, size: 15, color: c.textTertiary),
                        ],
                        if (m.isFlagged) ...[
                          const SizedBox(width: 4),
                          Icon(Icons.flag_rounded, size: 15, color: c.brand.base),
                        ],
                      ]),
                      if (comfortable) ...[
                        const SizedBox(height: 5),
                        Row(children: [
                          if (ClassPill.shows(m.label, m.spamScore)) ...[
                            ClassPill(label: m.label, spamScore: m.spamScore),
                            const SizedBox(width: 8),
                          ],
                          Expanded(
                            child: Text(
                              m.snippet.replaceAll(RegExp(r'\s+'), ' '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppType.ui(c.textTertiary, size: 12.5),
                            ),
                          ),
                        ]),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
