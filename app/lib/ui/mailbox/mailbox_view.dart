import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:df_theme/df_theme.dart';
import 'package:spam_core/spam_core.dart';
import '../../app/strings.dart';
import '../../platform/platform_services.dart';
import '../../db/database.dart';
import '../../filter/screener.dart';
import '../../filter/verdict_controller.dart';
import '../../mail/sync_engine.dart';
import '../../app/log.dart';
import '../../app/ui_strings.dart';
import '../../theme/app_type.dart';
import '../common/app_parts.dart';
import '../common/mail_queries.dart';
import 'message_row.dart';

enum _ListFilter { all, inbox, newsletters, spam, review, newSenders }

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

  // The list loads a page at a time. Reaching the end of what is stored
  // reveals the next page; past the last stored message, older mail is
  // fetched from the server.
  static const _pageSize = SyncEngine.olderPageSize;
  int _limit = _pageSize;
  String? _pagedFolderId;
  bool _loadingOlder = false;
  bool _olderFailed = false;
  final _exhausted = <String>{}; // folders whose server has nothing older

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

    if (_pagedFolderId != selectedFolderId) {
      _pagedFolderId = selectedFolderId;
      _limit = _pageSize;
    }
    final folderWhere = selectedFolderId != null ? 'folder_id = ?' : '1 = 1';
    final folderParams = <Object?>[?selectedFolderId];

    // Header and chip counts are counted in SQL: the list below only loads a
    // page at a time, so it cannot be counted from.
    final counts = {for (final f in _ListFilter.values) f: 0};
    var unreadTotal = 0;
    for (final r in db.db.select(
      "SELECT COALESCE(classification_label, 'inbox') AS l, COUNT(*) AS n, "
      'SUM(CASE WHEN is_read = 0 THEN 1 ELSE 0 END) AS u FROM messages WHERE $folderWhere GROUP BY l',
      folderParams,
    )) {
      final n = r['n'] as int;
      counts[_ListFilter.all] = counts[_ListFilter.all]! + n;
      unreadTotal += (r['u'] as int?) ?? 0;
      final f = switch (r['l'] as String) {
        'newsletter' => _ListFilter.newsletters,
        'spam' => _ListFilter.spam,
        _ => _ListFilter.inbox,
      };
      counts[f] = counts[f]! + n;
    }

    final screener = ref.watch(screenerProvider);
    final screenerMode = ref.watch(screenerModeProvider);
    final newSenderWhere = screener.newSenderWhereClause(tableAlias: 'messages');

    // Review count: classification_label = 'spam' AND spam_score < 0.9 in non-Junk folder, not user-overridden
    const reviewWhereSql =
        "classification_label = 'spam' AND spam_score < 0.9 "
        "AND folder_id NOT IN (SELECT id FROM folders WHERE LOWER(COALESCE(special_use, '')) = 'junk') "
        "AND NOT EXISTS (SELECT 1 FROM classifications c WHERE c.message_id = messages.id AND c.user_overridden = 1)";
    final reviewRows = db.db.select(
      'SELECT COUNT(*) AS n FROM messages WHERE $folderWhere AND $reviewWhereSql',
      folderParams,
    );
    counts[_ListFilter.review] = (reviewRows.firstOrNull?['n'] as int?) ?? 0;

    // New senders count
    final newSenderRows = db.db.select(
      'SELECT COUNT(*) AS n FROM messages WHERE $folderWhere AND ${newSenderWhere.sql}',
      [...folderParams, ...newSenderWhere.args],
    );
    counts[_ListFilter.newSenders] = (newSenderRows.firstOrNull?['n'] as int?) ?? 0;

    if (screenerMode == 'strict') {
      final strictInboxRows = db.db.select(
        "SELECT COUNT(*) AS n FROM messages WHERE $folderWhere "
        "AND COALESCE(classification_label, 'inbox') IN ('inbox', 'ham') "
        "AND NOT (${newSenderWhere.sql})",
        [...folderParams, ...newSenderWhere.args],
      );
      counts[_ListFilter.inbox] = (strictInboxRows.firstOrNull?['n'] as int?) ?? 0;
    }

    final matching = counts[_filter]!;

    final labelWhere = switch (_filter) {
      _ListFilter.all => '',
      _ListFilter.inbox => screenerMode == 'strict'
          ? " AND COALESCE(classification_label, 'inbox') IN ('inbox', 'ham') AND NOT (${newSenderWhere.sql})"
          : " AND COALESCE(classification_label, 'inbox') IN ('inbox', 'ham')",
      _ListFilter.newsletters => " AND classification_label = 'newsletter'",
      _ListFilter.spam => " AND classification_label = 'spam'",
      _ListFilter.review => " AND $reviewWhereSql",
      _ListFilter.newSenders => " AND ${newSenderWhere.sql}",
    };
    final extraArgs = switch (_filter) {
      _ListFilter.inbox when screenerMode == 'strict' => newSenderWhere.args,
      _ListFilter.newSenders => newSenderWhere.args,
      _ => const <Object?>[],
    };
    final rows = db.db.select(
      'SELECT * FROM messages WHERE $folderWhere$labelWhere ORDER BY date DESC LIMIT ?',
      [...folderParams, ...extraArgs, _limit],
    );

    final messages = rows.map((r) => MessageSummary(
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

    final folderRow = selectedFolderId == null
        ? null
        : db.db.select('SELECT name, special_use FROM folders WHERE id = ?', [selectedFolderId]).firstOrNull;
    final folderName = (folderRow?['name'] as String?) ?? AppStrings.navMail;
    final hasMoreLocal = matching > messages.length;
    final canLoadFromServer = selectedFolderId != null &&
        SyncEngine.pagesOlder(folderRow?['special_use'] as String?) &&
        !_exhausted.contains(selectedFolderId);
    final showFooter = hasMoreLocal || canLoadFromServer;
    final limitAtBuild = _limit;
    void loadMore() => _loadMore(selectedFolderId, limitAtBuild, hasMoreLocal: hasMoreLocal, canLoadFromServer: canLoadFromServer);
    final narrow = MediaQuery.sizeOf(context).width < 700;

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
                          '${UiStrings.messageCount(counts[_ListFilter.all]!)} · ${UiStrings.unreadCount(unreadTotal)}',
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
                          _ListFilter.review => UiStrings.filterReview,
                          _ListFilter.newSenders => UiStrings.filterNewSenders,
                        },
                        count: counts[f]!,
                        selected: _filter == f,
                        onTap: () => setState(() {
                          _filter = f;
                          _selectedIndex = 0;
                          _limit = _pageSize;
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
                          Text(
                            switch (_filter) {
                              _ListFilter.review => UiStrings.reviewEmpty,
                              _ListFilter.newSenders => UiStrings.newSendersEmpty,
                              _ => UiStrings.emptyListTitle,
                            },
                            style: AppType.display(palette.textTertiary, size: 28, weight: 500, italic: true),
                            textAlign: TextAlign.center,
                          ),
                          if (_filter != _ListFilter.review && _filter != _ListFilter.newSenders) ...[
                            const SizedBox(height: 6),
                            Text(UiStrings.emptyListBody, style: AppType.ui(palette.textTertiary, size: 13)),
                          ],
                        ]),
                      ),
                    )
                  : NotificationListener<ScrollNotification>(
                      onNotification: (n) {
                        if (showFooter && n.metrics.extentAfter < 400) loadMore();
                        return false;
                      },
                      child: ListView.builder(
                        padding: EdgeInsets.only(bottom: narrow ? 88 : 24),
                        itemCount: messages.length + (showFooter ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == messages.length) {
                            return _LoadMoreFooter(
                              loading: _loadingOlder,
                              failed: _olderFailed,
                              onTap: loadMore,
                            );
                          }
                          final msg = messages[index];
                          final isReview = _filter == _ListFilter.review;
                          return MessageRow(
                            message: msg,
                            isSelected: msg.id == selectedMessageId,
                            isComfortable: isComfortable,
                            onMarkSpam: isReview
                                ? () => ref.read(verdictControllerProvider).applyVerdict(
                                      messageId: msg.id,
                                      newLabel: Label.spam,
                                    )
                                : null,
                            onMarkNotSpam: isReview
                                ? () => ref.read(verdictControllerProvider).applyVerdict(
                                      messageId: msg.id,
                                      newLabel: Label.ham,
                                    )
                                : null,
                            onTap: () {
                              setState(() => _selectedIndex = index);
                              ref.read(selectedMessageIdProvider.notifier).set(msg.id);
                              widget.onSelectMessage?.call(msg.id);
                            },
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Shows the next page. Mail already stored is revealed first; once all of
  /// it is shown, the next page of older mail is fetched from the server.
  Future<void> _loadMore(String? folderId, int limitAtBuild, {required bool hasMoreLocal, required bool canLoadFromServer}) async {
    if (_loadingOlder) return;
    if (hasMoreLocal) {
      // Relative to the limit this build showed: several scroll events can
      // arrive before the rebuild, and all must ask for the same page.
      if (_limit == limitAtBuild) setState(() => _limit = limitAtBuild + _pageSize);
      return;
    }
    if (folderId == null || !canLoadFromServer) return;
    setState(() {
      _loadingOlder = true;
      _olderFailed = false;
    });
    try {
      final n = await ref.read(syncEngineProvider).loadOlder(folderId);
      if (n == 0) {
        _exhausted.add(folderId);
      } else {
        _limit += _pageSize;
      }
    } catch (e, st) {
      logError('load older mail', e, st);
      _olderFailed = true;
    } finally {
      if (mounted) setState(() => _loadingOlder = false);
    }
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

class _LoadMoreFooter extends StatelessWidget {
  final bool loading;
  final bool failed;
  final VoidCallback onTap;
  const _LoadMoreFooter({required this.loading, required this.failed, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.df.colors;
    final label = loading
        ? UiStrings.loadingOlder
        : failed
            ? UiStrings.loadOlderFailed
            : UiStrings.loadOlder;
    return InkWell(
      onTap: loading ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (loading) ...[
            SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: c.textTertiary)),
            const SizedBox(width: 10),
          ],
          Text(label, style: AppType.mono(failed ? c.error.base : c.textTertiary, size: 11.5)),
        ]),
      ),
    );
  }
}
