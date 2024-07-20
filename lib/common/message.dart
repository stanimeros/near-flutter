class Message{
  final String uid;
  final String friendUid;
  final String content;
  final DateTime timestamp;

  const Message({
    required this.uid,
    required this.friendUid,
    required this.content,
    required this.timestamp
  });
}