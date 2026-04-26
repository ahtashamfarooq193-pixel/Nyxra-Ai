import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/message.dart';

class StorageService {
  static const String _messagesKey = 'chat_messages';

  Future<void> saveMessages(List<Message> messages) async {
    final prefs = await SharedPreferences.getInstance();
    final String encodedData = jsonEncode(
      messages.map((m) => m.toJson()).toList(),
    );
    await prefs.setString(_messagesKey, encodedData);
  }

  Future<List<Message>> loadMessages() async {
    final prefs = await SharedPreferences.getInstance();
    final String? encodedData = prefs.getString(_messagesKey);
    
    if (encodedData == null) return [];

    try {
      final List<dynamic> decodedData = jsonDecode(encodedData);
      return decodedData
          .map((item) => Message.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('Error loading messages: $e');
      return [];
    }
  }

  Future<void> clearMessages() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_messagesKey);
  }

  Future<void> deleteSession(String sessionId) async {
    final messages = await loadMessages();
    messages.removeWhere((m) => m.sessionId == sessionId);
    await saveMessages(messages);
  }
}
