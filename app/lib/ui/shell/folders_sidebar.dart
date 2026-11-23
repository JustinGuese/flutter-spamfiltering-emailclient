import 'package:df_theme/df_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/strings.dart';
import '../../app/ui_strings.dart';
import '../../db/database.dart';
import '../../mail/sync_engine.dart';
import '../../platform/platform_services.dart';
import '../../theme/app_type.dart';
import '../common/app_parts.dart';
import '../common/mail_queries.dart';
import '../protection/protection_view.dart';

/// Left pane: brand mark, compose, mailboxes, a live "Your filter" ledger, account.
class FoldersSidebar extends ConsumerWidget {
  final VoidCallback onCompose;
  const FoldersSidebar({super.key, required this.onCompose});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.df.colors;
    ref.watch(mailRevisionProvider);
    final db = ref.watch(databaseProvider);
    final selected = effectiveFolderId(db, ref.watch(selectedFolderIdProvider));
    final folders = db.db.select('SELECT id, name, special_use, unread_count FROM folders');
    final account = db.db.select('SELECT email, display_name FROM accounts LIMIT 1').firstOrNull;
    final stats = filterStats(db);

    return Container(
      color: c.canvas,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
            child: Row(children: [
              _Mark(),
              const SizedBox(width: 10),
              Text(AppStrings.appName, style: AppType.display(c.textPrimary, size: 18, weight: 650, letterSpacing: -0.2)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
            child: _ComposeButton(onTap: onCompose),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 6),
            child: Align(alignment: Alignment.centerLeft, child: Eyebrow(UiStrings.sidebarMailboxes)),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final f in folders)
                  _FolderTile(
                    name: f['name'] as String,
                    icon: _icon(f['special_use'] as String?),
                    unread: f['unread_count'] as int,
                    selected: f['id'] == selected,
                    onTap: () {
                      ref.read(selectedFolderIdProvider.notifier).set(f['id'] as String);
                      ref.read(selectedMessageIdProvider.notifier).set(null);
                    },
                  ),
                const SizedBox(height: 22),
                Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 8), child: Eyebrow(UiStrings.sidebarFilter)),
                _StatsCard(stats: stats),
              ],
            ),
          ),
          if (account != null) _AccountChip(email: account['email'] as String, name: account['display_name'] as String),
        ],
      ),
    );
  }

  IconData _icon(String? use) => switch (use) {
        'inbox' => Icons.inbox_outlined,
        'sent' => Icons.north_east_rounded,
        'drafts' => Icons.edit_note_rounded,
        'trash' => Icons.delete_outline_rounded,
        'junk' => Icons.block_rounded,
        'archive' => Icons.inventory_2_outlined,
        _ => Icons.auto_stories_outlined,
      };
}

class _Mark extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/icon/icon_rounded.png',
      width: 30,
      height: 30,
      cacheWidth: 90,
      filterQuality: FilterQuality.medium,
      excludeFromSemantics: true,
    );
  }
}

class _ComposeButton extends StatelessWidget {
  final VoidCallback onTap;
  const _ComposeButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.df.colors;
    return Material(
      color: c.brand.deep,
      borderRadius: BorderRadius.circular(context.df.shape.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(context.df.shape.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(children: [
            Icon(Icons.edit_outlined, size: 18, color: c.textOnBrand),
            const SizedBox(width: 10),
            Text(UiStrings.compose, style: AppType.ui(c.textOnBrand, size: 14.5, weight: FontWeight.w600)),
            const Spacer(),
            Text('C', style: AppType.mono(c.textOnBrand.withValues(alpha: 0.7), size: 12, weight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}

class _FolderTile extends StatefulWidget {
  final String name;
  final IconData icon;
  final int unread;
  final bool selected;
  final VoidCallback onTap;
  const _FolderTile({required this.name, required this.icon, required this.unread, required this.selected, required this.onTap});

  @override
  State<_FolderTile> createState() => _FolderTileState();
}

class _FolderTileState extends State<_FolderTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.df.colors;
    final sel = widget.selected;
    final bg = sel ? c.brand.container : (_hover ? c.surfaceSunken : Colors.transparent);
    final fg = sel ? c.brand.onContainer : c.textSecondary;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: context.df.motion.fast,
          margin: const EdgeInsets.symmetric(vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(context.df.shape.sm)),
          child: Row(children: [
            Icon(widget.icon, size: 18, color: fg),
            const SizedBox(width: 12),
            Expanded(
              child: Text(widget.name,
                  style: AppType.ui(sel ? c.brand.onContainer : c.textPrimary, size: 14, weight: sel || widget.unread > 0 ? FontWeight.w600 : FontWeight.w500)),
            ),
            if (widget.unread > 0) Text('${widget.unread}', style: AppType.mono(sel ? c.brand.onContainer : c.textTertiary, size: 12, weight: FontWeight.w700)),
          ]),
        ),
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  final ({int caught, int learned, int community}) stats;
  const _StatsCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final c = context.df.colors;
    Widget row(int n, String caption, Color color, ProtectionTab tab) => InkWell(
          onTap: () => ProtectionView.open(context, tab: tab),
          child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            SizedBox(
              width: 74,
              child: Text(groupThousands(n), style: AppType.display(color, size: 26, weight: 600, height: 1, letterSpacing: -0.5)),
            ),
            Expanded(child: Text(caption, style: AppType.mono(c.textTertiary, size: 10.5, weight: FontWeight.w500))),
            Icon(Icons.chevron_right_rounded, size: 16, color: c.textDisabled),
          ]),
        ));
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(context.df.shape.md),
        border: Border.all(color: c.hairline),
      ),
      child: Column(children: [
        row(stats.caught, UiStrings.statCaught, c.error.base, ProtectionTab.story),
        Divider(height: 1, color: c.hairline),
        row(stats.learned, UiStrings.statLearned, c.brand.deep, ProtectionTab.learned),
        Divider(height: 1, color: c.hairline),
        row(stats.community, UiStrings.statCommunity, c.accent.base, ProtectionTab.story),
      ]),
    );
  }
}

class _AccountChip extends StatelessWidget {
  final String email;
  final String name;
  const _AccountChip({required this.email, required this.name});

  @override
  Widget build(BuildContext context) {
    final c = context.df.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: c.hairline))),
      child: Row(children: [
        Monogram(name: name, seed: email, size: 34),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: AppType.ui(c.textPrimary, size: 13, weight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(email, style: AppType.mono(c.textTertiary, size: 10.5), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
      ]),
    );
  }
}
