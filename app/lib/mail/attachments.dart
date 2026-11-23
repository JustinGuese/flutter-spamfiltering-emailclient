import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:enough_mail/enough_mail.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Largest total size of the files on one outgoing message. Base64 adds a third
/// on the wire, and the common 25 MB server limit counts the encoded size, so
/// this keeps a message under it. A server with a lower limit still rejects the
/// send with its own error, which the compose window shows.
const maxOutgoingAttachmentBytes = 18 * 1024 * 1024;

/// One attachment of a stored message, as listed in the `attachments` table.
class AttachmentMeta {
  /// Row id in `attachments`; null before it is stored.
  final int? id;

  /// The IMAP part number of the attachment inside the message (`2`, `1.2`).
  final String fetchId;
  final String fileName;
  final String mimeType;

  /// Bytes. Approximate until the file is downloaded (0 when unknown).
  final int size;

  const AttachmentMeta({
    this.id,
    required this.fetchId,
    required this.fileName,
    required this.mimeType,
    this.size = 0,
  });
}

/// The attachments of a fully fetched [msg]: parts a person would call "a file"
/// rather than part of the text.
///
/// Counted: parts with `Content-Disposition: attachment`; named non-text parts
/// without a disposition (older mailers); named inline files; attached mails
/// (`message/rfc822`). Not counted: the text/HTML body and images embedded in
/// the HTML by `Content-ID` (signature logos), which are not files to open.
///
/// The `fetchId` numbering is the one `MimeMessage.getPart` resolves, so
/// [partOf] finds the bytes again in a re-fetched copy of the same message.
List<AttachmentMeta> extractAttachments(MimeMessage msg) {
  final out = <AttachmentMeta>[];
  void walk(MimePart part, String? fetchId) {
    final type = part.getHeaderContentType();
    final media = type?.mediaType;
    final children = part.parts ?? const <MimePart>[];
    final isMail = media?.sub == MediaSubtype.messageRfc822;
    if (children.isNotEmpty && !isMail) {
      for (var i = 0; i < children.length; i++) {
        walk(children[i], fetchId == null ? '${i + 1}' : '$fetchId.${i + 1}');
      }
      return;
    }
    if (fetchId == null || media?.top == MediaToptype.multipart) return;

    final disp = part.getHeaderContentDisposition();
    final name = _decodedName(part, disp, type);
    final embedded = (part.getHeaderValue('content-id') ?? '').trim().isNotEmpty;
    final isText = media?.top == MediaToptype.text;
    final named = name != null && name.isNotEmpty;

    final isAttachment = switch (disp?.disposition) {
      ContentDisposition.attachment => true,
      ContentDisposition.inline => named && !isText && !embedded,
      _ => isMail || (named && !isText && !embedded),
    };
    if (!isAttachment) return;

    out.add(AttachmentMeta(
      fetchId: fetchId,
      fileName: safeFileName(name, fallback: isMail ? 'message.eml' : 'attachment'),
      mimeType: media?.text ?? 'application/octet-stream',
      size: disp?.size ?? _estimatedSize(part),
    ));
  }

  final top = msg.parts ?? const <MimePart>[];
  if (top.isEmpty) {
    // A message that is itself one file (no multipart wrapper) is IMAP part 1.
    final disp = msg.getHeaderContentDisposition();
    final type = msg.getHeaderContentType();
    if (disp?.disposition == ContentDisposition.attachment && type?.mediaType.top != MediaToptype.text) {
      out.add(AttachmentMeta(
        fetchId: '1',
        fileName: safeFileName(_decodedName(msg, disp, type), fallback: 'attachment'),
        mimeType: type?.mediaType.text ?? 'application/octet-stream',
        size: disp?.size ?? _estimatedSize(msg),
      ));
    }
  } else {
    walk(msg, null);
  }
  return out;
}

/// The part of [msg] with this [fetchId], or null when it is not in the message.
MimePart? partOf(MimeMessage msg, String fetchId) {
  if ((msg.parts ?? const []).isEmpty) return fetchId == '1' ? msg : null;
  return msg.getPart(fetchId);
}

String? _decodedName(MimePart part, ContentDispositionHeader? disp, ContentTypeHeader? type) {
  final raw = disp?.filename ?? type?.parameters['name'];
  if (raw == null) return null;
  try {
    return MailCodec.decodeHeader(raw);
  } catch (_) {
    return raw;
  }
}

/// Decoded size from the encoded text length; avoids base64-decoding every
/// attachment of every message during sync just to show a number.
int _estimatedSize(MimePart part) {
  final data = part.mimeData;
  final encoded = switch (data) {
    TextMimeData() => data.text.length,
    BinaryMimeData() => data.data.length,
    _ => 0,
  };
  final base64 = part.getHeaderValue('content-transfer-encoding')?.trim().toLowerCase() == 'base64';
  return base64 ? encoded * 3 ~/ 4 : encoded;
}

