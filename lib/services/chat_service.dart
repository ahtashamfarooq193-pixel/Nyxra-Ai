import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../models/message.dart';

class ChatService {
  static const String _backendBaseUrl = String.fromEnvironment(
    'BACKEND_BASE_URL',
    defaultValue: 'https://nyxra-ai.vercel.app',
  );

  Stream<String> getAIResponseStream(
    String userMessage,
    List<Message> conversationHistory, {
    String? imagePath,
    Uint8List? imageBytes,
  }) async* {
    try {
      final response = await http.post(
        Uri.parse('$_backendBaseUrl/api/chat'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
        'userMessage': userMessage,
        'conversationHistory': conversationHistory
            .map(
              (message) => {
                'text': message.text,
                'isUser': message.isUser,
              },
            )
            .toList(),
        'imageBase64': imageBytes == null ? null : base64Encode(imageBytes),
        'imagePath': imagePath,
      }),
      ).timeout(const Duration(seconds: 60));

      if (response.statusCode != 200) {
        yield '❌ **Server Error:** ${response.statusCode}';
        return;
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final text = decoded['text']?.toString().trim() ?? '';
      if (text.isEmpty) {
        yield '❌ **Empty response:** Please try again.';
        return;
      }

      for (final chunk in _chunkResponse(text)) {
        yield chunk;
        await Future.delayed(const Duration(milliseconds: 18));
      }
    } catch (e) {
      yield '❌ **Connection Error:** Failed to connect to secure AI service. Please try again.';
    }
  }

  List<String> _chunkResponse(String text) {
    final chunks = <String>[];
    const chunkSize = 24;
    for (int i = 0; i < text.length; i += chunkSize) {
      final end = (i + chunkSize < text.length) ? i + chunkSize : text.length;
      final chunk = text.substring(i, end);
      if (chunk.isNotEmpty) {
        chunks.add(chunk);
      }
    }

    return chunks.isEmpty ? [text] : chunks;
  }
}
