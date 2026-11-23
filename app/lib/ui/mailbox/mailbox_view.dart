import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:df_theme/df_theme.dart';
import 'package:spam_core/spam_core.dart';
import '../../app/strings.dart';
import '../../platform/platform_services.dart';
import '../../db/database.dart';
import '../../filter/verdict_controller.dart';
import '../../mail/sync_engine.dart';
import '../../app/ui_strings.dart';
import '../../theme/app_type.dart';
import '../common/app_parts.dart';
import '../common/mail_queries.dart';
import 'message_row.dart';

enum _ListFilter { all, inbox, newsletters, spam }

class MailboxView extends ConsumerStatefulWidget {
  final ValueChanged<String>? onSelectMessage;
  final VoidCallback? onCompose;

  const MailboxView({
    super.key,
    this.onSelectMessage,
    this.onCompose,
  });

  @override
  ConsumerState<MailboxView> createState() => _MailboxViewState();
}

class _MailboxViewState extends ConsumerState<MailboxView> {
  final FocusNode _focusNode = FocusNode();
  int _selectedIndex = 0;
  _ListFilter _filter = _ListFilter.all;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.df.colors;
    ref.watch(mailRevisionProvider); // rebuild when sync writes new mail
    final db0 = ref.watch(databaseProvider);
    final isComfortable = ref.watch(listDensityComfortableProvider);
    final selectedFolderId = effectiveFolderId(db0, ref.watch(selectedFolderIdProvider));
    final selectedMessageId = ref.watch(selectedMessageIdProvider);
    final db = ref.watch(databaseProvider);

    final query = selectedFolderId != null
        ? 'SELECT * FROM messages WHERE folder_id = ? ORDER BY date DESC'
        : 'SELECT * FROM messages ORDER BY date DESC';
    final params = selectedFolderId != null ? [selectedFolderId] : [];
    final rows = db.db.select(query, params);

    final allMessages = rows.map((r) => MessageSummary(
      id: r['id'] as String,
      sender: r['sender'] as String,
      senderDomain: r['sender_domain'] as String?,
      subject: r['subject'] as String,
      snippet: r['snippet'] as String,
      date: DateTime.parse(r['date'] as String),
      isRead: (r['is_read'] as int) == 1,
      isFlagged: (r['is_flagged'] as int) == 1,
      hasAttachments: (r['has_attachments'] as int) == 1,
      label: Label.values.byName((r['classification_label'] as String?) ?? 'inbox'),
      spamScore: (r['spam_score'] as num?)?.toDouble() ?? 0.0,
    )).toList();

