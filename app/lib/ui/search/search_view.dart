import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:df_theme/df_theme.dart';
import '../../app/strings.dart';
import '../../db/database.dart';
import '../../mail/sync_engine.dart';
import '../../platform/platform_services.dart';
import '../../search/search_query.dart';
import '../../search/search_service.dart';
import '../../theme/app_type.dart';
import '../common/app_parts.dart';
import '../mailbox/message_row.dart';
import '../reader/reader_view.dart';

const _resultLimit = 100;

enum _ServerState { idle, searching, done, failed }

/// The Search tab: one box over the local full-text index, results on the left,
/// the reader on the right (or full screen on narrow layouts).
class SearchView extends ConsumerStatefulWidget {
  const SearchView({super.key});

  @override
  ConsumerState<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends ConsumerState<SearchView> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _includeSpam = false;

  Timer? _debounce;
  int _runId = 0; // a newer query invalidates an older server answer
  _ServerState _server = _ServerState.idle;
  int _serverAdded = 0;
  String? _serverError;

  /// Local results update on every keystroke; the server is asked once typing
  /// pauses. Hits it returns are stored locally, so the same list then shows them.
  void _onQueryChanged() {
    setState(() {});
    _debounce?.cancel();
    final q = _controller.text.trim();
    if (q.length < 2 || !parseSearch(q).remoteable) {
      _runId++;
      setState(() => _server = _ServerState.idle);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 700), () => _searchServer(q));
  }

  Future<void> _searchServer(String q) async {
    final id = ++_runId;
    setState(() => _server = _ServerState.searching);
    var state = _ServerState.failed;
    var added = 0;
    String? error;
    try {
      final r = await ref.read(syncEngineProvider).searchRemote(q);
      added = r.imported;
      error = r.error;
      state = r.failed > 0 && r.imported == 0 ? _ServerState.failed : _ServerState.done;
    } catch (e) {
      error = e.toString();
    }
    if (!mounted || id != _runId) return;
    setState(() {
      _server = state;
      _serverAdded = added;
      _serverError = error;
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(mailRevisionProvider); // re-run after sync or a verdict
    final selectedId = ref.watch(selectedMessageIdProvider);
    final split = MediaQuery.sizeOf(context).width >= 700;

    final list = _ResultsPane(
      controller: _controller,
      focus: _focus,
      includeSpam: _includeSpam,
      selectedId: selectedId,
      server: _server,
      serverAdded: _serverAdded,
      serverError: _serverError,
      onRetry: () => _searchServer(_controller.text.trim()),
      onChanged: _onQueryChanged,
      onToggleSpam: () => setState(() => _includeSpam = !_includeSpam),
    );
    final reader = ReaderView(messageId: selectedId);

    if (split) {
      final c = context.df.colors;
      return Row(children: [
        SizedBox(width: 380, child: list),
        VerticalDivider(width: 1, thickness: 1, color: c.hairline),
        Expanded(child: reader),
      ]);
    }
    if (selectedId != null) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) ref.read(selectedMessageIdProvider.notifier).set(null);
        },
        child: reader,
      );
    }
    return list;
  }
}

class _ResultsPane extends ConsumerWidget {
  final TextEditingController controller;
  final FocusNode focus;
  final bool includeSpam;
  final String? selectedId;
  final VoidCallback onChanged;
  final VoidCallback onToggleSpam;
  final _ServerState server;
  final int serverAdded;
  final String? serverError;
  final VoidCallback onRetry;

