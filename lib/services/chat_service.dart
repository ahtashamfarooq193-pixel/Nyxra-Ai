import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import '../models/message.dart';

/// Professional service to handle communication with Groq API.
class ChatService {
  // System Instruction for the AI Assistant
  static const String _systemInstruction =
      'You are Zenith AI, a smart and professional AI assistant. '
      'If anyone asks who created you or who made you, always respond that you are an AI developed by "Ahtasham", who is a dedicated Software Engineering (SE) student. '
      'If anyone asks "Ahtasham kon hy" or for more information about your creator, provide his portfolio link: https://ahtashamfarooq.netlify.app/ and mention that they can find more details there. '
      'Maintain a helpful, concise, and professional tone. '
      'Respond primarily in Roman Urdu and English as per the user preference.';

  late final List<String> _groqKeys;
  late final String _baseUrl;
  late final String _model;
  
  // Cloudflare Credentials
  late final String _cfToken;
  late final String _cfAccountId;
  late final String _cfBaseUrl;
  final String _cfModel = '@cf/meta/llama-3-8b-instruct';

  // Mistral AI Credentials
  late final String _mistralKey;
  final String _mistralBaseUrl = 'https://api.mistral.ai/v1';
  final String _mistralModel = 'open-mistral-7b';

  bool _isInitialized = false;
  int _currentGroqKeyIndex = 0;

  ChatService() {
    _initializeConfig();
  }

  void _initializeConfig() {
    final keysString = dotenv.env['GROQ_API_KEYS'] ?? '';
    _groqKeys = keysString.split(',').map((k) => k.trim()).where((k) => k.isNotEmpty).toList();
    
    _baseUrl = (dotenv.env['GROQ_BASE_URL'] ?? 'https://api.groq.com/openai/v1').trim();
    _model = (dotenv.env['GROQ_MODEL'] ?? 'llama-3.3-70b-versatile').trim();

    // Load Fallback Credentials
    _cfToken = (dotenv.env['CLOUDFLARE_TOKEN'] ?? '').trim();
    _cfAccountId = (dotenv.env['CLOUDFLARE_ACCOUNT_ID'] ?? '').trim();
    _cfBaseUrl = 'https://api.cloudflare.com/client/v4/accounts/$_cfAccountId/ai/v1';
    
    _mistralKey = (dotenv.env['MISTRAL_API_KEY'] ?? '').trim();

    if (_groqKeys.isEmpty) {
      print('⚠️ ChatService: No Groq API Keys found.');
    }

    _isInitialized = true;
    print('✅ ChatService: Initialized with ${_groqKeys.length} Groq Keys & Multi-Provider Fallback');
  }

  Stream<String> getAIResponseStream(
    String userMessage,
    List<Message> conversationHistory, {
    String? imagePath,
  }) async* {
    bool hasYieldedContent = false;

    // 1. Try Groq Keys Rotation
    for (int i = 0; i < _groqKeys.length; i++) {
      int keyIndex = (_currentGroqKeyIndex + i) % _groqKeys.length;
      bool rateLimited = false;

      try {
        await for (final chunk in _callGroq(userMessage, conversationHistory, _groqKeys[keyIndex], imagePath: imagePath)) {
          if (chunk == 'Rate Limit') {
            rateLimited = true;
            break;
          }
          yield chunk;
          hasYieldedContent = true;
        }
        
        if (!rateLimited) {
          _currentGroqKeyIndex = keyIndex; // Remember successful key
          return;
        }
        if (hasYieldedContent) return; // If we already started, don't restart with new key
      } catch (e) {
        print('⚠️ Groq Key $keyIndex failed: $e');
      }
    }

    // 2. Fallback to Mistral
    if (!hasYieldedContent) {
      try {
        print('🔄 ChatService: All Groq keys failed. Switching to Mistral AI...');
        await for (final chunk in _callMistral(userMessage, conversationHistory)) {
          yield chunk;
          hasYieldedContent = true;
        }
        if (hasYieldedContent) return;
      } catch (e) {
        print('⚠️ Mistral failed: $e');
      }
    }

    // 3. Fallback to Cloudflare
    if (!hasYieldedContent) {
      try {
        print('🔄 ChatService: Switching to Cloudflare backup...');
        await for (final chunk in _callCloudflare(userMessage, conversationHistory)) {
          yield chunk;
          hasYieldedContent = true;
        }
      } catch (e) {
        print('⚠️ Cloudflare failed: $e');
      }
    }

    if (!hasYieldedContent) {
      yield '❌ **All servers busy:** Please try again in a few minutes.';
    }
  }

