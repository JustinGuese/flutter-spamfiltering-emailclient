/// Date and sender helpers shared by the list, reader and sidebar.
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String _two(int n) => n.toString().padLeft(2, '0');

/// List column: today -> 14:12, this year -> 22 Nov, older -> 22 Nov 2025.
String formatListDate(DateTime when, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final d = when.toLocal();
  if (d.year == n.year && d.month == n.month && d.day == n.day) {
    return '${_two(d.hour)}:${_two(d.minute)}';
  }
  final base = '${d.day} ${_months[d.month - 1]}';
  return d.year == n.year ? base : '$base ${d.year}';
}

/// Reader header: Mon 23 Nov 2026 · 14:12
String formatFullDate(DateTime when) {
  final d = when.toLocal();
  return '${_days[d.weekday - 1]} ${d.day} ${_months[d.month - 1]} ${d.year} · ${_two(d.hour)}:${_two(d.minute)}';
}

/// `"Mara Lindqvist <mara@x.studio>"` -> (name: Mara Lindqvist, email: mara@x.studio).
({String name, String email}) parseSender(String raw) {
  final m = RegExp(r'^\s*"?([^"<]*?)"?\s*<([^>]+)>\s*$').firstMatch(raw);
  if (m != null) {
    final name = m.group(1)!.trim();
    final email = m.group(2)!.trim();
    return (name: name.isEmpty ? email.split('@').first : name, email: email);
  }
  final email = raw.trim();
  return (name: email.contains('@') ? email.split('@').first : email, email: email);
}

