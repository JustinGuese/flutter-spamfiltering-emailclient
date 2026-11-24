enum NotifyMode { off, instant, every5min, hourly }

class NewMail {
  final String messageId;
  final String accountId;
  final String sender;
  final String subject;
  final DateTime receivedAt;

  const NewMail({
    required this.messageId,
    required this.accountId,
    required this.sender,
    required this.subject,
    required this.receivedAt,
  });
}

abstract class NotificationSink {
  Future<void> show(int id, String title, String body, {String? payload});
}
