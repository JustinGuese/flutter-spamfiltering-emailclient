import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app/log.dart';
import '../db/database.dart';
import 'account_repository.dart';
import 'list_unsubscribe.dart';
import 'smtp_service.dart';
import 'unsubscribe_guard.dart';

/// The trigger that initiated an unsubscribe action.
enum UnsubscribeTrigger {
  /// Automated unsubscribe fired after the user marks a message as spam (after undo window).
  verdict,

  /// Manual unsubscribe initiated by the user tapping Unsubscribe button in reader.
  manual,
}

/// Status outcome of an unsubscribe attempt.
enum UnsubscribeStatus {
  sent,
  failed,
  skippedDisabled,
  skippedNoTarget,
  skippedUnauthenticated,
  skippedDuplicate,
  skippedRateLimited,
  skippedSelfDomain,
  skippedUnsafeUrl,
}

/// The result of an unsubscribe attempt.
class UnsubscribeOutcome {
  final UnsubscribeStatus status;

  /// The method used: 'one_click' or 'mailto', or null if skipped/no target.
  final String? method;

  const UnsubscribeOutcome(this.status, {this.method});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UnsubscribeOutcome &&
          runtimeType == other.runtimeType &&
          status == other.status &&
          method == other.method;

  @override
  int get hashCode => Object.hash(status, method);

  @override
  String toString() => 'UnsubscribeOutcome($status, method: $method)';
}

/// Abstract contract for mail sending in unsubscribe actions to allow injection/mocking.
abstract class UnsubscribeMailSender {
  Future<void> sendUnsubscribeMail({
    required AccountRecord account,
    required MailtoTarget mailto,
  });
}

/// Default implementation of [UnsubscribeMailSender] using [SmtpService].
class SmtpUnsubscribeMailSender implements UnsubscribeMailSender {
  final AccountRepository accountRepo;
  final SmtpService smtpService;

  SmtpUnsubscribeMailSender({
    required this.accountRepo,
    SmtpService? smtpService,
  }) : smtpService = smtpService ?? SmtpService();

  @override
  Future<void> sendUnsubscribeMail({
    required AccountRecord account,
    required MailtoTarget mailto,
  }) async {
    final auth = await accountRepo.getAuthForAccount(account.id);
    if (auth == null) {
      throw StateError('No credentials found for account ${account.id}');
    }

    // Message is NOT appended to Sent folder (imapForSentAppend is omitted/null)
    await smtpService.sendMail(
      account: account,
      auth: auth,
      to: [mailto.to],
      subject: mailto.subject,
      bodyText: mailto.body,
    );
  }
}

/// Implementation of RFC 8058 One-Click and RFC 2369 mailto unsubscribe service.
class UnsubscribeServiceImpl implements UnsubscribeService {
  final AppDatabase db;
  final AccountRepository accountRepo;
  final UnsubscribeGuard guard;
  final Dio dio;
  final UnsubscribeMailSender mailSender;
  final DateTime Function() clock;

  UnsubscribeServiceImpl({
    required this.db,
    required this.accountRepo,
    UnsubscribeGuard? guard,
    Dio? dio,
    UnsubscribeMailSender? mailSender,
    DateTime Function()? clock,
  })  : guard = guard ?? const UnsubscribeGuard(),
        dio = dio ?? _createDefaultDio(),
        mailSender = mailSender ??
            SmtpUnsubscribeMailSender(accountRepo: accountRepo),
        clock = clock ?? DateTime.now;

