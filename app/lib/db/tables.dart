import 'package:drift/drift.dart';

/// C3 Drift schema: accounts, folders, messages, bodies, contacts,
/// classifications, tokens, blocklist_entries, settings.

class Accounts extends Table {
  TextColumn get id => text()();
  TextColumn get email => text()();
  TextColumn get displayName => text()();
  TextColumn get imapHost => text()();
  IntColumn get imapPort => integer()();
  TextColumn get smtpHost => text()();
  IntColumn get smtpPort => integer()();
  TextColumn get authType => text().withDefault(const Constant('password'))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class Folders extends Table {
  TextColumn get id => text()();
  TextColumn get accountId => text()();
  TextColumn get name => text()();
  TextColumn get serverPath => text()();
  TextColumn get specialUse => text().nullable()(); // inbox, sent, drafts, trash, junk, archive
  IntColumn get uidValidity => integer().nullable()();
  IntColumn get lastSeenUid => integer().nullable()();
  IntColumn get unreadCount => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

class Messages extends Table {
  TextColumn get id => text()();
  TextColumn get accountId => text()();
  TextColumn get folderId => text()();
  IntColumn get uid => integer()();
  TextColumn get messageId => text().nullable()();
  TextColumn get subject => text()();
  TextColumn get sender => text()();
  TextColumn get senderDomain => text().nullable()();
  TextColumn get recipientAddrs => text()();
  DateTimeColumn get date => dateTime()();
  TextColumn get snippet => text()();
  BoolColumn get isRead => boolean().withDefault(const Constant(false))();
  BoolColumn get isFlagged => boolean().withDefault(const Constant(false))();
  BoolColumn get hasAttachments => boolean().withDefault(const Constant(false))();
  TextColumn get classificationLabel => text().withDefault(const Constant('inbox'))();
  RealColumn get spamScore => real().withDefault(const Constant(0.0))();

  @override
  Set<Column> get primaryKey => {id};
}

class Bodies extends Table {
  TextColumn get messageId => text()();
  TextColumn get textBody => text().nullable()();
  TextColumn get htmlBody => text().nullable()();
  TextColumn get sanitizedHtml => text().nullable()();
  BoolColumn get remoteImagesBlocked => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {messageId};
}

class Contacts extends Table {
  TextColumn get id => text()();
  TextColumn get email => text()();
  TextColumn get name => text().nullable()();
  IntColumn get trustLevel => integer().withDefault(const Constant(0))();
  BoolColumn get alwaysAllowImages => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class Classifications extends Table {
  TextColumn get messageId => text()();
  TextColumn get label => text()();
  RealColumn get spamScore => real()();
  TextColumn get evidenceJson => text()();
  DateTimeColumn get classifiedAt => dateTime()();
  BoolColumn get userOverridden => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {messageId};
}

class Tokens extends Table {
  Int64Column get hash => int64()();
  IntColumn get spam => integer().withDefault(const Constant(0))();
  IntColumn get ham => integer().withDefault(const Constant(0))();
  IntColumn get newsletter => integer().withDefault(const Constant(0))();
  IntColumn get inbox => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {hash};
}

class BlocklistEntries extends Table {
  TextColumn get id => text()();
  TextColumn get type => text()(); // body_band, url_hash, sender_domain
  Int64Column get hashValue => int64()();
  DateTimeColumn get addedAt => dateTime()();
  DateTimeColumn get expiresAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}