    bool inFilter(MessageSummary m) => switch (_filter) {
          _ListFilter.all => true,
          _ListFilter.inbox => m.label == Label.inbox || m.label == Label.ham,
          _ListFilter.newsletters => m.label == Label.newsletter,
          _ListFilter.spam => m.label == Label.spam,
        };
    final messages = allMessages.where(inFilter).toList();
    final unreadTotal = allMessages.where((m) => !m.isRead).length;
    final folderName = selectedFolderId == null
        ? AppStrings.navMail
        : (db.db.select('SELECT name FROM folders WHERE id = ?', [selectedFolderId]).firstOrNull?['name'] as String? ?? AppStrings.navMail);
    final narrow = MediaQuery.sizeOf(context).width < 700;
    int countOf(_ListFilter f) => f == _ListFilter.all ? allMessages.length : allMessages.where((m) => switch (f) {
          _ListFilter.inbox => m.label == Label.inbox || m.label == Label.ham,
          _ListFilter.newsletters => m.label == Label.newsletter,
          _ => m.label == Label.spam,
        }).length;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (node, event) => _handleKeyEvent(event, messages),
      child: Scaffold(
        backgroundColor: palette.canvas,
        floatingActionButton: narrow && widget.onCompose != null
            ? FloatingActionButton.extended(
                onPressed: widget.onCompose,
                backgroundColor: palette.brand.deep,
                foregroundColor: palette.textOnBrand,
                elevation: 3,
                focusElevation: 3,
                focusColor: Colors.transparent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(context.df.shape.lg)),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: Text(UiStrings.compose, style: AppType.ui(palette.textOnBrand, size: 14, weight: FontWeight.w600)),
              )
            : null,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 20, 10, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(folderName, style: AppType.display(palette.textPrimary, size: 32, weight: 600, height: 1.0, letterSpacing: -0.8)),
                        const SizedBox(height: 6),
                        Text(
                          '${UiStrings.messageCount(allMessages.length)} · ${UiStrings.unreadCount(unreadTotal)}',
                          style: AppType.mono(palette.textTertiary, size: 11.5),
                        ),
                      ]),
                    ),
                    IconButton(
                      icon: Icon(isComfortable ? Icons.view_agenda_outlined : Icons.table_rows_outlined, size: 20, color: palette.textSecondary),
                      tooltip: AppStrings.settingsDensity,
                      onPressed: () => ref.read(listDensityComfortableProvider.notifier).toggle(),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  for (final f in _ListFilter.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _FilterChip(
                        label: switch (f) {
                          _ListFilter.all => UiStrings.filterAll,
                          _ListFilter.inbox => UiStrings.filterInbox,
                          _ListFilter.newsletters => UiStrings.filterNewsletters,
                          _ListFilter.spam => UiStrings.filterSpam,
                        },
                        count: countOf(f),
                        selected: _filter == f,
                        onTap: () => setState(() {
                          _filter = f;
                          _selectedIndex = 0;
                        }),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Divider(height: 1, color: palette.hairline),
            Expanded(
              child: messages.isEmpty
                  ? LedgerPaper(
                      child: Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Text(UiStrings.emptyListTitle, style: AppType.display(palette.textTertiary, size: 30, weight: 500, italic: true)),
                          const SizedBox(height: 6),
                          Text(UiStrings.emptyListBody, style: AppType.ui(palette.textTertiary, size: 13)),
                        ]),
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.only(bottom: narrow ? 88 : 24),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final msg = messages[index];
                        return MessageRow(
                          message: msg,
                          isSelected: msg.id == selectedMessageId,
                          isComfortable: isComfortable,
                          onTap: () {
                            setState(() => _selectedIndex = index);
                            ref.read(selectedMessageIdProvider.notifier).set(msg.id);
                            widget.onSelectMessage?.call(msg.id);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  KeyEventResult _handleKeyEvent(KeyEvent event, List<MessageSummary> messages) {
    if (event is! KeyDownEvent || messages.isEmpty) {
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.keyJ) {
      // Move down
      setState(() {
        _selectedIndex = (_selectedIndex + 1).clamp(0, messages.length - 1);
      });
      _selectCurrent(messages);
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.keyK) {
      // Move up
      setState(() {
        _selectedIndex = (_selectedIndex - 1).clamp(0, messages.length - 1);
      });
      _selectCurrent(messages);
      return KeyEventResult.handled;
    } else if (event.character == '!') {
      // Mark Spam
      _applyLabel(messages, Label.spam);
      return KeyEventResult.handled;
    } else if (event.character == 'n') {
      // Mark Newsletter
      _applyLabel(messages, Label.newsletter);
      return KeyEventResult.handled;
    } else if (event.character == 'i') {
      // Move to Inbox
      _applyLabel(messages, Label.inbox);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _selectCurrent(List<MessageSummary> messages) {
    if (_selectedIndex >= 0 && _selectedIndex < messages.length) {
      final msg = messages[_selectedIndex];
      ref.read(selectedMessageIdProvider.notifier).set(msg.id);
      widget.onSelectMessage?.call(msg.id);
    }
  }

  void _applyLabel(List<MessageSummary> messages, Label label) {
    if (_selectedIndex >= 0 && _selectedIndex < messages.length) {
      final msg = messages[_selectedIndex];
      ref.read(verdictControllerProvider).applyVerdict(
        messageId: msg.id,
        newLabel: label,
      );
    }
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({required this.label, required this.count, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.df.colors;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: context.df.motion.fast,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? c.textPrimary : Colors.transparent,
          borderRadius: BorderRadius.circular(context.df.shape.pill),
          border: Border.all(color: selected ? c.textPrimary : c.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: AppType.ui(selected ? c.canvas : c.textSecondary, size: 13, weight: FontWeight.w600)),
          const SizedBox(width: 6),
          Text('$count', style: AppType.mono(selected ? c.canvas.withValues(alpha: 0.7) : c.textTertiary, size: 11, weight: FontWeight.w600)),
        ]),
      ),
    );
  }
}