  static Dio _createDefaultDio() {
    return Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        sendTimeout: const Duration(seconds: 10),
        headers: {
          'User-Agent': 'DataFortress-Mail/1.0',
        },
        followRedirects: false,
        validateStatus: (status) => status != null && status >= 200 && status < 300,
      ),
    );
  }

  @override
  Future<UnsubscribeOutcome> unsubscribeForMessage(
    String messageId, {
    required UnsubscribeTrigger trigger,
  }) async {
    // 1. Setting: check 'auto_unsubscribe' (defaults true).
    // If false and trigger == verdict, return skippedDisabled (do not write log).
    if (trigger == UnsubscribeTrigger.verdict && !db.isAutoUnsubscribeEnabled) {
      return const UnsubscribeOutcome(UnsubscribeStatus.skippedDisabled);
    }

    // Fetch message
    final msgRows = db.db.select(
      'SELECT id, account_id, sender, sender_domain, list_unsubscribe, list_unsubscribe_post, sender_auth_pass '
      'FROM messages WHERE id = ?',
      [messageId],
    );
    if (msgRows.isEmpty) {
      return const UnsubscribeOutcome(UnsubscribeStatus.skippedNoTarget);
    }

    final msg = msgRows.first;
    final accountId = msg['account_id'] as String;
    var senderDomain = (msg['sender_domain'] as String?)?.toLowerCase().trim();
    final senderRaw = msg['sender'] as String? ?? '';
    final listUnsub = msg['list_unsubscribe'] as String?;
    final listUnsubPost = msg['list_unsubscribe_post'] as String?;
    final senderAuthPass = (msg['sender_auth_pass'] as int? ?? 0) == 1;

    // Fallback for senderDomain if null or empty
    if (senderDomain == null || senderDomain.isEmpty) {
      final at = senderRaw.lastIndexOf('@');
      if (at != -1 && at < senderRaw.length - 1) {
        var dom = senderRaw.substring(at + 1).trim();
        if (dom.endsWith('>')) dom = dom.substring(0, dom.length - 1).trim();
        senderDomain = dom.toLowerCase();
      } else {
        senderDomain = '';
      }
    }

    // Parse targets
    final targets = parseListUnsubscribe(listUnsub, listUnsubPost);
    if (!targets.hasTarget) {
      return const UnsubscribeOutcome(UnsubscribeStatus.skippedNoTarget);
    }

    // Fetch account
    final accounts = accountRepo.listAccounts();
    final account = accounts.where((a) => a.id == accountId).firstOrNull;
    if (account == null) {
      return const UnsubscribeOutcome(UnsubscribeStatus.skippedNoTarget);
    }

    final recipientEmail = account.email.toLowerCase().trim();
    final recipientDomain = recipientEmail.contains('@')
        ? recipientEmail.substring(recipientEmail.lastIndexOf('@') + 1).trim()
        : '';

    // Self-domain check
    if (senderDomain.isNotEmpty &&
        recipientDomain.isNotEmpty &&
        senderDomain == recipientDomain) {
      _writeLog(
        accountId: accountId,
        senderDomain: senderDomain,
        messageId: messageId,
        method: null,
        status: UnsubscribeStatus.skippedSelfDomain.name,
      );
      return const UnsubscribeOutcome(UnsubscribeStatus.skippedSelfDomain);
    }

    // Auth check: Only authenticated senders get auto-unsubscribed on verdict.
    // On manual, authentication guard is bypassed.
    if (trigger == UnsubscribeTrigger.verdict && !senderAuthPass) {
      _writeLog(
        accountId: accountId,
        senderDomain: senderDomain,
        messageId: messageId,
        method: null,
        status: UnsubscribeStatus.skippedUnauthenticated.name,
      );
      return const UnsubscribeOutcome(UnsubscribeStatus.skippedUnauthenticated);
    }

    // Rate cap check: Max 20 unsubscribe attempts per rolling 24 h across all accounts.
    // We check rows where method IN ('one_click', 'mailto') created in last 24h.
    final now = clock().toUtc();
    final cutoff24h = now.subtract(const Duration(hours: 24)).toIso8601String();
    final attemptsCountRow = db.db.select(
      "SELECT COUNT(*) as c FROM unsubscribe_log WHERE created_at >= ? AND method IS NOT NULL",
      [cutoff24h],
    );
    final countLast24h = (attemptsCountRow.first['c'] as int?) ?? 0;
    if (countLast24h >= 20) {
      _writeLog(
        accountId: accountId,
        senderDomain: senderDomain,
        messageId: messageId,
        method: null,
        status: UnsubscribeStatus.skippedRateLimited.name,
      );
      return const UnsubscribeOutcome(UnsubscribeStatus.skippedRateLimited);
    }

    // Idempotency:
    // One successful attempt per (account, sender domain) per 30 days;
    // Failures retried after 24 h, max 3 attempts.
    final cutoff30d = now.subtract(const Duration(days: 30)).toIso8601String();
    final logs = db.db.select(
      'SELECT status, created_at FROM unsubscribe_log '
      'WHERE account_id = ? AND sender_domain = ? AND created_at >= ? '
      'ORDER BY created_at DESC',
      [accountId, senderDomain, cutoff30d],
    );

    // Check for success in last 30 days
    final hasRecentSuccess = logs.any((r) => (r['status'] as String) == UnsubscribeStatus.sent.name);
    if (hasRecentSuccess) {
      _writeLog(
        accountId: accountId,
        senderDomain: senderDomain,
        messageId: messageId,
        method: null,
        status: UnsubscribeStatus.skippedDuplicate.name,
      );
      return const UnsubscribeOutcome(UnsubscribeStatus.skippedDuplicate);
    }

    // Check recent failures within 24 hours or max 3 attempts
    final failureLogs = logs.where((r) => (r['status'] as String) == UnsubscribeStatus.failed.name).toList();
    if (failureLogs.isNotEmpty) {
      if (failureLogs.length >= 3) {
        // Max 3 attempts reached
        _writeLog(
          accountId: accountId,
          senderDomain: senderDomain,
          messageId: messageId,
          method: null,
          status: UnsubscribeStatus.skippedDuplicate.name,
        );
        return const UnsubscribeOutcome(UnsubscribeStatus.skippedDuplicate);
      }

      // Check if most recent failure was within 24 hours
      final latestFailTime = DateTime.tryParse(failureLogs.first['created_at'] as String)?.toUtc();
      if (latestFailTime != null && now.difference(latestFailTime).inHours < 24) {
        _writeLog(
          accountId: accountId,
          senderDomain: senderDomain,
          messageId: messageId,
          method: null,
          status: UnsubscribeStatus.skippedDuplicate.name,
        );
        return const UnsubscribeOutcome(UnsubscribeStatus.skippedDuplicate);
      }
    }

    // Execution: Prefer One-Click, fallback to mailto
    if (targets.oneClickUrl != null) {
      final outcome = await _executeOneClick(
        url: targets.oneClickUrl!,
        accountId: accountId,
        senderDomain: senderDomain,
        messageId: messageId,
      );
      return outcome;
    } else if (targets.mailto != null) {
      final outcome = await _executeMailto(
        mailto: targets.mailto!,
        account: account,
        senderDomain: senderDomain,
        messageId: messageId,
      );
      return outcome;
    }

    return const UnsubscribeOutcome(UnsubscribeStatus.skippedNoTarget);
  }

  Future<UnsubscribeOutcome> _executeOneClick({
    required Uri url,
    required String accountId,
    required String senderDomain,
    required String messageId,
  }) async {
    const method = 'one_click';

    // SSRF / URL safety check
    final isSafe = await guard.isSafe(url);
    if (!isSafe) {
      _writeLog(
        accountId: accountId,
        senderDomain: senderDomain,
        messageId: messageId,
        method: method,
        status: UnsubscribeStatus.skippedUnsafeUrl.name,
      );
      return const UnsubscribeOutcome(
        UnsubscribeStatus.skippedUnsafeUrl,
        method: method,
      );
    }

    // Request hygiene:
    // Plain Dio, no cookies, no auth headers, no app/device IDs, generic User-Agent.
    // Body is exactly 'List-Unsubscribe=One-Click', Content-Type: application/x-www-form-urlencoded.
    // No redirects followed (a 3xx is logged as failed).
    try {
      final response = await dio.postUri(
        url,
        data: 'List-Unsubscribe=One-Click',
        options: Options(
          contentType: 'application/x-www-form-urlencoded',
          followRedirects: false,
          validateStatus: (status) => status != null && status >= 200 && status < 300,
          headers: {
            // Explicitly ensure no leftover auth / cookie headers
            'User-Agent': 'DataFortress-Mail/1.0',
          },
        ),
      );

      if (response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300) {
        _writeLog(
          accountId: accountId,
          senderDomain: senderDomain,
          messageId: messageId,
          method: method,
          status: UnsubscribeStatus.sent.name,
        );
        return const UnsubscribeOutcome(UnsubscribeStatus.sent, method: method);
      } else {
        _writeLog(
          accountId: accountId,
          senderDomain: senderDomain,
          messageId: messageId,
          method: method,
          status: UnsubscribeStatus.failed.name,
        );
        return const UnsubscribeOutcome(UnsubscribeStatus.failed, method: method);
      }
    } catch (e) {
      logError('One-click unsubscribe failed for $url', e);
      _writeLog(
        accountId: accountId,
        senderDomain: senderDomain,
        messageId: messageId,
        method: method,
        status: UnsubscribeStatus.failed.name,
      );
      return const UnsubscribeOutcome(UnsubscribeStatus.failed, method: method);
    }
  }

  Future<UnsubscribeOutcome> _executeMailto({
    required MailtoTarget mailto,
    required AccountRecord account,
    required String senderDomain,
    required String messageId,
  }) async {
    const method = 'mailto';

    // mailto safety: recipient is not the account's own address
    if (mailto.to.toLowerCase() == account.email.toLowerCase()) {
      _writeLog(
        accountId: account.id,
        senderDomain: senderDomain,
        messageId: messageId,
        method: method,
        status: UnsubscribeStatus.failed.name,
      );
      return const UnsubscribeOutcome(UnsubscribeStatus.failed, method: method);
    }

    try {
      await mailSender.sendUnsubscribeMail(account: account, mailto: mailto);
      _writeLog(
        accountId: account.id,
        senderDomain: senderDomain,
        messageId: messageId,
        method: method,
        status: UnsubscribeStatus.sent.name,
      );
      return const UnsubscribeOutcome(UnsubscribeStatus.sent, method: method);
    } catch (e) {
      logError('Mailto unsubscribe failed for ${mailto.to}', e);
      _writeLog(
        accountId: account.id,
        senderDomain: senderDomain,
        messageId: messageId,
        method: method,
        status: UnsubscribeStatus.failed.name,
      );
      return const UnsubscribeOutcome(UnsubscribeStatus.failed, method: method);
    }
  }

  void _writeLog({
    required String accountId,
    required String senderDomain,
    required String? messageId,
    required String? method,
    required String status,
  }) {
    final nowStr = clock().toUtc().toIso8601String();
    db.db.execute(
      '''
      INSERT INTO unsubscribe_log (account_id, sender_domain, message_id, method, status, created_at)
      VALUES (?, ?, ?, ?, ?, ?)
      ''',
      [accountId, senderDomain, messageId, method, status, nowStr],
    );
  }
}

/// Riverpod provider for [UnsubscribeService].
final unsubscribeServiceProvider = Provider<UnsubscribeService>((ref) {
  final db = ref.watch(databaseProvider);
  final accountRepo = ref.watch(accountRepositoryProvider);
  return UnsubscribeServiceImpl(
    db: db,
    accountRepo: accountRepo,
  );
});

/// Abstract base class / contract.
abstract class UnsubscribeService {
  Future<UnsubscribeOutcome> unsubscribeForMessage(
    String messageId, {
    required UnsubscribeTrigger trigger,
  });
}
