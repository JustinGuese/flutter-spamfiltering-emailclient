import 'package:flutter_test/flutter_test.dart';
import 'package:spamfiltering_emailclient/mail/reply_builder.dart';
import 'package:spamfiltering_emailclient/mail/smtp_service.dart';

ComposeDraft _draft(
  ComposeMode mode, {
  String sender = 'alice@x.com',
  List<String> to = const ['me@y.com', 'bob@x.com'],
  List<String> cc = const ['carol@x.com', 'ME@Y.com'],
  String subject = 'Lunch',
}) =>
    buildDraft(
      mode: mode,
      accountId: 'a1',
      accountEmail: 'me@y.com',
      sender: sender,
      to: to,
      cc: cc,
      subject: subject,
      dateText: 'Mon 2 Nov 2026',
      textBody: 'hello\n\nworld',
      messageId: '<m1@x.com>',
    );

void main() {
  test('reply goes to the sender only and quotes the original', () {
    final d = _draft(ComposeMode.reply);
    expect(d.to, ['alice@x.com']);
    expect(d.cc, isEmpty);
    expect(d.subject, 'Re: Lunch');
    expect(d.inReplyTo, '<m1@x.com>');
    expect(d.accountId, 'a1');
    expect(d.body, contains('On Mon 2 Nov 2026, alice@x.com wrote:\n> hello\n>\n> world'));
    expect(d.body.startsWith('\n\n'), isTrue, reason: 'cursor space above the quote');
  });

  test('reply all keeps everyone except the account itself, without duplicates', () {
    final d = _draft(ComposeMode.replyAll);
    expect(d.to, ['alice@x.com']);
    expect(d.cc, ['bob@x.com', 'carol@x.com']);
  });

  test('reply all to a message you sent goes to its recipients', () {
    final d = _draft(ComposeMode.replyAll, sender: 'me@y.com', to: ['bob@x.com'], cc: ['carol@x.com']);
    expect(d.to, ['bob@x.com']);
    expect(d.cc, ['carol@x.com']);
  });

  test('forward has no recipients or thread header and carries the original headers', () {
    final d = _draft(ComposeMode.forward);
    expect(d.to, isEmpty);
    expect(d.inReplyTo, isNull);
    expect(d.subject, 'Fwd: Lunch');
    expect(d.body, contains('Forwarded message'));
    expect(d.body, contains('From: alice@x.com'));
    expect(d.body, contains('Cc: carol@x.com, ME@Y.com'));
    expect(d.body, endsWith('hello\n\nworld'));
  });

  test('subject prefixes never stack', () {
    expect(prefixedSubject('Re: Lunch', ComposeMode.reply), 'Re: Lunch');
    expect(prefixedSubject('RE: Lunch', ComposeMode.replyAll), 'RE: Lunch');
    expect(prefixedSubject('Fwd: Lunch', ComposeMode.forward), 'Fwd: Lunch');
    expect(prefixedSubject('FW: Lunch', ComposeMode.forward), 'FW: Lunch');
    expect(prefixedSubject('Lunch', ComposeMode.forward), 'Fwd: Lunch');
  });

  test('quoted mail text is escaped in the outgoing HTML part', () {
    final html = textToHtml('> <script>alert(1)</script> & more');
    expect(html, isNot(contains('<script>')));
    expect(html, contains('&lt;script&gt;'));
    expect(html, contains('&amp;'));
  });
}
