import '../../db/database.dart';

/// The folder a list shows when nothing is selected yet: the Inbox.
String? effectiveFolderId(AppDatabase db, String? selected) {
  if (selected != null) return selected;
  final row = db.db.select("SELECT id FROM folders WHERE special_use = 'inbox' LIMIT 1").firstOrNull;
  return row?['id'] as String?;
}

String groupThousands(int n) {
  final s = n.toString();
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
    out.write(s[i]);
  }
  return out.toString();
}

/// Real numbers only: everything the "Your filter" card shows is counted from the
/// local database.
({int caught, int learned, int community}) filterStats(AppDatabase db) {
  int count(String sql) => (db.db.select(sql).first.values.first as int?) ?? 0;
  return (
    caught: count("SELECT COUNT(*) FROM classifications WHERE label = 'spam'"),
    learned: count('SELECT COUNT(*) FROM tokens'),
    community: count('SELECT COUNT(*) FROM blocklist_entries'),
  );
}
