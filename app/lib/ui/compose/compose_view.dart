import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:df_theme/df_theme.dart';
import '../../app/strings.dart';
import '../../app/ui_strings.dart';
import '../../theme/app_type.dart';
import '../common/app_parts.dart';
import '../../mail/account_repository.dart';
import '../../mail/reply_builder.dart';
import '../../mail/smtp_service.dart';
import '../../mail/sync_engine.dart';

class ComposeView extends ConsumerStatefulWidget {
  /// Prefill for Reply / Reply All / Forward; null opens an empty message.
  final ComposeDraft? draft;

  const ComposeView({super.key, this.draft});

  @override
  ConsumerState<ComposeView> createState() => _ComposeViewState();
}

class _ComposeViewState extends ConsumerState<ComposeView> {
  final _toController = TextEditingController();
  final _ccController = TextEditingController();
  final _bccController = TextEditingController();
  final _subjectController = TextEditingController();
  final _bodyController = TextEditingController();

  bool _showCc = false;
  bool _showBcc = false;
  String? _selectedAccountId;
  String _savedIndicator = '';
  Timer? _autosaveTimer;

  @override
  void initState() {
    super.initState();
    final draft = widget.draft;
    if (draft != null) {
      _selectedAccountId = draft.accountId;
      _toController.text = draft.to.join(', ');
      _ccController.text = draft.cc.join(', ');
      _showCc = draft.cc.isNotEmpty;
      _subjectController.text = draft.subject;
      _bodyController.text = draft.body;
      // Cursor above the quote, where the answer is typed.
      _bodyController.selection = const TextSelection.collapsed(offset: 0);
    }

    _autosaveTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      final now = DateTime.now();
      final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      if (mounted) {
        setState(() {
          _savedIndicator = '${AppStrings.composeDraftSaved} $timeStr';
        });
      }
    });
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    _toController.dispose();
    _ccController.dispose();
    _bccController.dispose();
    _subjectController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.df.colors;
    final accountRepo = ref.watch(accountRepositoryProvider);
    final accounts = accountRepo.listAccounts();

    // Also covers a draft whose account has since been removed.
    if (!accounts.any((a) => a.id == _selectedAccountId) && accounts.isNotEmpty) {
      _selectedAccountId = accounts.first.id;
    }

    final narrow = MediaQuery.sizeOf(context).width < 700;

    Widget row(String label, Widget field, {Widget? trailing}) => Container(
          padding: EdgeInsets.symmetric(horizontal: narrow ? 20 : 32, vertical: 4),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: palette.hairline))),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 72,
                child: Text(label.toUpperCase(), style: AppType.mono(palette.textTertiary, size: 10.5, weight: FontWeight.w600, letterSpacing: 1.3)),
              ),
              Expanded(child: field),
              ?trailing,
            ],
          ),
        );

    InputDecoration bare(String? hint) => InputDecoration(
          hintText: hint,
          hintStyle: AppType.ui(palette.textDisabled, size: 15),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          filled: false,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        );

    Widget reveal(String text, VoidCallback onTap) => TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(minimumSize: const Size(36, 32), padding: const EdgeInsets.symmetric(horizontal: 8)),
          child: Text(text, style: AppType.mono(palette.brand.deep, size: 12, weight: FontWeight.w700)),
        );

    return Scaffold(
      backgroundColor: palette.canvas,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              height: 68,
              padding: EdgeInsets.symmetric(horizontal: narrow ? 8 : 24),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: palette.hairline))),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    tooltip: AppStrings.composeDiscard,
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 4),
                  Text(AppStrings.composeTitle, style: AppType.display(palette.textPrimary, size: 22, weight: 600, letterSpacing: -0.4)),
                  const Spacer(),
                  if (_savedIndicator.isNotEmpty && !narrow)
                    Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: Text(_savedIndicator, style: AppType.mono(palette.textTertiary, size: 11)),
                    ),
                  Tooltip(
                    message: UiStrings.attachSoon,
                    child: IconButton(icon: const Icon(Icons.attach_file_rounded), onPressed: null),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () => _sendMessage(accounts),
                    style: FilledButton.styleFrom(
                      backgroundColor: palette.brand.deep,
                      foregroundColor: palette.textOnBrand,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(context.df.shape.pill)),
                    ),
                    icon: const Icon(Icons.north_east_rounded, size: 16),
                    label: Text(UiStrings.send, style: AppType.ui(palette.textOnBrand, size: 14, weight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 820),
                  child: Container(
                    margin: EdgeInsets.symmetric(vertical: narrow ? 0 : 24),
                    decoration: BoxDecoration(
                      color: palette.surface,
                      borderRadius: BorderRadius.circular(narrow ? 0 : context.df.shape.lg),
                      border: narrow ? null : Border.all(color: palette.hairline),
                      boxShadow: narrow ? null : context.df.cardShadow,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        if (accounts.length > 1)
                          row(
                            UiStrings.fieldFrom,
                            DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _selectedAccountId,
                                isExpanded: true,
                                style: AppType.ui(palette.textPrimary, size: 14.5),
                                items: accounts.map((a) => DropdownMenuItem(value: a.id, child: Text('${a.displayName} <${a.email}>'))).toList(),
                                onChanged: (val) => setState(() => _selectedAccountId = val),
                              ),
                            ),
                          ),
                        row(
                          UiStrings.fieldTo,
                          TextField(controller: _toController, style: AppType.ui(palette.textPrimary, size: 15), decoration: bare(AppStrings.composeToHint)),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            if (!_showCc) reveal(UiStrings.fieldCc, () => setState(() => _showCc = true)),
                            if (!_showBcc) reveal(UiStrings.fieldBcc, () => setState(() => _showBcc = true)),
                          ]),
                        ),
                        if (_showCc)
                          row(UiStrings.fieldCc, TextField(controller: _ccController, style: AppType.ui(palette.textPrimary, size: 15), decoration: bare(null))),
                        if (_showBcc)
                          row(UiStrings.fieldBcc, TextField(controller: _bccController, style: AppType.ui(palette.textPrimary, size: 15), decoration: bare(null))),
                        row(
                          UiStrings.fieldSubject,
                          TextField(
                            controller: _subjectController,
                            style: AppType.display(palette.textPrimary, size: 21, weight: 600, letterSpacing: -0.3, height: 1.2),
                            decoration: bare(AppStrings.composeSubjectHint).copyWith(contentPadding: const EdgeInsets.symmetric(vertical: 16)),
                          ),
                        ),
                        Expanded(
                          child: LedgerPaper(
                            lineGap: 30,
                            offset: 45,
                            opacity: 0.45,
                            child: TextField(
                              controller: _bodyController,
                              expands: true,
                              maxLines: null,
                              minLines: null,
                              textAlignVertical: TextAlignVertical.top,
                              style: AppType.ui(palette.textPrimary, size: 16, height: 30 / 16),
                              decoration: bare(AppStrings.composeBodyHint).copyWith(
                                contentPadding: EdgeInsets.fromLTRB(narrow ? 20 : 32, 20, narrow ? 20 : 32, 20),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendMessage(List<AccountRecord> accounts) async {
    final account = accounts.where((a) => a.id == _selectedAccountId).firstOrNull;
    if (account == null) return;
    final toList = _toController.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (toList.isEmpty) return;

    final auth = await ref.read(accountRepositoryProvider).getAuthForAccount(account.id);
    if (auth == null) return;

    final smtp = SmtpService();
    await smtp.sendMail(
      account: account,
      auth: auth,
      to: toList,
      cc: _ccController.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
      bcc: _bccController.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
      subject: _subjectController.text,
      bodyText: _bodyController.text,
      inReplyTo: widget.draft?.inReplyTo,
    );

    // Servers that file sent mail themselves: pull it into Sent right away.
    unawaited(ref.read(syncEngineProvider).syncAccount(account.id).catchError((Object _) {}));
    if (mounted) Navigator.of(context).pop();
  }
}
