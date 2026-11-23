import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:df_theme/df_theme.dart';
import '../../app/bootstrap.dart';
import '../../app/log.dart';
import '../../app/strings.dart';
import '../../app/ui_strings.dart';
import '../../theme/app_type.dart';
import '../common/app_parts.dart';
import '../../mail/account_repository.dart';
import '../../mail/autodiscover.dart';
import '../../mail/imap_service.dart';
import '../../mail/mail_auth.dart';
import '../../mail/sync_engine.dart';

class AccountSetupView extends ConsumerStatefulWidget {
  final VoidCallback? onSetupSuccess;

  const AccountSetupView({super.key, this.onSetupSuccess});

  @override
  ConsumerState<AccountSetupView> createState() => _AccountSetupViewState();
}

class _AccountSetupViewState extends ConsumerState<AccountSetupView> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _imapHostCtrl = TextEditingController();
  final _imapPortCtrl = TextEditingController(text: '993');
  final _smtpHostCtrl = TextEditingController();
  final _smtpPortCtrl = TextEditingController(text: '587');

  bool _isManual = false;
  bool _isLoading = false;
  final List<AutodiscoverLine> _ledgerLines = [];

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _nameCtrl.dispose();
    _imapHostCtrl.dispose();
    _imapPortCtrl.dispose();
    _smtpHostCtrl.dispose();
    _smtpPortCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.df.colors;
    final wide = MediaQuery.sizeOf(context).width >= 900;

    Widget promise(String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.check_rounded, size: 18, color: c.accent.base),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: AppType.ui(c.textSecondary, size: 14.5, height: 1.4))),
          ]),
        );

    final intro = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(UiStrings.setupHeadline, style: AppType.display(c.textPrimary, size: wide ? 56 : 38, weight: 500, italic: true, letterSpacing: -1.4, height: 1.02)),
        const SizedBox(height: 14),
        Text(UiStrings.setupSub, style: AppType.ui(c.textSecondary, size: 16, height: 1.5)),
        const SizedBox(height: 22),
        promise(UiStrings.setupPromise1),
        promise(UiStrings.setupPromise2),
        promise(UiStrings.setupPromise3),
      ],
    );

    final form = Container(
      padding: EdgeInsets.all(wide ? 32 : 0),
      decoration: wide
          ? BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(context.df.shape.lg),
              border: Border.all(color: c.hairline),
              boxShadow: context.df.cardShadow,
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: AppStrings.setupDisplayName)),
          const SizedBox(height: 14),
          TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: AppStrings.setupEmail),
            onChanged: _onEmailChanged,
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _passwordCtrl,
            obscureText: true,
            decoration: const InputDecoration(labelText: AppStrings.setupPassword),
          ),
          const SizedBox(height: 10),
          Text(AppStrings.setupAppPasswordNote, style: AppType.ui(c.textTertiary, size: 12.5, height: 1.45)),
          if (_ledgerLines.isNotEmpty) ...[
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: BoxDecoration(
                color: c.surfaceSunken,
                borderRadius: BorderRadius.circular(context.df.shape.sm),
                border: Border.all(color: c.hairline),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Eyebrow(UiStrings.setupLedgerTitle),
                  const SizedBox(height: 8),
                  for (final line in _ledgerLines)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(children: [
                        Icon(line.isSuccess ? Icons.check_circle_rounded : Icons.circle_outlined, size: 14, color: line.isSuccess ? c.accent.base : c.textTertiary),
                        const SizedBox(width: 8),
                        Expanded(child: Text(line.text, style: AppType.mono(line.isSuccess ? c.accent.onContainer : c.textSecondary, size: 12))),
                      ]),
                    ),
                ],
              ),
            ),
          ],
          if (_isManual) ...[
            const SizedBox(height: 18),
            Row(children: [
              Expanded(flex: 3, child: TextField(controller: _imapHostCtrl, decoration: const InputDecoration(labelText: AppStrings.setupImapHost))),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: _imapPortCtrl, decoration: const InputDecoration(labelText: AppStrings.setupImapPort))),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(flex: 3, child: TextField(controller: _smtpHostCtrl, decoration: const InputDecoration(labelText: AppStrings.setupSmtpHost))),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: _smtpPortCtrl, decoration: const InputDecoration(labelText: AppStrings.setupSmtpPort))),
            ]),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _isLoading ? null : _connectAccount,
            style: FilledButton.styleFrom(
              backgroundColor: c.brand.deep,
              foregroundColor: c.textOnBrand,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(context.df.shape.md)),
            ),
            child: Text(_isLoading ? UiStrings.setupConnecting : AppStrings.setupConnect, style: AppType.ui(c.textOnBrand, size: 15, weight: FontWeight.w600)),
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: () => setState(() => _isManual = !_isManual),
            child: Text(_isManual ? UiStrings.setupUseAuto : AppStrings.setupManualConfig, style: AppType.ui(c.brand.deep, size: 13.5, weight: FontWeight.w600)),
          ),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: c.canvas,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(AppStrings.setupTitle, style: AppType.ui(c.textTertiary, size: 13, weight: FontWeight.w600, letterSpacing: 0.3)),
      ),
      body: LedgerPaper(
        margin: wide,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(wide ? 88 : 24, wide ? 40 : 8, wide ? 64 : 24, 40),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: wide ? 1180 : 520),
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 6, child: Padding(padding: const EdgeInsets.only(top: 24, right: 64), child: intro)),
                        Expanded(flex: 5, child: form),
                      ],
                    )
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [intro, const SizedBox(height: 28), form]),
            ),
          ),
        ),
      ),
    );
  }

  void _onEmailChanged(String email) {
    final discovered = MailAutodiscover.resolveKnown(email);
    if (discovered != null) {
      setState(() {
        _imapHostCtrl.text = discovered.imapHost;
        _imapPortCtrl.text = discovered.imapPort.toString();
        _smtpHostCtrl.text = discovered.smtpHost;
        _smtpPortCtrl.text = discovered.smtpPort.toString();
        _ledgerLines.clear();
        _ledgerLines.add(AutodiscoverLine(
          text: '${discovered.imapHost}:${discovered.imapPort} TLS',
          isSuccess: true,
        ));
        _ledgerLines.add(AutodiscoverLine(
          text: '${discovered.smtpHost}:${discovered.smtpPort} TLS',
          isSuccess: true,
        ));
      });
    }
  }

  Future<void> _connectAccount() async {
    setState(() => _isLoading = true);
    final email = _emailCtrl.text.trim();
    final name = _nameCtrl.text.trim().isEmpty ? email : _nameCtrl.text.trim();
    final password = _passwordCtrl.text;

    final account = AccountRecord(
      id: 'acc_${DateTime.now().millisecondsSinceEpoch}',
      email: email,
      displayName: name,
      imapHost: _imapHostCtrl.text.trim(),
      imapPort: int.tryParse(_imapPortCtrl.text) ?? 993,
      smtpHost: _smtpHostCtrl.text.trim(),
      smtpPort: int.tryParse(_smtpPortCtrl.text) ?? 587,
      authType: 'password',
      createdAt: DateTime.now(),
    );

    // Prove the server and password work before anything is saved, so a wrong
    // host or password is reported here instead of as an empty mailbox later.
    final probe = ImapService();
    try {
      await probe.connectAndAuthenticate(account, PasswordMailAuth(password));
    } catch (e, st) {
      logError('connection test ${account.imapHost}:${account.imapPort}', e, st);
      if (!mounted) return;
      setState(() => _isLoading = false);
      final hint = account.imapHost.toLowerCase().contains('smtp') ? ' ${UiStrings.setupImapLooksSmtp}' : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${AppStrings.setupFailed} ($e)$hint'),
          duration: const Duration(seconds: 12),
          showCloseIcon: true,
        ),
      );
      return;
    } finally {
      try {
        await probe.disconnect();
      } catch (_) {}
    }

    final repo = ref.read(accountRepositoryProvider);
    try {
      // The timeout matters on Linux: with no unlocked keyring the Secret
      // Service waits on a prompt that never shows and the write never returns.
      await repo
          .saveAccount(account, PasswordMailAuth(password))
          .timeout(const Duration(seconds: 15));
    } catch (e, st) {
      logError('save credentials', e, st);
      // The row goes synchronously; the keychain cleanup may hang just like the
      // write did, so it is best-effort.
      repo.deleteAccount(account.id).timeout(const Duration(seconds: 3)).catchError((Object _) {});
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${UiStrings.setupStoreFailed} ($e)')),
      );
      return;
    }

    ref.read(mailRevisionProvider.notifier).bump(); // Settings/sidebar show the new account
    // Runs in the background so the screen can close, but a bad password or
    // an unreachable server must not vanish: it is reported like any sync error.
    final syncEngine = ref.read(syncEngineProvider);
    final errors = ref.read(syncErrorProvider.notifier);
    syncEngine.syncAccount(account.id).catchError((Object e, StackTrace st) {
      logError('sync $email', e, st);
      errors.set('Sync failed for $email: $e');
    });

    setState(() => _isLoading = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.setupSuccess)),
      );
      widget.onSetupSuccess?.call();
      Navigator.of(context).pop();
    }
  }
}
