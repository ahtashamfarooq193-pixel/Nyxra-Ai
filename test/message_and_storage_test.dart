import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:my_chatgpt/models/message.dart';
import 'package:my_chatgpt/services/storage_service.dart';

Message message(String id, String sessionId, {bool isError = false}) => Message(
  id: id,
  text: 'message-$id',
  isUser: true,
  timestamp: DateTime.utc(2026, 1, 1, 0, 0, int.parse(id)),
  sessionId: sessionId,
  isError: isError,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Message JSON round-trip preserves error state', () {
    final original = message('1', 'session-a', isError: true);
    final restored = Message.fromJson(original.toJson());

    expect(restored.id, original.id);
    expect(restored.sessionId, original.sessionId);
    expect(restored.isError, isTrue);
  });

  test('saving one guest session does not overwrite another session', () async {
    final storage = StorageService();
    await storage.saveSessionMessages([message('1', 'session-a')]);
    await storage.saveSessionMessages([message('2', 'session-b')]);

    final stored = await storage.loadMessages();
    expect(stored.map((item) => item.sessionId).toSet(), {
      'session-a',
      'session-b',
    });
  });

  test('updating a session replaces only that session branch', () async {
    final storage = StorageService();
    await storage.saveSessionMessages([
      message('1', 'session-a'),
      message('2', 'session-a'),
    ]);
    await storage.saveSessionMessages([message('3', 'session-b')]);
    await storage.saveSessionMessages([message('4', 'session-a')]);

    final stored = await storage.loadMessages();
    expect(stored.map((item) => item.id).toSet(), {'3', '4'});
  });
}
