import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/message.dart';

class StorageService {
  static const String _messagesKey = 'chat_messages';
  static const String _guestTokensKey = 'guest_tokens';
  static const String _guestResetKey = 'guest_tokens_reset_day';
  static const String _guestImageCountKey = 'guest_image_count';
  static const String _guestImageResetKey = 'guest_image_reset_day';

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

  /// Local token balance for guests (not signed in), mirroring the daily reset
  /// that [FirestoreService.checkAndResetDailyTokens] does for signed-in users.
  /// Without this the balance would live only in memory and every app restart
  /// would hand out a fresh allowance.
  Future<int> loadGuestTokens(int dailyAllowance) async {
    final prefs = await SharedPreferences.getInstance();
    final today = _todayKey();

    if (prefs.getString(_guestResetKey) != today) {
      await prefs.setString(_guestResetKey, today);
      await prefs.setInt(_guestTokensKey, dailyAllowance);
      return dailyAllowance;
    }

    return prefs.getInt(_guestTokensKey) ?? dailyAllowance;
  }

  Future<void> saveGuestTokens(int tokens) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_guestTokensKey, tokens);
    await prefs.setString(_guestResetKey, _todayKey());
  }

  Future<int> loadGuestImageCount() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _todayKey();
    if (prefs.getString(_guestImageResetKey) != today) {
      await prefs.setString(_guestImageResetKey, today);
      await prefs.setInt(_guestImageCountKey, 0);
      return 0;
    }
    return prefs.getInt(_guestImageCountKey) ?? 0;
  }

  Future<bool> tryReserveGuestImage(int dailyLimit) async {
    final prefs = await SharedPreferences.getInstance();
    final used = await loadGuestImageCount();
    if (used >= dailyLimit) return false;
    await prefs.setInt(_guestImageCountKey, used + 1);
    await prefs.setString(_guestImageResetKey, _todayKey());
    return true;
  }

  Future<void> releaseGuestImage() async {
    final prefs = await SharedPreferences.getInstance();
    final used = await loadGuestImageCount();
    if (used > 0) await prefs.setInt(_guestImageCountKey, used - 1);
  }

  String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month}-${now.day}';
  }
}
