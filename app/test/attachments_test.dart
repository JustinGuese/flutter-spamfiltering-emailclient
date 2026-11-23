import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:enough_mail/enough_mail.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spamfiltering_emailclient/mail/attachments.dart';
import 'package:spamfiltering_emailclient/mail/smtp_service.dart';

Uint8List _bytes(int n) => Uint8List.fromList(List.generate(n, (i) => (i * 7 + 3) % 256));

MimeMessage _roundTrip(MimeMessage m) => MimeMessage.parseFromText(m.renderMessage());

void main() {
  group('outgoing message', () {
    final from = MailAddress('Me', 'me@example.com');

    test('without files it stays multipart/alternative', () {
      final m = buildOutgoingMessage(from: from, to: ['a@b.c'], subject: 's', bodyText: 'hi');
      expect(m.getHeaderContentType()!.mediaType.sub, MediaSubtype.multipartAlternative);
      expect(extractAttachments(_roundTrip(m)), isEmpty);
    });

    test('with files it is multipart/mixed: the text pair first, then each file, bytes intact', () {
      final pdf = _bytes(5000);
      final png = _bytes(321);
      final m = buildOutgoingMessage(
        from: from,
        to: ['a@b.c'],
        subject: 'Invoice',
        bodyText: 'see attached',
        attachments: [
          LoadedAttachment('Rechnung März.pdf', 'application/pdf', pdf),
          LoadedAttachment('logo.png', 'image/png', png),
        ],
      );
      final parsed = _roundTrip(m);
      expect(parsed.getHeaderContentType()!.mediaType.sub, MediaSubtype.multipartMixed);
      expect(parsed.decodeTextPlainPart()!.trim(), 'see attached');
      expect(parsed.decodeTextHtmlPart(), contains('see attached'));

      final files = extractAttachments(parsed);
      expect(files.map((f) => f.fileName), ['Rechnung März.pdf', 'logo.png']);
      expect(files.map((f) => f.mimeType), ['application/pdf', 'image/png']);
      expect(partOf(parsed, files[0].fetchId)!.decodeContentBinary(), pdf);
      expect(partOf(parsed, files[1].fetchId)!.decodeContentBinary(), png);
      expect(parsed.hasAttachments(), isTrue);
    });
  });

  group('extractAttachments', () {
    MimeMessage parse(List<String> parts) => MimeMessage.parseFromText(
        'From: a@b.c\r\nSubject: x\r\nMIME-Version: 1.0\r\nContent-Type: multipart/mixed; boundary=b\r\n\r\n${parts.join()}--b--');

    String part(String headers, String content) => '--b\r\n$headers\r\n\r\n$content\r\n';

    test('finds attachments in nested multiparts with IMAP part numbers', () {
      final data = base64.encode(utf8.encode('hello world'));
      final m = parse([
        part('Content-Type: multipart/alternative; boundary=c', '--c\r\nContent-Type: text/plain\r\n\r\nbody\r\n--c--'),
            part('Content-Type: application/pdf; name="a.pdf"\r\nContent-Disposition: attachment; filename="a.pdf"\r\nContent-Transfer-Encoding: base64', data)
      ]);
      final files = extractAttachments(m);
      expect(files, hasLength(1));
      expect(files.single.fetchId, '2');
      expect(utf8.decode(partOf(m, '2')!.decodeContentBinary()!), 'hello world');
    });

    test('counts a named non-text part without a disposition, but not the text body or a cid logo', () {
      final m = parse([
        part('Content-Type: text/plain', 'body'),
            part('Content-Type: image/png\r\nContent-ID: <logo@x>\r\nContent-Disposition: inline; filename="logo.png"\r\nContent-Transfer-Encoding: base64', 'AAAA'),
            part('Content-Type: application/zip; name="old-mailer.zip"\r\nContent-Transfer-Encoding: base64', 'AAAA')
      ]);
      expect(extractAttachments(m).map((f) => f.fileName), ['old-mailer.zip']);
    });

    test('an attached mail is one attachment and is not entered', () {
      final m = parse([
        part('Content-Type: text/plain', 'body'),
            part('Content-Type: message/rfc822\r\nContent-Disposition: attachment', 'From: x@y.z\r\nContent-Type: multipart/mixed; boundary=z\r\n\r\n--z\r\nContent-Type: text/plain\r\n\r\nin\r\n--z--')
      ]);
      final files = extractAttachments(m);
      expect(files, hasLength(1));
      expect(files.single.fileName, 'message.eml');
    });

    test('an unnamed attachment gets a fallback name', () {
      final m = parse([part('Content-Type: application/octet-stream\r\nContent-Disposition: attachment', 'AAAA')]);
      expect(extractAttachments(m).single.fileName, 'attachment');
    });

    test('a plain text mail has none', () {
      expect(extractAttachments(MimeMessage.parseFromText('Subject: x\r\nContent-Type: text/plain\r\n\r\nhi')), isEmpty);
    });
  });

  group('file names from the outside world', () {
    test('safeFileName strips directories, control characters, dots and reserved names', () {
      expect(safeFileName('../../.bashrc'), 'bashrc');
      expect(safeFileName(r'C:\Users\x\evil.exe'), 'evil.exe');
      expect(safeFileName('a<b>:c|d?.txt'), 'a_b__c_d_.txt');
      expect(safeFileName('nul.txt'), '_nul.txt');
      expect(safeFileName('   '), 'attachment');
      expect(safeFileName(null, fallback: 'x'), 'x');
      expect(safeFileName('report.'), 'report');
      final long = safeFileName('${'a' * 300}.pdf');
      expect(long.length, 120);
      expect(long, endsWith('.pdf'));
    });

    test('runnable types are recognised case-insensitively', () {
      expect(isRunnableFileName('Setup.EXE'), isTrue);
      expect(isRunnableFileName('run.sh'), isTrue);
      expect(isRunnableFileName('budget.xlsm'), isTrue);
      expect(isRunnableFileName('photo.jpg'), isFalse);
      expect(isRunnableFileName('invoice.pdf'), isFalse);
      expect(isRunnableFileName('noext'), isFalse);
    });

    test('formatBytes', () {
      expect(formatBytes(0), '');
      expect(formatBytes(900), '900 B');
      expect(formatBytes(2048), '2 KB');
      expect(formatBytes(1536 * 1024), '1.5 MB');
      expect(formatBytes(30 * 1024 * 1024), '30 MB');
    });
  });

  group('AttachmentCache', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('att_cache'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('writes, finds and removes per account', () async {
      final cache = AttachmentCache(root: () async => dir);
      const meta = AttachmentMeta(fetchId: '2', fileName: 'a.pdf', mimeType: 'application/pdf');
      expect(await cache.find('acc', 'msg<1>/x', meta), isNull);
      final f = await cache.write('acc', 'msg<1>/x', meta, _bytes(10));
      expect(f.path, startsWith(dir.path));
      expect((await cache.find('acc', 'msg<1>/x', meta))!.readAsBytesSync(), _bytes(10));
      await cache.write('other', 'm', meta, _bytes(1));
      await cache.deleteAccount('acc');
      expect(await cache.find('acc', 'msg<1>/x', meta), isNull);
      expect(await cache.find('other', 'm', meta), isNotNull);
    });
  });
}
