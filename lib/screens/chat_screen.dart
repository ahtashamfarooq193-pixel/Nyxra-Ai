import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/message.dart';
import '../widgets/message_bubble.dart';
import '../widgets/message_input.dart';
import '../services/chat_service.dart';
import '../services/storage_service.dart';
import '../services/firestore_service.dart';
import '../utils/constants.dart';
import '../splashscreen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<Message> _messages = [];
  final ChatService _chatService = ChatService();
  final StorageService _storageService = StorageService();
  final FirestoreService _firestoreService = FirestoreService();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  bool _isLoading = false;
  bool _isGenerating = false;
  bool _stopRequested = false;
  bool _showScrollToBottom = false;
  int _generationId = 0;
  String? _currentUserUid;
  late String _currentSessionId = DateTime.now().millisecondsSinceEpoch
      .toString(); // Current active session
  final FlutterTts _flutterTts = FlutterTts();
  bool _isVoiceEnabled = false;
  int _userTokens = AppConstants.dailyFreeTokens;
  int _dailyImagesUsed = 0;
  List<Message> _allHistoryMessages = [];
  bool _isHistoryLoading = false;
  int _historyLoadId = 0;
  bool _isSigningIn = false;

  @override
  void initState() {
    super.initState();
    try {
      _currentUserUid = FirebaseAuth.instance.currentUser?.uid;
      _startNewChat();
      _scrollController.addListener(_handleScrollPosition);

      // Auto-focus input
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          FocusScope.of(context).requestFocus(_focusNode);
        }
      });

      _initTts();
      _loadUserTokens();
      _loadImageUsage();
      _refreshHistory();
    } catch (e) {
      print("ChatScreen Initialization Error: $e");
    }
  }

  Future<void> _refreshHistory() async {
    final loadId = ++_historyLoadId;
    setState(() => _isHistoryLoading = true);

    List<Message> messages = [];
    if (_currentUserUid != null) {
      messages = await _firestoreService.loadMessages(_currentUserUid!);
    } else {
      messages = await _storageService.loadMessages();
    }

    if (mounted && loadId == _historyLoadId) {
      setState(() {
        _allHistoryMessages = messages;
        _isHistoryLoading = false;
      });
    }
  }

  void _loadUserTokens() async {
    if (_currentUserUid == null) {
      // Guests keep their balance locally so it survives app restarts.
      final tokens = await _storageService.loadGuestTokens(
        AppConstants.dailyFreeTokens,
      );
      if (mounted) {
        setState(() {
          _userTokens = tokens;
        });
      }
      return;
    }

    final tokens = await _firestoreService.checkAndResetDailyTokens(
      _currentUserUid!,
    );
    if (!mounted) return;
    setState(() {
      _userTokens = tokens;
    });

    if (_userTokens == AppConstants.dailyFreeTokens) {
      // Show reset message in English at the top
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✅ Your ${AppConstants.dailyFreeTokens} daily free tokens have been reset!',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600),
          ),
          backgroundColor: AppConstants.primaryColor,
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.only(
            bottom: MediaQuery.of(context).size.height - 100,
            left: 20,
            right: 20,
          ),
        ),
      );
    }
  }

  Future<void> _loadImageUsage() async {
    final used = _currentUserUid == null
        ? await _storageService.loadGuestImageCount()
        : await _firestoreService.getDailyImageCount(_currentUserUid!);
    if (mounted) setState(() => _dailyImagesUsed = used);
  }

  bool _isImageGenerationRequest(String text) {
    final value = text.trim().toLowerCase();
    if (RegExp(r'^/(draw|image|imagine)\s+').hasMatch(value)) return true;
    final hasImageWord = RegExp(
      r'\b(image|img|pics?|picture|photo|tasveer)\b',
    ).hasMatch(value);
    final hasCreateWord = RegExp(
      r'\b(draw|generate|create|make|bna|bnao|bana|banao|imagine)\b',
    ).hasMatch(value);
    return hasImageWord && hasCreateWord;
  }

  Future<bool> _reserveImageSlot() async {
    final reserved = _currentUserUid == null
        ? await _storageService.tryReserveGuestImage(
            AppConstants.dailyFreeImages,
          )
        : await _firestoreService.tryReserveDailyImage(
            _currentUserUid!,
            AppConstants.dailyFreeImages,
          );
    if (reserved && mounted) setState(() => _dailyImagesUsed++);
    return reserved;
  }

  Future<void> _releaseImageSlot() async {
    if (_currentUserUid == null) {
      await _storageService.releaseGuestImage();
    } else {
      await _firestoreService.releaseDailyImage(_currentUserUid!);
    }
    if (mounted && _dailyImagesUsed > 0) {
      setState(() => _dailyImagesUsed--);
    }
  }

  void _initTts() async {
    try {
      await _flutterTts.setLanguage("en-US");
      await _flutterTts.setSpeechRate(0.45); // Balanced speed
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);

      // Try to set the engine to Google TTS (Best for Android)
      if (!kIsWeb && Theme.of(context).platform == TargetPlatform.android) {
        await _flutterTts.setEngine("com.google.android.tts");
      }

      // Fetch available voices and try to find a "Premium/Enhanced" one
      var voices = await _flutterTts.getVoices;
      if (voices != null) {
        List<dynamic> voiceList = List<dynamic>.from(voices);

        // Priority list for professional sounding voices
        final priorityVoices = [
          "en-us-x-sfg#female_1-local",
          "en-us-x-tpf-local",
          "en-us-x-iol-local",
          "en-us-x-low-local",
          "en-gb-x-fis-local",
        ];

        for (var priority in priorityVoices) {
          final found = voiceList.firstWhere(
            (v) => v["name"].toString().contains(priority),
            orElse: () => null,
          );
          if (found != null) {
            await _flutterTts.setVoice({
              "name": found["name"],
              "locale": found["locale"],
            });
            print("Selected Premium Voice: ${found["name"]}");
            break;
          }
        }
      }
    } catch (e) {
      print("TTS Optimization Error: $e");
    }
  }

  // Helper to fix pronunciation of names and Urdu words
  String _prepareTextForSpeech(String text) {
    String processed = text;
    // Fix user's name pronunciation
    processed = processed.replaceAll(
      RegExp(r'\bAhtasham\b', caseSensitive: false),
      "Eh-tah-shaam",
    );
    processed = processed.replaceAll(
      RegExp(r'\bAhtasham Farooq\b', caseSensitive: false),
      "Eh-tah-shaam Fa-rook",
    );

    // Fix common AI mispronunciations in greeting
    processed = processed.replaceAll(
      "Assalam-o-Alaikum",
      "As-salaam-o-alaikum",
    );

    // Clean markdown characters for smoother speech
    processed = processed.replaceAll(RegExp(r'[\*\#_]'), "");

    return processed;
  }

  void _startNewChat() {
    if (!mounted) return;
    setState(() {
      _generationId++;
      _stopRequested = true;
      _isGenerating = false;
      _messages.clear();
      _isLoading = false; // Reset loading state!
      _currentSessionId = DateTime.now().millisecondsSinceEpoch.toString();

      // Add welcome message with unique ID to prevent widget reuse issues
      _messages.add(
        Message(
          id: 'welcome_$_currentSessionId',
          text: 'Hello! I\'m Nyxra AI. How can I help you today?',
          isUser: false,
          timestamp: DateTime.now(),
          sessionId: _currentSessionId,
        ),
      );
    });
  }

  Future<void> _saveMessages() async {
    if (_currentUserUid == null) {
      await _storageService.saveSessionMessages(_messages);
    }
  }

  Future<void> _syncMessageToCloud(Message message) async {
    if (_currentUserUid != null) {
      await _firestoreService.saveMessage(_currentUserUid!, message);
    }
  }

  @override
  void dispose() {
    _flutterTts.stop();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _addMessage({
    required String text,
    required bool isUser,
    MessageStatus? status,
    String? imagePath,
    bool isError = false,
    bool persist = true,
  }) {
    final newMessage = Message(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      text: text,
      isUser: isUser,
      timestamp: DateTime.now(),
      status: status ?? MessageStatus.delivered,
      imagePath: imagePath,
      sessionId: _currentSessionId,
      isError: isError,
    );

    setState(() {
      _messages.add(newMessage);
    });

    if (persist) {
      _saveMessages();
      _syncMessageToCloud(newMessage);
    }
    _scrollToBottom();
    _refreshHistory();
  }

  void _deleteMessage(String id) {
    setState(() {
      _messages.removeWhere((m) => m.id == id);
    });
    _saveMessages();
    if (_currentUserUid != null) {
      _firestoreService.deleteMessage(_currentUserUid!, id);
    }
    _refreshHistory();
  }

  void _showEditDialog(Message message) {
    final TextEditingController editController = TextEditingController(
      text: message.text,
    );
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppConstants.surfaceColor,
        title: Text(
          'Edit Message',
          style: GoogleFonts.poppins(color: Colors.white, fontSize: 18),
        ),
        content: TextField(
          controller: editController,
          style: GoogleFonts.inter(color: Colors.white),
          maxLines: null,
          decoration: InputDecoration(
            hintText: 'Edit your message...',
            hintStyle: GoogleFonts.inter(color: AppConstants.faintTextColor),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white24),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: AppConstants.primaryColor),
            ),
          ),
        ),
        actions: [
          TextButton(
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(color: AppConstants.mutedTextColor),
            ),
            onPressed: () => Navigator.pop(context),
          ),
          TextButton(
            child: Text(
              'Save & resend',
              style: GoogleFonts.inter(
                color: AppConstants.primaryColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            onPressed: () {
              final newText = editController.text.trim();
              if (newText.isNotEmpty && newText != message.text) {
                Navigator.pop(context);
                _editAndResendMessage(message, newText);
                return;
              }
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _editAndResendMessage(
    Message originalMessage,
    String newText,
  ) async {
    if (_isGenerating) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Stop the current response before editing a message.'),
        ),
      );
      return;
    }

    await _handleSendMessage(
      newText,
      originalMessage.imagePath,
      null,
      false,
      originalMessage.id,
    );
  }

  void _updateMessageStatus(String messageId, MessageStatus newStatus) {
    setState(() {
      final index = _messages.indexWhere((msg) => msg.id == messageId);
      if (index != -1) {
        _messages[index] = _messages[index].copyWith(status: newStatus);
        _syncMessageToCloud(_messages[index]);
      }
    });
    _saveMessages();
  }

  void _handleScrollPosition() {
    if (!_scrollController.hasClients) return;
    final shouldShow =
        _scrollController.position.maxScrollExtent -
            _scrollController.position.pixels >
        180;
    if (shouldShow != _showScrollToBottom && mounted) {
      setState(() => _showScrollToBottom = shouldShow);
    }
  }

  bool get _isNearBottom {
    if (!_scrollController.hasClients) return true;
    return _scrollController.position.maxScrollExtent -
            _scrollController.position.pixels <
        180;
  }

  void _scrollToBottom({bool force = false}) {
    if (!force && !_isNearBottom) return;
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted && _scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: AppConstants.mediumAnimation,
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _stopGeneration() {
    if (!_isGenerating) return;
    setState(() {
      _stopRequested = true;
      _isGenerating = false;
      _isLoading = false;
    });
  }

  Future<bool> _handleSendMessage(
    String text,
    String? imagePath,
    Uint8List? imageBytes, [
    bool isVoiceInput = false,
    String? editFromMessageId,
  ]) async {
    final trimmedText = text.trim();
    if (trimmedText.isEmpty && imagePath == null) return false;
    if (_isGenerating) return false;

    final requestGenerationId = ++_generationId;
    _stopRequested = false;

    // 1. Token Check
    if (_userTokens <= 0) {
      _showPurchaseMessage();
      return false;
    }

    final isImageRequest = _isImageGenerationRequest(trimmedText);
    var imageSlotReserved = false;
    var imageDelivered = false;
    if (isImageRequest) {
      imageSlotReserved = await _reserveImageSlot();
      if (!imageSlotReserved) {
        _addMessage(
          text:
              '🖼️ Aaj ki ${AppConstants.dailyFreeImages} free images ki limit complete ho gayi hai. Kal dobara images generate kar sakte hain.',
          isUser: false,
          isError: true,
          persist: false,
        );
        return false;
      }
    }

    if (editFromMessageId != null) {
      final messageIndex = _messages.indexWhere(
        (message) => message.id == editFromMessageId,
      );
      if (messageIndex == -1) {
        if (imageSlotReserved) await _releaseImageSlot();
        return false;
      }

      // Only replace the old branch after all local validation and quota
      // reservation succeeded, so a rejected edit never destroys history.
      final supersededMessages = _messages.sublist(messageIndex).toList();
      setState(() => _messages.removeRange(messageIndex, _messages.length));
      if (_currentUserUid != null) {
        await Future.wait(
          supersededMessages.map(
            (message) =>
                _firestoreService.deleteMessage(_currentUserUid!, message.id),
          ),
        );
      }
    }

    final userMessageId = DateTime.now().millisecondsSinceEpoch.toString();
    final userMessage = Message(
      id: userMessageId,
      text: trimmedText,
      isUser: true,
      timestamp: DateTime.now(),
      status: MessageStatus.delivered,
      imagePath: imagePath,
      sessionId: _currentSessionId,
    );

    setState(() {
      _messages.add(userMessage);
      _isLoading = true;
      _isGenerating = true;
    });

    _saveMessages();
    _scrollToBottom(force: true);
    _syncMessageToCloud(userMessage);
    _refreshHistory();

    // Create a placeholder for AI message
    final aiMessageId = (DateTime.now().millisecondsSinceEpoch + 1).toString();

    // Check if it's an image request to show a better loading state
    Message aiMessage = Message(
      id: aiMessageId,
      text: isImageRequest ? '🎨 Drawing your imagination...' : '',
      isUser: false,
      timestamp: DateTime.now(),
      status: MessageStatus.sending,
      sessionId: _currentSessionId,
    );

    bool isFirstChunk = true;

    try {
      final stream = _chatService.getAIResponseStream(
        trimmedText,
        _messages
            .where((message) => message.id != aiMessageId && !message.isError)
            .toList(),
        imagePath: imagePath,
        imageBytes: imageBytes,
      );

      await for (final chunk in stream) {
        if (!mounted) break;
        if (_stopRequested || requestGenerationId != _generationId) break;
        if (_currentSessionId != aiMessage.sessionId)
          break; // User switched chats

        if (isFirstChunk) {
          setState(() {
            _messages.add(aiMessage);
            _isLoading = false; // Hide typing indicator once stream starts
          });
          isFirstChunk = false;
        }

        // If it's an image response, clear the "Drawing..." placeholder first
        if ((chunk.startsWith("|||IMG|||") ||
                chunk.startsWith("|||IMGURL|||")) &&
            aiMessage.text.contains('Drawing')) {
          aiMessage = aiMessage.copyWith(text: '');
        }

        if (chunk.startsWith("|||IMG|||")) {
          imageDelivered = true;
          final base64Data = chunk.substring(9);
          setState(() {
            final index = _messages.indexWhere((m) => m.id == aiMessageId);
            if (index != -1) {
              aiMessage = aiMessage.copyWith(
                imagePath: "data:image/png;base64,$base64Data",
              );
              _messages[index] = aiMessage;
            }
          });
          continue;
        }

        if (chunk.startsWith("|||IMGURL|||")) {
          imageDelivered = true;
          final imageUrl = chunk.substring(12);
          setState(() {
            final index = _messages.indexWhere((m) => m.id == aiMessageId);
            if (index != -1) {
              aiMessage = aiMessage.copyWith(imagePath: imageUrl);
              _messages[index] = aiMessage;
            }
          });
          continue;
        }

        if (chunk.startsWith("|||DOCX|||")) {
          final documentPayload = chunk.substring(10);
          final separatorIndex = documentPayload.indexOf('|||');
          if (separatorIndex != -1) {
            final documentName = documentPayload.substring(0, separatorIndex);
            final documentBase64 = documentPayload.substring(
              separatorIndex + 3,
            );
            setState(() {
              final index = _messages.indexWhere((m) => m.id == aiMessageId);
              if (index != -1) {
                aiMessage = aiMessage.copyWith(
                  documentName: documentName,
                  documentBase64: documentBase64,
                );
                _messages[index] = aiMessage;
              }
            });
          }
          continue;
        }

        setState(() {
          final index = _messages.indexWhere((m) => m.id == aiMessageId);
          if (index != -1) {
            aiMessage = aiMessage.copyWith(text: aiMessage.text + chunk);
            _messages[index] = aiMessage;
          }
        });
        _scrollToBottom();
      }

      final wasStopped = _stopRequested || requestGenerationId != _generationId;
      if (wasStopped && !isFirstChunk) {
        _updateMessageStatus(aiMessageId, MessageStatus.delivered);
        _saveMessages();
      } else if (!wasStopped && _currentSessionId == aiMessage.sessionId) {
        // Mark as delivered and save
        _updateMessageStatus(aiMessageId, MessageStatus.delivered);
        _saveMessages();
        _syncMessageToCloud(aiMessage);

        if (_isVoiceEnabled || isVoiceInput) {
          _flutterTts.speak(_prepareTextForSpeech(aiMessage.text));
        }

        // 2. Token Deduction
        _deductTokens(aiMessage.text);
      }
    } on ChatServiceException catch (error) {
      if (requestGenerationId == _generationId &&
          _currentSessionId == aiMessage.sessionId) {
        if (!isFirstChunk) {
          setState(() => _messages.removeWhere((m) => m.id == aiMessageId));
        }
        _addMessage(
          text: '❌ **Service Error:** ${error.message}',
          isUser: false,
          isError: true,
          persist: false,
        );
      }
    } catch (e) {
      print('ChatScreen Streaming Error: $e');
      if (isFirstChunk &&
          requestGenerationId == _generationId &&
          _currentSessionId == aiMessage.sessionId) {
        _addMessage(
          text:
              '❌ **Service Error:** AI is temporarily unreachable. Please try again in a moment.',
          isUser: false,
          isError: true,
          persist: false,
        );
      }
    } finally {
      if (imageSlotReserved && !imageDelivered) {
        await _releaseImageSlot();
      }
      if (mounted &&
          requestGenerationId == _generationId &&
          _currentSessionId == aiMessage.sessionId) {
        setState(() {
          _isLoading = false;
          _isGenerating = false;
        });
      }
    }
    return true;
  }

  void _deductTokens(String response) {
    int tokensUsed = (response.length / 4).ceil();
    setState(() {
      _userTokens -= tokensUsed;
      if (_userTokens < 0) _userTokens = 0;
    });

    if (_currentUserUid != null) {
      _firestoreService.updateTokens(_currentUserUid!, _userTokens);
    } else {
      _storageService.saveGuestTokens(_userTokens);
    }

    if (_userTokens <= 10 && _userTokens > 0) {
      _addMessage(
        text:
            '⚠️ Alert: Aapke sirf $_userTokens tokens bache hain aaj ke liye!',
        isUser: false,
      );
    }
  }

  void _showPurchaseMessage() {
    _addMessage(
      text:
          '🚫 Aapki aaj ki free limit (5000 tokens) khatam ho gayi!\n\n'
          '💎 **Token purchases abhi available nahi hain.**\n'
          'Buy Tokens feature coming soon hai.\n\n'
          '⏰ **Free tokens?**\n'
          'Kal midnight tak wait karo — 5000 free tokens automatic reset ho jayenge! 🔄',
      isUser: false,
      isError: true,
      persist: false,
    );
  }

  Future<void> _handleGoogleSignIn() async {
    if (_isSigningIn) return;
    setState(() => _isSigningIn = true);

    try {
      if (kIsWeb) {
        final GoogleAuthProvider googleProvider = GoogleAuthProvider();
        await FirebaseAuth.instance.signInWithPopup(googleProvider);
      } else {
        final GoogleSignIn googleSignIn = GoogleSignIn();
        await googleSignIn.signOut(); // clear stale sessions
        final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
        if (googleUser == null) {
          if (mounted) setState(() => _isSigningIn = false);
          return; // user cancelled
        }
        final GoogleSignInAuthentication googleAuth =
            await googleUser.authentication;
        final AuthCredential credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );
        await FirebaseAuth.instance.signInWithCredential(credential);
      }

      if (!mounted) return;
      setState(() => _currentUserUid = FirebaseAuth.instance.currentUser?.uid);
      _loadUserTokens();
      _loadImageUsage();
      _refreshHistory();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ Signed in — your tokens and history will now sync.',
              style: GoogleFonts.inter(),
            ),
            backgroundColor: AppConstants.successColor,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      print('SIGN-IN ERROR: $e');
      if (mounted) {
        String errorMsg = 'Sign in failed. Please try again.';
        if (e.toString().contains('People API')) {
          errorMsg =
              'Setup incomplete: Please enable People API in Google Console and wait 5 minutes.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg),
            backgroundColor: AppConstants.errorColor,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: _handleGoogleSignIn,
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSigningIn = false);
    }
  }

  Future<void> _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppConstants.surfaceColor,
        title: Text(
          'Sign Out',
          style: GoogleFonts.poppins(color: Colors.white),
        ),
        content: Text(
          'Are you sure you want to sign out?',
          style: GoogleFonts.inter(color: AppConstants.mutedTextColor),
        ),
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(context, false),
          ),
          TextButton(
            child: const Text(
              'Sign Out',
              style: TextStyle(color: AppConstants.errorColor),
            ),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseAuth.instance.signOut();
      await GoogleSignIn().signOut();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const Splashscreen()),
          (route) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isWideScreen = screenWidth > 900;

    Widget mainChat = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: Column(
          children: [
            Flexible(
              child: Stack(
                children: [
                  _messages.isEmpty
                      ? _buildEmptyState()
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(
                            vertical: AppConstants.paddingMedium,
                          ),
                          itemCount: _messages.length + (_isLoading ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == _messages.length && _isLoading) {
                              return _buildTypingIndicator();
                            }
                            return MessageBubble(
                              message: _messages[index],
                              onCopy: (msg) {
                                Clipboard.setData(
                                  ClipboardData(text: msg.text),
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Message copied to clipboard',
                                    ),
                                  ),
                                );
                              },
                              onEdit: (msg) => _showEditDialog(msg),
                              onDelete: (msg) => _deleteMessage(msg.id),
                            );
                          },
                        ),
                  if (_showScrollToBottom)
                    Positioned(
                      right: 16,
                      bottom: 14,
                      child: Tooltip(
                        message: 'Jump to latest message',
                        child: FloatingActionButton.small(
                          heroTag: 'scroll_to_latest',
                          backgroundColor: AppConstants.surfaceOverlay,
                          foregroundColor: Colors.white,
                          onPressed: () => _scrollToBottom(force: true),
                          child: const Icon(Icons.keyboard_arrow_down_rounded),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            MessageInput(
              onSendMessage: (text, imagePath, imageBytes, isVoiceInput) =>
                  _handleSendMessage(text, imagePath, imageBytes, isVoiceInput),
              focusNode: _focusNode,
              isGenerating: _isGenerating,
              onStopGenerating: _stopGeneration,
            ),
          ],
        ),
      ),
    );

    if (isWideScreen) {
      return Scaffold(
        backgroundColor: AppConstants.backgroundColor,
        body: Row(
          children: [
            // Persistent Sidebar for Web/Desktop
            Container(
              width: 300,
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(color: AppConstants.borderColor, width: 1),
                ),
              ),
              child: _buildHistoryDrawerContent(),
            ),
            // Main Chat Area
            Expanded(
              child: Scaffold(
                backgroundColor: Colors.transparent,
                appBar: _buildAppBar(isWideScreen),
                body: mainChat,
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppConstants.backgroundColor,
      resizeToAvoidBottomInset: true,
      appBar: isLandscape ? null : _buildAppBar(false),
      drawer: _buildHistoryDrawer(),
      body: mainChat,
    );
  }

  PreferredSizeWidget _buildAppBar(bool isWideScreen) {
    return AppBar(
      elevation: 0,
      backgroundColor: AppConstants.backgroundColor.withOpacity(0.8),
      surfaceTintColor: Colors.transparent,
      automaticallyImplyLeading: !isWideScreen,
      flexibleSpace: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AppConstants.borderColor, width: 1),
          ),
        ),
      ),
      title: Row(
        children: [
          Hero(
            tag: 'bot_icon',
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.2),
                border: Border.all(
                  color: Colors.white.withOpacity(0.3),
                  width: 1.5,
                ),
              ),
              child: ClipOval(
                child: Image.asset(
                  'assets/images/Icon.png',
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    decoration: const BoxDecoration(
                      gradient: AppConstants.primaryGradient,
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.smart_toy_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Nyxra AI',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppConstants.successColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'High Speed',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: Colors.white.withOpacity(0.9),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: Icon(
            _isVoiceEnabled ? Icons.volume_up : Icons.volume_off,
            color: _isVoiceEnabled
                ? AppConstants.successColor
                : AppConstants.mutedTextColor,
          ),
          onPressed: () {
            setState(() {
              _isVoiceEnabled = !_isVoiceEnabled;
              if (!_isVoiceEnabled) {
                _flutterTts.stop();
              }
            });
          },
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: Colors.white),
          onSelected: (value) {
            if (value == 'clear') {
              _confirmClearChat();
            } else if (value == 'logout') {
              _handleLogout();
            } else if (value == 'login') {
              _handleGoogleSignIn();
            }
          },
          itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
            const PopupMenuItem<String>(
              value: 'clear',
              child: Row(
                children: [
                  Icon(
                    Icons.delete_outline,
                    color: AppConstants.errorColor,
                    size: 20,
                  ),
                  SizedBox(width: 8),
                  Text('Clear Chat'),
                ],
              ),
            ),
            if (_currentUserUid != null)
              const PopupMenuItem<String>(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Text('Sign Out'),
                  ],
                ),
              )
            else
              const PopupMenuItem<String>(
                value: 'login',
                child: Row(
                  children: [
                    Icon(Icons.login, color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Text('Sign In'),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildHistoryDrawer() {
    return Drawer(
      backgroundColor: AppConstants.backgroundColor,
      child: _buildHistoryDrawerContent(),
    );
  }

  Widget _buildHistoryDrawerContent() {
    return Column(
      children: [
        _buildDrawerHeader(),
        Expanded(
          child: _isHistoryLoading
              ? const Center(child: CircularProgressIndicator())
              : Builder(
                  builder: (context) {
                    final sessions = _groupMessagesBySession(
                      _allHistoryMessages,
                    );

                    if (sessions.isEmpty) {
                      return Center(
                        child: Text(
                          'No history yet',
                          style: GoogleFonts.inter(
                            color: AppConstants.mutedTextColor,
                          ),
                        ),
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 16,
                      ),
                      itemCount: sessions.length,
                      itemBuilder: (context, index) {
                        final session = sessions[index];
                        final isCurrent = session.id == _currentSessionId;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: isCurrent
                                ? AppConstants.primaryColor.withOpacity(0.15)
                                : AppConstants.surfaceOverlay,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isCurrent
                                  ? AppConstants.primaryColor.withOpacity(0.4)
                                  : AppConstants.borderColor,
                              width: 1,
                            ),
                            boxShadow: isCurrent
                                ? [
                                    BoxShadow(
                                      color: AppConstants.primaryColor
                                          .withOpacity(0.1),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ]
                                : [],
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 4,
                            ),
                            onTap: () {
                              _loadSession(session.id, _allHistoryMessages);
                              if (Scaffold.of(context).isDrawerOpen) {
                                Navigator.pop(context);
                              }
                            },
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: isCurrent
                                    ? AppConstants.primaryColor.withOpacity(0.2)
                                    : AppConstants.surfaceOverlay,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.chat_bubble_outline_rounded,
                                color: isCurrent
                                    ? AppConstants.primaryColor
                                    : AppConstants.mutedTextColor,
                                size: 18,
                              ),
                            ),
                            title: Text(
                              session.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                color: isCurrent
                                    ? Colors.white
                                    : Colors.white.withOpacity(0.85),
                                fontSize: 14,
                                fontWeight: isCurrent
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                              ),
                            ),
                            subtitle: Text(
                              _formatDate(session.timestamp),
                              style: GoogleFonts.inter(
                                color: isCurrent
                                    ? AppConstants.mutedTextColor
                                    : AppConstants.faintTextColor,
                                fontSize: 11,
                              ),
                            ),
                            trailing: IconButton(
                              icon: Icon(
                                Icons.delete_outline_rounded,
                                color: AppConstants.errorColor.withOpacity(0.7),
                                size: 20,
                              ),
                              onPressed: () =>
                                  _confirmDeleteSession(session.id),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
        if (kIsWeb)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: _buildDrawerOption(
              icon: Icons.android,
              label: 'Download App',
              onTap: () async {
                final Uri url = Uri.parse(
                  'https://drive.google.com/drive/folders/1FJ-Qp_SPkTmXM_zgAkCpbYZrLM5WoXgd',
                );
                if (await canLaunchUrl(url)) {
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                }
              },
              isSpecial: true,
            ),
          ),
        _buildDrawerFooter(),
      ],
    );
  }

  Widget _buildDrawerHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
      decoration: BoxDecoration(
        color: AppConstants.backgroundColor,
        border: Border(
          bottom: BorderSide(color: AppConstants.borderColor, width: 1),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withOpacity(0.2),
                    width: 2,
                  ),
                ),
                child: ClipOval(
                  child: Image.asset(
                    'assets/images/Icon.png',
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      decoration: const BoxDecoration(
                        gradient: AppConstants.primaryGradient,
                      ),
                      child: const Icon(
                        Icons.smart_toy_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Nyxra AI',
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppConstants.primaryColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppConstants.primaryColor.withOpacity(0.3),
                      ),
                    ),
                    child: Text(
                      '$_userTokens Tokens',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: AppConstants.primaryColor,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildDrawerOption(
            icon: Icons.add_shopping_cart_rounded,
            label: 'Buy Tokens · Coming Soon',
            onTap: null,
            isDisabled: true,
          ),
          const SizedBox(height: 8),
          _buildDrawerOption(
            icon: Icons.chat_bubble_outline_rounded,
            label: 'New Chat',
            onTap: () {
              _startNewChat();
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerOption({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool isSpecial = false,
    bool isDisabled = false,
  }) {
    return InkWell(
      onTap: isDisabled ? null : onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          gradient: isSpecial && !isDisabled
              ? AppConstants.primaryGradient
              : null,
          color: isSpecial && !isDisabled ? null : AppConstants.surfaceOverlay,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSpecial && !isDisabled
                ? Colors.white.withOpacity(0.2)
                : AppConstants.borderColor,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isDisabled ? AppConstants.mutedTextColor : Colors.white,
              size: 20,
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: isDisabled ? AppConstants.mutedTextColor : Colors.white,
                fontWeight: isSpecial ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            if (isSpecial && !isDisabled) ...[
              const Spacer(),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: Colors.white,
                size: 12,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerFooter() {
    final user = FirebaseAuth.instance.currentUser;
    final displayName = user?.displayName ?? 'Guest User';
    final email = user?.email ?? 'Nyxra AI Free Tier';
    final bool isGuest = _currentUserUid == null;

    return InkWell(
      onTap: isGuest ? _handleGoogleSignIn : null,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppConstants.surfaceOverlay,
          border: Border(top: BorderSide(color: AppConstants.borderColor)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppConstants.primaryColor.withOpacity(0.3),
                  width: 1.5,
                ),
              ),
              child: CircleAvatar(
                radius: 18,
                backgroundColor: AppConstants.primaryColor.withOpacity(0.1),
                child: _isSigningIn
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(
                        Icons.person_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isGuest ? 'Guest User' : displayName,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    isGuest
                        ? (_isSigningIn
                              ? 'Signing in...'
                              : 'Tap to sign in & sync')
                        : email,
                    style: GoogleFonts.inter(
                      color: isGuest
                          ? AppConstants.primaryColor
                          : AppConstants.faintTextColor,
                      fontSize: 11,
                      fontWeight: isGuest ? FontWeight.w500 : FontWeight.normal,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'v1.0.1 - Nyxra AI',
                    style: GoogleFonts.inter(
                      color: Colors.white10,
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
            ),
            if (isGuest && !_isSigningIn)
              const Icon(
                Icons.chevron_right_rounded,
                color: AppConstants.faintTextColor,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }

  List<_SessionInfo> _groupMessagesBySession(List<Message> messages) {
    final Map<String, List<Message>> grouped = {};
    for (var msg in messages) {
      grouped.putIfAbsent(msg.sessionId, () => []).add(msg);
    }

    return grouped.entries.map((entry) {
      final sessionMessages = entry.value;
      sessionMessages.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      // Use the first user message as the title, or a default
      final firstUserMsg = sessionMessages.firstWhere(
        (m) => m.isUser,
        orElse: () => sessionMessages.first,
      );

      return _SessionInfo(
        id: entry.key,
        title: firstUserMsg.text,
        timestamp: sessionMessages.last.timestamp,
      );
    }).toList()..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  void _loadSession(String sessionId, List<Message> allMessages) {
    setState(() {
      _generationId++;
      _stopRequested = true;
      _isGenerating = false;
      _isLoading = false;
      _currentSessionId = sessionId;
      _messages.clear();
      _messages.addAll(allMessages.where((m) => m.sessionId == sessionId));
      _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    });
    _scrollToBottom();
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day) {
      return 'Today, ${_formatTime(date)}';
    }
    return '${date.day}/${date.month}/${date.year}';
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  void _confirmClearChat() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppConstants.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Clear All Chats?',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'This will delete your entire chat history. This action cannot be undone.',
          style: GoogleFonts.inter(color: AppConstants.mutedTextColor),
        ),
        actions: [
          TextButton(
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(color: AppConstants.mutedTextColor),
            ),
            onPressed: () => Navigator.pop(context),
          ),
          TextButton(
            child: Text(
              'Clear All',
              style: GoogleFonts.inter(
                color: AppConstants.errorColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            onPressed: () async {
              Navigator.pop(context);
              _generationId++;
              _stopRequested = true;
              if (_currentUserUid == null) {
                await _storageService.clearMessages();
              }
              if (_currentUserUid != null) {
                await _firestoreService.clearMessages(_currentUserUid!);
              }
              if (!mounted) return;
              _startNewChat();
              await _refreshHistory();
            },
          ),
        ],
      ),
    );
  }

  void _confirmDeleteSession(String sessionId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppConstants.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Delete Chat?',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Are you sure you want to delete this chat session?',
          style: GoogleFonts.inter(color: AppConstants.mutedTextColor),
        ),
        actions: [
          TextButton(
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(color: AppConstants.mutedTextColor),
            ),
            onPressed: () => Navigator.pop(context),
          ),
          TextButton(
            child: Text(
              'Delete',
              style: GoogleFonts.inter(
                color: AppConstants.errorColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            onPressed: () async {
              Navigator.pop(context);
              await _deleteSession(sessionId);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _deleteSession(String sessionId) async {
    // 1. Delete from local storage
    await _storageService.deleteSession(sessionId);

    // 2. Delete from Firestore if logged in
    if (_currentUserUid != null) {
      await _firestoreService.deleteSession(_currentUserUid!, sessionId);
    }

    // 3. Update UI
    if (!mounted) return;
    if (_currentSessionId == sessionId) {
      _startNewChat();
    }

    _refreshHistory();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Chat deleted', style: GoogleFonts.inter()),
        backgroundColor: AppConstants.surfaceColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              gradient: AppConstants.primaryGradient,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppConstants.primaryColor.withOpacity(0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.chat_bubble_outline,
              color: Colors.white,
              size: 36,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Start a conversation',
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: AppConstants.textColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Ask me anything!',
            style: GoogleFonts.inter(
              fontSize: 14,
              color: AppConstants.subtextColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.paddingMedium,
        vertical: AppConstants.paddingSmall,
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(shape: BoxShape.circle),
            child: ClipOval(
              child: Image.asset(
                'assets/images/Icon.png',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  decoration: const BoxDecoration(
                    gradient: AppConstants.primaryGradient,
                  ),
                  child: const Icon(
                    Icons.smart_toy_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppConstants.aiMessageColor,
              borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
              border: Border.all(color: AppConstants.borderColor, width: 1),
            ),
            child: const TypingDots(),
          ),
        ],
      ),
    );
  }
}

class TypingDots extends StatefulWidget {
  const TypingDots({super.key});

  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            final delay = index * 0.2;
            final value = ((_controller.value - delay) % 1.0);
            final opacity = (1.0 - (value * 2).abs()).clamp(0.2, 1.0);
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(opacity),
                shape: BoxShape.circle,
              ),
            );
          }),
        );
      },
    );
  }
}

class _SessionInfo {
  final String id;
  final String title;
  final DateTime timestamp;

  _SessionInfo({
    required this.id,
    required this.title,
    required this.timestamp,
  });
}
