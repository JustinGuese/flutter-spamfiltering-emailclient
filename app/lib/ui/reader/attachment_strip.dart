import 'dart:async';
import 'dart:io';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:df_theme/df_theme.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import '../../app/log.dart';
import '../../app/ui_strings.dart';
import '../../mail/attachments.dart';
import '../../mail/sync_engine.dart';
import '../../theme/app_type.dart';

/// The files of one received message. Tapping one downloads it from the mail
/// server (once; it is kept on the device afterwards) and opens it; the save
/// button writes a copy where the user chooses.
class AttachmentStrip extends ConsumerStatefulWidget {
  final String messageId;

  /// Hands a downloaded file to the operating system. Replaced in tests, which
  /// must never launch a real program.
  final Future<OpenResult> Function(String path) opener;

  const AttachmentStrip({super.key, required this.messageId, this.opener = _openWithSystem});

  @override
  ConsumerState<AttachmentStrip> createState() => _AttachmentStripState();
}

class _AttachmentStripState extends ConsumerState<AttachmentStrip> {
  final _busy = <int>{};
  List<AttachmentMeta>? _files;
  Object? _listError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(AttachmentStrip old) {
    super.didUpdateWidget(old);
    if (old.messageId != widget.messageId) {
      _files = null;
      _listError = null;
      _load();
    }
  }

  Future<void> _load() async {
    final id = widget.messageId;
    try {
      final files = await ref.read(syncEngineProvider).attachmentsOf(id);
      if (mounted && id == widget.messageId) setState(() => _files = files);
    } catch (e, st) {
      logError('attachment list $id', e, st);
      if (mounted && id == widget.messageId) setState(() => _listError = e);
    }
  }

  String _why(Object e) => e is StateError ? e.message : e.toString();

  void _say(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _open(AttachmentMeta a) async {
    if (isRunnableFileName(a.fileName)) {
      final save = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text(UiStrings.attachmentRunnableTitle),
          content: Text(UiStrings.attachmentRunnableBody.replaceAll('{name}', a.fileName)),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text(UiStrings.attachmentCancel)),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text(UiStrings.attachmentSave)),
          ],
        ),
      );
      if (save == true) await _save(a);
      return;
    }
    final file = await _download(a);
    if (file == null) return;
    try {
      final result = await widget.opener(file.path);
      if (result.type == ResultType.done) return;
      logInfo('attachment', 'open ${a.fileName}: ${result.type} ${result.message}');
    } catch (e, st) {
      logError('open attachment ${a.fileName}', e, st); // e.g. no xdg-open on a bare Linux install
    }
    _say(UiStrings.attachmentNoApp.replaceAll('{name}', a.fileName));
  }

  Future<void> _save(AttachmentMeta a) async {
    final file = await _download(a);
    if (file == null) return;
    try {
      final saved = await FilePicker.saveFile(
        fileName: a.fileName,
        bytes: await file.readAsBytes(),
        mimeType: a.mimeType,
        dialogTitle: UiStrings.attachmentSave,
      );
      if (saved != null) _say(UiStrings.attachmentSaved.replaceAll('{path}', saved.scheme == 'file' ? saved.toFilePath() : a.fileName));
    } catch (e, st) {
      logError('save attachment', e, st);
      _say(UiStrings.attachmentDownloadFailed.replaceAll('{name}', a.fileName).replaceAll('{error}', _why(e)));
    }
  }

  Future<File?> _download(AttachmentMeta a) async {
    final id = a.id;
    if (id == null || _busy.contains(id)) return null;
    setState(() => _busy.add(id));
    try {
      return await ref.read(syncEngineProvider).downloadAttachment(id);
    } catch (e, st) {
      logError('download attachment $id', e, st);
      _say(UiStrings.attachmentDownloadFailed.replaceAll('{name}', a.fileName).replaceAll('{error}', _why(e)));
      return null;
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    // A sync may add or replace rows (the list is read once, not per frame).
    // Only once a first load has finished, so a failing server is not retried on every sync tick.
    ref.listen(mailRevisionProvider, (_, _) {
      if (_files != null) _load();
    });
    final c = context.df.colors;
    final files = _files;

    Widget frame(Widget child) => Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: c.surfaceSunken,
            borderRadius: BorderRadius.circular(context.df.shape.md),
            border: Border.all(color: c.hairline),
          ),
          child: child,
        );

    if (_listError != null && files == null) {
      return frame(Row(children: [
        Expanded(child: Text(UiStrings.attachmentsFailed.replaceAll('{error}', _why(_listError!)), style: AppType.ui(c.textSecondary, size: 13))),
        TextButton(
          onPressed: () {
            setState(() => _listError = null);
            _load();
          },
          child: const Text(UiStrings.attachmentRetry),
        ),
      ]));
    }
    if (files == null) {
      return frame(Row(children: [
        const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 10),
        Text(UiStrings.attachmentsLoading, style: AppType.ui(c.textTertiary, size: 13)),
      ]));
    }
    if (files.isEmpty) return const SizedBox.shrink();

    return frame(Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${UiStrings.attachmentsTitle.toUpperCase()} · ${files.length}',
            style: AppType.mono(c.textTertiary, size: 10.5, weight: FontWeight.w600, letterSpacing: 1.3)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [for (final a in files) _chip(a)]),
      ],
    ));
  }

  Widget _chip(AttachmentMeta a) {
    final c = context.df.colors;
    final busy = _busy.contains(a.id);
    final size = formatBytes(a.size);
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.df.shape.md),
        side: BorderSide(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(
            child: InkWell(
              onTap: busy ? null : () => _open(a),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  busy
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(_iconFor(a.mimeType), size: 20, color: c.brand.deep),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(a.fileName, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.ui(c.textPrimary, size: 13.5, weight: FontWeight.w600)),
                      if (size.isNotEmpty) Text(size, style: AppType.mono(c.textTertiary, size: 11)),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
          IconButton(
            tooltip: UiStrings.attachmentSave,
            icon: const Icon(Icons.download_rounded, size: 18),
            visualDensity: VisualDensity.compact,
            onPressed: busy ? null : () => _save(a),
          ),
        ]),
      ),
    );
  }
}

Future<OpenResult> _openWithSystem(String path) => OpenFilex.open(path);

IconData _iconFor(String mime) {
  final m = mime.toLowerCase();
  if (m.startsWith('image/')) return Icons.image_outlined;
  if (m.startsWith('audio/')) return Icons.audiotrack_outlined;
  if (m.startsWith('video/')) return Icons.movie_outlined;
  if (m == 'application/pdf') return Icons.picture_as_pdf_outlined;
  if (m.contains('zip') || m.contains('compressed') || m.contains('tar') || m.contains('rar') || m.contains('7z')) return Icons.folder_zip_outlined;
  if (m.startsWith('text/') || m.contains('word') || m.contains('document')) return Icons.description_outlined;
  if (m.contains('sheet') || m.contains('excel') || m.contains('csv')) return Icons.table_chart_outlined;
  if (m == 'message/rfc822') return Icons.mail_outline_rounded;
  return Icons.insert_drive_file_outlined;
}
