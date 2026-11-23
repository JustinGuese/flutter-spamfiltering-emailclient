/// A parsed search box entry. The local search uses [match] (an FTS5 `MATCH`
/// expression) plus [where] (SQL on `messages` aliased `m`); the server search
/// uses [imapCriteria] (an IMAP `SEARCH` argument string).
class ParsedSearch {
  /// FTS5 expression, or null when the input has no text terms.
  final String? match;
  final List<String> where;
  final List<Object> args;

  /// IMAP `SEARCH` criteria for the same query; empty when there is none.
  final String imapCriteria;

  /// True when the user asked for spam explicitly (`is:spam`).
  final bool wantsSpam;

  /// False when the query depends on something only this device knows
  /// (`is:spam`, `is:newsletter` are our own verdicts), so the server cannot
  /// answer it.
  final bool remoteable;

  const ParsedSearch({
    this.match,
    this.where = const [],
    this.args = const [],
    this.imapCriteria = '',
    this.wantsSpam = false,
    this.remoteable = true,
  });

  bool get isEmpty => match == null && where.isEmpty;
}

final _token = RegExp(r'(?:([A-Za-z]+):)?(?:"([^"]*)"|(\S+))');
final _word = RegExp(r'[\p{L}\p{N}]+', unicode: true);
final _isoDate = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

const _columns = {'from': 'sender', 'to': 'recipients', 'subject': 'subject'};
const _imapKeys = {'from': 'FROM', 'to': 'TO', 'subject': 'SUBJECT'};
const _labels = {'spam': 'spam', 'newsletter': 'newsletter'};
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// Understands plain words (prefix-matched, all must appear), `"exact phrases"`
/// and these operators: `from:` `to:` `subject:` `is:unread|read|flagged|spam|
/// newsletter` `has:attachment` `before:YYYY-MM-DD` `after:YYYY-MM-DD`.
/// Anything it does not recognise is searched as plain text, so a typo never
/// yields an error.
ParsedSearch parseSearch(String input) {
  final terms = <String>[];
  final where = <String>[];
  final args = <Object>[];
  final imap = <String>[];
  var wantsSpam = false;
  var remoteable = true;

  String quote(String s) => '"${s.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';

  void text(String value, {required bool phrase, String? column, String imapKey = 'TEXT'}) {
    final words = _word.allMatches(value).map((m) => m.group(0)!).toList();
    if (words.isEmpty) return;
    final expr = '"${words.join(' ')}"${phrase ? '' : ' *'}';
    terms.add(column == null ? expr : '($column : $expr)');
    // Servers match substrings: a phrase as one string, loose words each.
    if (phrase) {
      imap.add('$imapKey ${quote(words.join(' '))}');
    } else {
      for (final w in words) {
        imap.add('$imapKey ${quote(w)}');
      }
    }
  }

  for (final m in _token.allMatches(input)) {
    final key = m.group(1)?.toLowerCase();
    final quoted = m.group(2);
    final value = (quoted ?? m.group(3) ?? '').trim();
    final raw = m.group(0)!;

    if (key != null && value.isNotEmpty) {
      if (_columns.containsKey(key)) {
        text(value, phrase: quoted != null, column: _columns[key], imapKey: _imapKeys[key]!);
        continue;
      }
      final v = value.toLowerCase();
      if (key == 'is' && v == 'unread') {
        where.add('m.is_read = 0');
        imap.add('UNSEEN');
        continue;
      }
      if (key == 'is' && v == 'read') {
        where.add('m.is_read = 1');
        imap.add('SEEN');
        continue;
      }
      if (key == 'is' && v == 'flagged') {
        where.add('m.is_flagged = 1');
        imap.add('FLAGGED');
        continue;
      }
      if (key == 'is' && _labels.containsKey(v)) {
        where.add('m.classification_label = ?');
        args.add(_labels[v]!);
        remoteable = false;
        if (v == 'spam') wantsSpam = true;
        continue;
      }
      if (key == 'has' && (v == 'attachment' || v == 'attachments')) {
        // IMAP has no such search; the local filter applies once it is imported.
        where.add('m.has_attachments = 1');
        continue;
      }
      final date = _isoDate.firstMatch(v);
      if ((key == 'before' || key == 'after') && date != null) {
        final month = int.parse(date.group(2)!);
        if (month >= 1 && month <= 12) {
          where.add(key == 'before' ? 'm.date < ?' : 'm.date >= ?');
          args.add(v);
          imap.add('${key == 'before' ? 'BEFORE' : 'SINCE'} ${int.parse(date.group(3)!)}-${_months[month - 1]}-${date.group(1)}');
          continue;
        }
      }
    }
    if (quoted != null && key == null) {
      text(quoted, phrase: true);
    } else {
      text(raw, phrase: false); // unknown operator or bare word
    }
  }

  return ParsedSearch(
    match: terms.isEmpty ? null : terms.join(' AND '),
    where: where,
    args: args,
    imapCriteria: imap.join(' '),
    wantsSpam: wantsSpam,
    remoteable: remoteable,
  );
}
