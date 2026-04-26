enum MessageStatus {
  sending,
  sent,
  delivered,
}

class Message {
  final String id;
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final MessageStatus status;
  final String? imagePath;
  final String sessionId; // Added to group messages

  Message({
    required this.id,
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.status = MessageStatus.delivered,
    this.imagePath,
    required this.sessionId,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'] as String,
      text: json['text'] as String,
      isUser: json['isUser'] as bool,
      timestamp: DateTime.parse(json['timestamp'] as String),
      status: MessageStatus.values.firstWhere(
        (e) => e.toString() == 'MessageStatus.${json['status']}',
        orElse: () => MessageStatus.delivered,
      ),
      imagePath: json['imagePath'] as String?,
      sessionId: json['sessionId'] as String? ?? 'default', // Fallback for old messages
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'isUser': isUser,
      'timestamp': timestamp.toIso8601String(),
      'status': status.toString().split('.').last,
      'imagePath': imagePath,
      'sessionId': sessionId,
    };
  }

  Message copyWith({
    String? id,
    String? text,
    bool? isUser,
    DateTime? timestamp,
    MessageStatus? status,
    String? imagePath,
    String? sessionId,
  }) {
    return Message(
      id: id ?? this.id,
      text: text ?? this.text,
      isUser: isUser ?? this.isUser,
      timestamp: timestamp ?? this.timestamp,
      status: status ?? this.status,
      imagePath: imagePath ?? this.imagePath,
      sessionId: sessionId ?? this.sessionId,
    );
  }
}

