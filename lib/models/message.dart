enum MessageStatus { sending, sent, delivered }

class Message {
  final String id;
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final MessageStatus status;
  final String? imagePath;
  final String? documentBase64;
  final String? documentName;
  final String sessionId; // Added to group messages
  final bool isError;

  Message({
    required this.id,
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.status = MessageStatus.delivered,
    this.imagePath,
    this.documentBase64,
    this.documentName,
    required this.sessionId,
    this.isError = false,
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
      documentBase64: json['documentBase64'] as String?,
      documentName: json['documentName'] as String?,
      sessionId:
          json['sessionId'] as String? ??
          'default', // Fallback for old messages
      isError: json['isError'] as bool? ?? false,
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
      'documentBase64': documentBase64,
      'documentName': documentName,
      'sessionId': sessionId,
      'isError': isError,
    };
  }

  Message copyWith({
    String? id,
    String? text,
    bool? isUser,
    DateTime? timestamp,
    MessageStatus? status,
    String? imagePath,
    String? documentBase64,
    String? documentName,
    String? sessionId,
    bool? isError,
  }) {
    return Message(
      id: id ?? this.id,
      text: text ?? this.text,
      isUser: isUser ?? this.isUser,
      timestamp: timestamp ?? this.timestamp,
      status: status ?? this.status,
      imagePath: imagePath ?? this.imagePath,
      documentBase64: documentBase64 ?? this.documentBase64,
      documentName: documentName ?? this.documentName,
      sessionId: sessionId ?? this.sessionId,
      isError: isError ?? this.isError,
    );
  }
}
