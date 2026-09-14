enum ChatMode { online, offline }

extension ChatModeX on ChatMode {
  String get wire => this == ChatMode.online ? 'online' : 'offline';
  static ChatMode fromWire(String value) => value == 'online' ? ChatMode.online : ChatMode.offline;
}

enum ChatLanguage { english, malayalam }

extension ChatLanguageX on ChatLanguage {
  String get wire => this == ChatLanguage.malayalam ? 'malayalam' : 'english';
  String get shortLabel => this == ChatLanguage.malayalam ? 'ML' : 'EN';
}

class ChatRequest {
  final String message;
  final String sessionId;
  final ChatLanguage language;

  const ChatRequest({required this.message, required this.sessionId, this.language = ChatLanguage.english});

  Map<String, dynamic> toJson() => {'message': message, 'session_id': sessionId, 'language': language.wire};
}

class ChatResponse {
  final String reply;
  final ChatMode mode;

  const ChatResponse({required this.reply, required this.mode});

  factory ChatResponse.fromJson(Map<String, dynamic> json) => ChatResponse(
        reply: json['reply'] as String,
        mode: ChatModeX.fromWire(json['mode'] as String),
      );
}

class ChatMessage {
  final String id;
  final String text;
  final bool isUser;
  final ChatMode? mode;
  final DateTime timestamp;

  const ChatMessage({
    required this.id,
    required this.text,
    required this.isUser,
    this.mode,
    required this.timestamp,
  });
}