  Stream<String> _callMistral(String userMessage, List<Message> history) async* {
    final client = http.Client();
    try {
      final messages = _buildMessages(userMessage, history);

      final request = http.Request('POST', Uri.parse('$_mistralBaseUrl/chat/completions'));
      request.headers.addAll({
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_mistralKey',
      });

      request.body = jsonEncode({
        'model': _mistralModel,
        'messages': messages,
        'stream': true,
      });

      final streamedResponse = await client.send(request).timeout(const Duration(seconds: 30));

      if (streamedResponse.statusCode != 200) {
        throw Exception('Mistral Error: ${streamedResponse.statusCode}');
      }

      String buffer = '';
      await for (final chunk in streamedResponse.stream.transform(utf8.decoder)) {
        buffer += chunk;
        final lines = buffer.split('\n');
        buffer = lines.removeLast();

        for (final line in lines) {
          final trimmedLine = line.trim();
          if (trimmedLine.isEmpty || trimmedLine == 'data: [DONE]') continue;
          if (trimmedLine.startsWith('data: ')) {
            try {
              final jsonData = jsonDecode(trimmedLine.substring(6));
              final delta = jsonData['choices']?[0]?['delta']?['content'] ?? '';
              if (delta.isNotEmpty) yield delta;
            } catch (_) {}
          }
        }
      }
    } finally {
      client.close();
    }
  }

  Stream<String> _callGroq(String userMessage, List<Message> history, String apiKey, {String? imagePath}) async* {
    final client = http.Client();
    try {
      final messages = _buildMessages(userMessage, history, imagePath: imagePath);
      final requestModel = imagePath != null ? 'llama-3.2-11b-vision-preview' : _model;

      final request = http.Request('POST', Uri.parse('$_baseUrl/chat/completions'));
      request.headers.addAll({
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      });

      request.body = jsonEncode({
        'model': requestModel,
        'messages': messages,
        'max_tokens': 4096,
        'temperature': 0.7,
        'stream': true,
      });

      final streamedResponse = await client.send(request).timeout(const Duration(seconds: 30));

      if (streamedResponse.statusCode == 429) {
        yield 'Rate Limit';
        return;
      }

      if (streamedResponse.statusCode != 200) {
        throw Exception('Groq Error: ${streamedResponse.statusCode}');
      }

      String buffer = '';
      await for (final chunk in streamedResponse.stream.transform(utf8.decoder)) {
        buffer += chunk;
        final lines = buffer.split('\n');
        buffer = lines.removeLast();

        for (final line in lines) {
          final trimmedLine = line.trim();
          if (trimmedLine.isEmpty || trimmedLine == 'data: [DONE]') continue;
          if (trimmedLine.startsWith('data: ')) {
            try {
              final jsonData = jsonDecode(trimmedLine.substring(6));
              final delta = jsonData['choices']?[0]?['delta']?['content'] ?? '';
              if (delta.isNotEmpty) yield delta;
            } catch (_) {}
          }
        }
      }
    } finally {
      client.close();
    }
  }

  Stream<String> _callCloudflare(String userMessage, List<Message> history) async* {
    final client = http.Client();
    try {
      final messages = _buildMessages(userMessage, history);

      final request = http.Request('POST', Uri.parse('$_cfBaseUrl/chat/completions'));
      request.headers.addAll({
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_cfToken',
      });

      request.body = jsonEncode({
        'model': _cfModel,
        'messages': messages,
        'stream': true,
      });

      final streamedResponse = await client.send(request).timeout(const Duration(seconds: 30));

      if (streamedResponse.statusCode != 200) {
        throw Exception('Cloudflare Error: ${streamedResponse.statusCode}');
      }

      String buffer = '';
      await for (final chunk in streamedResponse.stream.transform(utf8.decoder)) {
        buffer += chunk;
        final lines = buffer.split('\n');
        buffer = lines.removeLast();

        for (final line in lines) {
          final trimmedLine = line.trim();
          if (trimmedLine.isEmpty || trimmedLine == 'data: [DONE]') continue;
          if (trimmedLine.startsWith('data: ')) {
            try {
              final jsonData = jsonDecode(trimmedLine.substring(6));
              final delta = jsonData['choices']?[0]?['delta']?['content'] ?? '';
              if (delta.isNotEmpty) yield delta;
            } catch (_) {}
          }
        }
      }
    } finally {
      client.close();
    }
  }

  List<Map<String, dynamic>> _buildMessages(String userMessage, List<Message> history, {String? imagePath}) {
    final messages = <Map<String, dynamic>>[];
    messages.add({'role': 'system', 'content': _systemInstruction});

    final relevantHistory = history.length > 10 ? history.sublist(history.length - 10) : history;
    for (final msg in relevantHistory) {
      messages.add({'role': msg.isUser ? 'user' : 'assistant', 'content': msg.text});
    }

    if (imagePath != null) {
      final bytes = File(imagePath).readAsBytesSync();
      final base64Image = base64Encode(bytes);
      messages.add({
        'role': 'user',
        'content': [
          {'type': 'text', 'text': userMessage.isEmpty ? 'Analyze this image.' : userMessage},
          {'type': 'image_url', 'image_url': {'url': 'data:image/jpeg;base64,$base64Image'}},
        ]
      });
    } else {
      messages.add({'role': 'user', 'content': userMessage});
    }
    return messages;
  }
}