/// A file name that is safe to create on disk: no directories, no control or
/// reserved characters, no leading dots, bounded length. Attachment names come
/// from the sender, so `../../.bashrc` and `CON` are expected inputs.
String safeFileName(String? name, {String fallback = 'attachment'}) {
  var s = (name ?? '').replaceAll('\\', '/').split('/').last;
  s = s.replaceAll(RegExp(r'[\x00-\x1f\x7f<>:"|?*]'), '_').trim();
  s = s.replaceFirst(RegExp(r'^\.+'), '').replaceFirst(RegExp(r'[. ]+$'), '');
  if (RegExp(r'^(con|prn|aux|nul|com\d|lpt\d)(\..*)?$', caseSensitive: false).hasMatch(s)) s = '_$s';
  if (s.isEmpty) return fallback;
  if (s.length > 120) {
    final ext = p.extension(s);
    final keep = ext.length <= 12 ? ext : '';
    s = s.substring(0, 120 - keep.length) + keep;
  }
  return s;
}

/// Extensions the operating system would *run* (or hand to an interpreter) when
/// opened. A mail client must not do that on a tap.
const _runnableExtensions = {
  'exe', 'msi', 'bat', 'cmd', 'com', 'scr', 'pif', 'ps1', 'psm1', 'vbs', 'vbe', 'js', 'jse', 'wsf', 'wsh',
  'hta', 'cpl', 'lnk', 'reg', 'jar', 'sh', 'bash', 'command', 'desktop', 'app', 'apk', 'dmg', 'pkg',
  'appimage', 'run', 'bin', 'docm', 'xlsm', 'pptm', 'iso', 'url', 'scpt', 'workflow', 'py',
};

/// True when opening [fileName] could execute code. The reader then offers
/// "Save as…" instead of opening it.
bool isRunnableFileName(String fileName) {
  final ext = p.extension(fileName).toLowerCase().replaceFirst('.', '');
  return _runnableExtensions.contains(ext);
}

/// "1.4 MB", "212 KB", "" for unknown.
String formatBytes(int bytes) {
  if (bytes <= 0) return '';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  final mb = bytes / (1024 * 1024);
  return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
}

/// A file attached to a message being written. The bytes are read at send time
/// ([load]), so a picked file costs nothing until it is sent and a forwarded
/// attachment is downloaded only if the forward is actually sent.
class OutgoingAttachment {
  final String fileName;
  final String mimeType;

  /// Bytes, as far as known when it was added (0 when the source did not say).
  final int size;
  final Future<Uint8List> Function() load;

  const OutgoingAttachment({
    required this.fileName,
    required this.mimeType,
    required this.size,
    required this.load,
  });

  /// From a name given by the user's file system or a sender: sanitised, with
  /// the media type guessed from the extension unless [mimeType] is known.
  factory OutgoingAttachment.named(
    String name, {
    required int size,
    required Future<Uint8List> Function() load,
    String? mimeType,
  }) {
    final safe = safeFileName(p.basename(name.replaceAll('\\', '/')));
    return OutgoingAttachment(
      fileName: safe,
      mimeType: mimeType ?? MediaType.guessFromFileName(safe).text,
      size: size,
      load: load,
    );
  }
}

/// An attachment with its bytes loaded, ready to put into a MIME message.
class LoadedAttachment {
  final String fileName;
  final String mimeType;
  final Uint8List bytes;
  const LoadedAttachment(this.fileName, this.mimeType, this.bytes);
}

/// Downloaded attachments, one file each, under
/// `<app support>/attachments/<account id>/<hash>/<file name>`.
///
/// Plain files on the device, like the mail cache itself; removing the account
/// removes its folder.
class AttachmentCache {
  final Future<Directory> Function() _root;

  AttachmentCache({Future<Directory> Function()? root})
      : _root = root ?? (() async => Directory(p.join((await getApplicationSupportDirectory()).path, 'attachments')));

  String _key(String messageId, String fetchId) => sha1.convert('$messageId|$fetchId'.codeUnits).toString();

  Future<Directory> _dir(String accountId, String messageId, String fetchId) async =>
      Directory(p.join((await _root()).path, safeFileName(accountId), _key(messageId, fetchId)));

  /// The cached file, or null when it has not been downloaded.
  Future<File?> find(String accountId, String messageId, AttachmentMeta a) async {
    final f = File(p.join((await _dir(accountId, messageId, a.fetchId)).path, a.fileName));
    return await f.exists() ? f : null;
  }

  Future<File> write(String accountId, String messageId, AttachmentMeta a, Uint8List bytes) async {
    final dir = await _dir(accountId, messageId, a.fetchId);
    await dir.create(recursive: true);
    final f = File(p.join(dir.path, a.fileName));
    await f.writeAsBytes(bytes, flush: true);
    return f;
  }

  Future<void> deleteAccount(String accountId) async {
    final dir = Directory(p.join((await _root()).path, safeFileName(accountId)));
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}
