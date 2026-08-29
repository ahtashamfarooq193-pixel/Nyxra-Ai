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
      final response = await http
          .post(
            Uri.parse('$_backendBaseUrl/api/chat'),
            headers: {'Content-Type': 'application/json'},
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
              'imageBase64': imageBytes == null
                  ? null
                  : base64Encode(imageBytes),
              'imagePath': imagePath,
            }),
          )
          .timeout(const Duration(seconds: 75));

      if (response.statusCode != 200) {
        String errorDetail = 'Something went wrong';
        try {
          final errDecoded = jsonDecode(response.body);
          errorDetail =
              errDecoded['details'] ?? errDecoded['error'] ?? errorDetail;
        } catch (_) {}
        throw ChatServiceException(
          'Server Error (${response.statusCode}): $errorDetail',
        );
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final text = decoded['text']?.toString().trim() ?? '';
      final generatedImage = decoded['generatedImage'] as String?;
      final generatedImageUrl = decoded['generatedImageUrl'] as String?;
      final generatedDocument = decoded['generatedDocument'] as String?;
      final documentName =
          decoded['documentName']?.toString() ?? 'nyxra-document.docx';

      if (generatedImage != null) {
        // Special marker for images to be caught by the UI
        if (text.isNotEmpty) yield text;
        yield "|||IMG|||$generatedImage";
        return;
      }

      if (generatedImageUrl != null && generatedImageUrl.isNotEmpty) {
        if (text.isNotEmpty) yield text;
        yield "|||IMGURL|||$generatedImageUrl";
        return;
      }

      if (generatedDocument != null && generatedDocument.isNotEmpty) {
        if (text.isNotEmpty) yield text;
        final safeName = documentName.replaceAll('|||', '-');
        yield "|||DOCX|||$safeName|||$generatedDocument";
        return;
      }

      if (text.isEmpty) {
        throw const ChatServiceException(
          'AI service returned an empty response. Please try again.',
        );
      }

      for (final chunk in _chunkResponse(text)) {
        yield chunk;
        await Future.delayed(const Duration(milliseconds: 18));
      }
    } on TimeoutException {
      throw const ChatServiceException(
        'The server took too long to respond. Please try again.',
      );
    } on ChatServiceException {
      rethrow;
    } catch (e) {
      print('ChatService Error: $e');
      throw const ChatServiceException(
        'Could not connect to the AI service. Check your connection and retry.',
      );
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

class ChatServiceException implements Exception {
  final String message;

  const ChatServiceException(this.message);

  @override
  String toString() => message;
}
