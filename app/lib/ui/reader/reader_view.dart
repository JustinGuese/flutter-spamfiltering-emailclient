import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:df_theme/df_theme.dart';
import 'package:spam_core/spam_core.dart';
import '../../db/database.dart';
import '../../mail/html_to_text.dart';
import '../../app/strings.dart';
import '../../filter/filter_service.dart';
import '../../filter/verdict_controller.dart';
import '../../platform/platform_services.dart';
import '../filter/verdict_bar.dart';
import '../filter/stamp.dart';
import '../../app/ui_strings.dart';
import '../../theme/app_type.dart';
import '../common/app_parts.dart';
import '../common/formats.dart';
import '../filter/ledger_card.dart';
import '../filter/sharing_notice.dart';
import '../settings/sharing_tile.dart';

class ReaderView extends ConsumerStatefulWidget {
  final String? messageId;
  final VoidCallback? onReply;

  const ReaderView({
    super.key,
    required this.messageId,
    this.onReply,
  });

  @override
  ConsumerState<ReaderView> createState() => _ReaderViewState();
}

class _ReaderViewState extends ConsumerState<ReaderView> {
  Label? _stampLabel;
  int _stampCount = 0;

  @override
  Widget build(BuildContext context) {
    final palette = context.df.colors;
    final id = widget.messageId;

    if (id == null) return const _EmptyReader();

    final db = ref.watch(databaseProvider);
    final row = db.db.select('''
      SELECT m.*, b.text_body, b.html_body, b.sanitized_html, b.remote_images_blocked
      FROM messages m
      LEFT JOIN bodies b ON m.id = b.message_id
      WHERE m.id = ?
    ''', [id]).firstOrNull;

    if (row == null) return const SizedBox.shrink();

    final subject = row['subject'] as String;
    final sender = row['sender'] as String;
    final date = DateTime.parse(row['date'] as String);
    final currentLabel = Label.values.byName((row['classification_label'] as String?) ?? 'inbox');
    final spamScore = (row['spam_score'] as num?)?.toDouble() ?? 0.0;
    var bodyText = ((row['text_body'] as String?) ?? '').trim();
    if (bodyText.isEmpty) {
      final html = row['html_body'] as String?;
      if (html != null && html.isNotEmpty) bodyText = htmlToText(html);
    }
    if (bodyText.isEmpty) bodyText = UiStrings.emptyBody;

    final showSharingNotice = ref.watch(sharingNoticeVisibleProvider);

    final filterService = ref.watch(filterServiceProvider);
    final storedVerdict = filterService.getStoredVerdict(id);

    final who = parseSender(sender);
    final verdict = storedVerdict ??
        (spamScore > 0
            ? Verdict(
                label: currentLabel,
                spamScore: spamScore,
                evidence: [Evidence(id: 'score', weight: spamScore, detail: 'Overall classification')],
              )
            : null);
    final narrow = MediaQuery.sizeOf(context).width < 700;
    final hPad = narrow ? 20.0 : 40.0;

    return Scaffold(
      backgroundColor: palette.canvas,
      body: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 64,
                padding: EdgeInsets.symmetric(horizontal: narrow ? 6 : 20),
                decoration: BoxDecoration(
                  color: palette.canvas,
                  border: Border(bottom: BorderSide(color: palette.hairline)),
                ),
                child: Row(
                  children: [
                    if (narrow)
                      IconButton(
                        icon: const Icon(Icons.arrow_back_rounded),
                        onPressed: () => ref.read(selectedMessageIdProvider.notifier).set(null),
                      ),
                    const Spacer(),
                    VerdictBar(
                      messageId: id,
                      currentLabel: currentLabel,
                      onVerdictChanged: (newLabel, similar) {
                        setState(() {
                          _stampLabel = newLabel;
                          _stampCount = similar;
                        });
                      },
                    ),
                  ],
                ),
              ),
              if (showSharingNotice)
                SharingNoticeBanner(
                  onDismiss: () {
                    db.db.execute("INSERT OR REPLACE INTO settings (key, value) VALUES ('sharing_notice_seen', 'true')");
                    ref.read(sharingNoticeVisibleProvider.notifier).hide();
                  },
                  onTurnOff: () {
                    db.db.execute("INSERT OR REPLACE INTO settings (key, value) VALUES ('sharing_notice_seen', 'true')");
                    ref.read(communitySharingEnabledProvider.notifier).toggle(false);
                    ref.read(sharingNoticeVisibleProvider.notifier).hide();
                  },
                  onLearnMore: () => _showLearnMoreDialog(context),
                ),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(hPad, narrow ? 24 : 36, hPad, 56),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            subject,
                            style: AppType.display(palette.textPrimary, size: narrow ? 28 : 36, weight: 600, height: 1.08, letterSpacing: -0.9),
                          ),
                          SizedBox(height: narrow ? 18 : 24),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Monogram(name: who.name, seed: who.email, size: 46),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(who.name, style: AppType.ui(palette.textPrimary, size: 15.5, weight: FontWeight.w700)),
                                    const SizedBox(height: 2),
                                    Text(who.email, style: AppType.mono(palette.textTertiary, size: 11.5), overflow: TextOverflow.ellipsis),
                                  ],
                                ),
                              ),
                              if (!narrow) ...[
                                const SizedBox(width: 12),
                                Text(formatFullDate(date), style: AppType.mono(palette.textTertiary, size: 11.5)),
                              ],
                            ],
                          ),
                          const SizedBox(height: 10),
                          Padding(
                            padding: EdgeInsets.only(left: narrow ? 0 : 60),
                            child: Text(
                              '${narrow ? "${formatFullDate(date)}\n" : ""}${UiStrings.toMe} · ${row['recipient_addrs']}',
                              style: AppType.mono(palette.textTertiary, size: 11, ).copyWith(height: 1.6),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 2,
                            ),
                          ),
                          if (verdict != null) ...[
                            const SizedBox(height: 20),
                            LedgerCard(key: ValueKey(id), verdict: verdict),
                          ],
                          SizedBox(height: narrow ? 20 : 24),
                          Divider(height: 1, color: palette.hairline),
                          SizedBox(height: narrow ? 24 : 32),
                          SelectableText(
                            bodyText,
                            style: AppType.ui(palette.textPrimary.withValues(alpha: 0.94), size: 16.5, height: 1.72),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_stampLabel != null)
            Positioned(
              top: 90,
              right: 40,
              child: LedgerStamp(
                label: _stampLabel!,
                similarCount: _stampCount,
                onComplete: () => setState(() => _stampLabel = null),
              ),
            ),
        ],
      ),
    );
  }
  void _showLearnMoreDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(AppStrings.sharingNoticeLearnMoreTitle),
        content: const Text(AppStrings.sharingNoticeLearnMoreBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(AppStrings.sharingNoticeDismiss),
          ),
        ],
      ),
    );
  }
}

class _EmptyReader extends StatelessWidget {
  const _EmptyReader();

  @override
  Widget build(BuildContext context) {
    final c = context.df.colors;
    Widget key(String keys, String what) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(width: 64, child: Align(alignment: Alignment.centerLeft, child: KeyCap(keys))),
            Text(what, style: AppType.ui(c.textSecondary, size: 13.5)),
          ]),
        );
    return Scaffold(
      backgroundColor: c.canvas,
      body: LedgerPaper(
        margin: true,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(UiStrings.emptyReaderTitle, style: AppType.display(c.textPrimary.withValues(alpha: 0.85), size: 56, weight: 400, italic: true, letterSpacing: -1.5)),
                const SizedBox(height: 10),
                Text(UiStrings.emptyReaderBody, style: AppType.ui(c.textTertiary, size: 15)),
                const SizedBox(height: 28),
                key('J  K', UiStrings.keyNext),
                key('!', UiStrings.keySpam),
                key('N', UiStrings.keyNewsletter),
                key('I', UiStrings.keyInbox),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
