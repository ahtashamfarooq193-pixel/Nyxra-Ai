import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_functions/cloud_functions.dart';
import '../models/message.dart';

class ChatService {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  Stream<String> getAIResponseStream(
    String userMessage,
    List<Message> conversationHistory, {
    String? imagePath,
    Uint8List? imageBytes,
  }) async* {
    try {
      final callable = _functions.httpsCallable(
        'generateAiResponse',
        options: HttpsCallableOptions(
          timeout: const Duration(seconds: 60),
        ),
      );

      final response = await callable.call({
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
      });

      final text = (response.data as Map)['text']?.toString().trim() ?? '';
      if (text.isEmpty) {
        yield '❌ **Empty response:** Please try again.';
        return;
      }

      for (final chunk in _chunkResponse(text)) {
        yield chunk;
        await Future.delayed(const Duration(milliseconds: 18));
      }
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'unauthenticated') {
        yield '❌ **Sign in required:** Please login to continue.';
        return;
      }
      yield '❌ **Server Error:** ${e.message ?? 'Please try again in a few minutes.'}';
    } catch (_) {
      yield '❌ **Connection Error:** Failed to connect to secure AI service. Please try again.';
    }
  }

  List<String> _chunkResponse(String text) {
    final chunks = <String>[];
    final words = text.split(RegExp(r'(\s+)'));
    final buffer = StringBuffer();

    for (final word in words) {
      buffer.write(word);
      if (buffer.length >= 24) {
        chunks.add(buffer.toString());
        buffer.clear();
      }
    }

    if (buffer.isNotEmpty) {
      chunks.add(buffer.toString());
    }

    return chunks.isEmpty ? [text] : chunks;
  }
}