  const _ResultsPane({
    required this.server,
    required this.serverAdded,
    required this.serverError,
    required this.onRetry,
    required this.controller,
    required this.focus,
    required this.includeSpam,
    required this.selectedId,
    required this.onChanged,
    required this.onToggleSpam,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.df.colors;
    final db = ref.watch(databaseProvider);
    final isComfortable = ref.watch(listDensityComfortableProvider);
    final query = controller.text.trim();
    final results = searchMessages(db, query, includeSpam: includeSpam, limit: _resultLimit);

    Widget body;
    if (query.isEmpty) {
      body = _Prompt(onExample: (e) {
        controller.text = e;
        controller.selection = TextSelection.collapsed(offset: e.length);
        onChanged();
      });
    } else if (results.isEmpty && server == _ServerState.searching) {
      body = LedgerPaper(
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(height: 14),
            Text(AppStrings.searchServerSearching, style: AppType.ui(c.textTertiary, size: 13)),
          ]),
        ),
      );
    } else if (results.isEmpty) {
      body = LedgerPaper(
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(AppStrings.searchNoResultsTitle,
                style: AppType.display(c.textTertiary, size: 30, weight: 500, italic: true)),
            const SizedBox(height: 6),
            Text(AppStrings.searchNoResultsBody, style: AppType.ui(c.textTertiary, size: 13)),
          ]),
        ),
      );
    } else {
      body = ListView.builder(
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: results.length,
        itemBuilder: (context, i) {
          final m = results[i];
          return MessageRow(
            message: m,
            isSelected: m.id == selectedId,
            isComfortable: isComfortable,
            onTap: () => ref.read(selectedMessageIdProvider.notifier).set(m.id),
          );
        },
      );
    }

    return Scaffold(
      backgroundColor: c.canvas,
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
            child: TextField(
              controller: controller,
              focusNode: focus,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: (_) => onChanged(),
              style: AppType.ui(c.textPrimary, size: 15),
              decoration: InputDecoration(
                hintText: AppStrings.searchHint,
                hintStyle: AppType.ui(c.textTertiary, size: 15),
                prefixIcon: Icon(Icons.search, size: 20, color: c.textSecondary),
                suffixIcon: query.isEmpty
                    ? null
                    : IconButton(
                        icon: Icon(Icons.close, size: 18, color: c.textSecondary),
                        tooltip: AppStrings.searchClear,
                        onPressed: () {
                          controller.clear();
                          onChanged();
                          focus.requestFocus();
                        },
                      ),
                filled: true,
                fillColor: c.surfaceSunken,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(context.df.shape.pill),
                  borderSide: BorderSide(color: c.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(context.df.shape.pill),
                  borderSide: BorderSide(color: c.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(context.df.shape.pill),
                  borderSide: BorderSide(color: c.brand.deep, width: 1.5),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 20, 10),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  query.isEmpty || results.isEmpty ? '' : AppStrings.searchResultCount(results.length, _resultLimit),
                  style: AppType.mono(c.textTertiary, size: 11.5),
                ),
                if (query.isNotEmpty) _ServerStatus(state: server, added: serverAdded, error: serverError, onRetry: onRetry),
              ]),
            ),
            FilterChip(
              label: Text(AppStrings.searchIncludeSpam,
                  style: AppType.ui(includeSpam ? c.canvas : c.textSecondary, size: 12.5, weight: FontWeight.w600)),
              selected: includeSpam,
              showCheckmark: false,
              selectedColor: c.textPrimary,
              backgroundColor: Colors.transparent,
              side: BorderSide(color: includeSpam ? c.textPrimary : c.border),
              shape: const StadiumBorder(),
              onSelected: (_) => onToggleSpam(),
            ),
          ]),
        ),
        Divider(height: 1, color: c.hairline),
        Expanded(child: body),
      ]),
    );
  }
}

class _Prompt extends StatelessWidget {
  final ValueChanged<String> onExample;
  const _Prompt({required this.onExample});

  @override
  Widget build(BuildContext context) {
    final c = context.df.colors;
    return LedgerPaper(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(AppStrings.searchPromptTitle, style: AppType.display(c.textTertiary, size: 30, weight: 500, italic: true)),
          const SizedBox(height: 8),
          Text(AppStrings.searchPromptBody, style: AppType.ui(c.textTertiary, size: 13)),
          const SizedBox(height: 24),
          Text(AppStrings.searchTryTitle, style: AppType.mono(c.textTertiary, size: 11.5)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final e in AppStrings.searchExamples)
              ActionChip(
                label: Text(e, style: AppType.mono(c.textSecondary, size: 12)),
                backgroundColor: Colors.transparent,
                side: BorderSide(color: c.border),
                shape: const StadiumBorder(),
                onPressed: () => onExample(e),
              ),
          ]),
        ]),
      ),
    );
  }
}

class _ServerStatus extends StatelessWidget {
  final _ServerState state;
  final int added;
  final String? error;
  final VoidCallback onRetry;
  const _ServerStatus({required this.state, required this.added, required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final c = context.df.colors;
    final style = AppType.mono(state == _ServerState.failed ? c.error.deep : c.textTertiary, size: 11.5);
    switch (state) {
      case _ServerState.idle:
        return const SizedBox.shrink();
      case _ServerState.searching:
        return Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5)),
            const SizedBox(width: 6),
            Flexible(child: Text(AppStrings.searchServerSearching, style: style, overflow: TextOverflow.ellipsis)),
          ]),
        );
      case _ServerState.done:
        return Text(added > 0 ? AppStrings.searchServerAdded(added) : AppStrings.searchServerNone, style: style, overflow: TextOverflow.ellipsis);
      case _ServerState.failed:
        return Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(AppStrings.searchServerFailed(error), style: style),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(minimumSize: Size.zero, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2)),
            child: Text(AppStrings.searchServerRetry, style: AppType.mono(c.brand.deep, size: 11.5, weight: FontWeight.w600)),
          ),
        ]);
    }
  }
}
