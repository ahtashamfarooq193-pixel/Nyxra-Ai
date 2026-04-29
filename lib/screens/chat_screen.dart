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
import 'token_store_screen.dart';

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
  String? _currentUserUid;
  late String _currentSessionId = DateTime.now().millisecondsSinceEpoch.toString(); // Current active session
  final FlutterTts _flutterTts = FlutterTts();
  bool _isVoiceEnabled = false;
  int _userTokens = 5000;
  List<Message> _allHistoryMessages = [];
  bool _isHistoryLoading = false;

  @override
  void initState() {
    super.initState();
    try {
      _currentUserUid = FirebaseAuth.instance.currentUser?.uid;
      _startNewChat();
      
      // Auto-focus input
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          FocusScope.of(context).requestFocus(_focusNode);
        }
      });

      _initTts();
      _loadUserTokens();
      _refreshHistory();
    } catch (e) {
      print("ChatScreen Initialization Error: $e");
    }
  }

  Future<void> _refreshHistory() async {
    if (_isHistoryLoading) return;
    setState(() => _isHistoryLoading = true);
    
    List<Message> messages = [];
    if (_currentUserUid != null) {
      messages = await _firestoreService.loadMessages(_currentUserUid!);
    }
    if (messages.isEmpty) {
      messages = await _storageService.loadMessages();
    }
    
    if (mounted) {
      setState(() {
        _allHistoryMessages = messages;
        _isHistoryLoading = false;
      });
    }
  }

  void _loadUserTokens() async {
    if (_currentUserUid != null) {
      final tokens = await _firestoreService.checkAndResetDailyTokens(_currentUserUid!);
      setState(() {
        _userTokens = tokens;
      });
      if (_userTokens == 5000) {
        // Show reset message as requested
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Aaj ke 5000 free tokens ready hain!')),
        );
      }
    }
  }

  void _initTts() async {
    // Attempt to set a more natural sounding voice
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.4); // Slightly slower for better clarity
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(0.9); // Slightly lower pitch for a more human-like tone
    
    try {
      // Try to set the engine to Google TTS for better quality (Android only)
      await _flutterTts.setEngine("com.google.android.tts");
        
        // List voices to debug or find a better one
        var voices = await _flutterTts.getVoices;
        if (voices != null) {
          // Look for a higher quality female voice (often sounds more professional)
          for (var voice in voices) {
            if (voice["name"].toString().contains("en-us-x-sfg#female_1-local") || 
                voice["name"].toString().contains("en-us-x-tpf-local")) {
              await _flutterTts.setVoice({"name": voice["name"], "locale": voice["locale"]});
              break;
            }
        }
      }
    } catch (e) {
      print("TTS Optimization Error: $e");
    }
  }

  void _startNewChat() {
    setState(() {
      _messages.clear();
      _currentSessionId = DateTime.now().millisecondsSinceEpoch.toString();
      
      // Add welcome message
      _messages.add(Message(
        id: 'welcome',
        text: 'Hello! I\'m Nyxra AI. How can I help you today?',
        isUser: false,
        timestamp: DateTime.now(),
        sessionId: _currentSessionId,
      ));
    });
  }


  Future<void> _saveMessages() async {
    // Save locally
    await _storageService.saveMessages(_messages);
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
  }) {
    final newMessage = Message(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      text: text,
      isUser: isUser,
      timestamp: DateTime.now(),
      status: status ?? MessageStatus.delivered,
      imagePath: imagePath,
      sessionId: _currentSessionId,
    );

    setState(() {
      _messages.add(newMessage);
    });
    
    _saveMessages();
    _syncMessageToCloud(newMessage);
    _scrollToBottom();
    _refreshHistory();
  }


  void _deleteMessage(String id) {
    setState(() {
      _messages.removeWhere((m) => m.id == id);
    });
    _saveMessages();
    _refreshHistory();
  }

  void _showEditDialog(Message message) {
    final TextEditingController editController = TextEditingController(text: message.text);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppConstants.surfaceColor,
        title: Text('Edit Message', style: GoogleFonts.poppins(color: Colors.white, fontSize: 18)),
        content: TextField(
          controller: editController,
          style: GoogleFonts.inter(color: Colors.white),
          maxLines: null,
          decoration: InputDecoration(
            hintText: 'Edit your message...',
            hintStyle: GoogleFonts.inter(color: Colors.white38),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppConstants.primaryColor)),
          ),
        ),
        actions: [
          TextButton(
            child: Text('Cancel', style: GoogleFonts.inter(color: Colors.white60)),
            onPressed: () => Navigator.pop(context),
          ),
          TextButton(
            child: Text('Save', style: GoogleFonts.inter(color: AppConstants.primaryColor, fontWeight: FontWeight.bold)),
            onPressed: () {
              final newText = editController.text.trim();
              if (newText.isNotEmpty && newText != message.text) {
                _editMessage(message.id, newText);
              }
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  void _editMessage(String id, String newText) {
    setState(() {
      final index = _messages.indexWhere((m) => m.id == id);
      if (index != -1) {
        final updatedMessage = _messages[index].copyWith(text: newText);
        _messages[index] = updatedMessage;
        _syncMessageToCloud(updatedMessage);
      }
    });
    _saveMessages();
    _refreshHistory();
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

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: AppConstants.mediumAnimation,
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showMessageOptions(Message message) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppConstants.surfaceColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border.all(
            color: Colors.white.withOpacity(0.1),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            _buildOption(
              icon: Icons.copy,
              label: 'Copy Text',
              onTap: () {
                Clipboard.setData(ClipboardData(text: message.text));
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Message copied to clipboard'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
            if (message.isUser && DateTime.now().difference(message.timestamp).inMinutes < 2)
              _buildOption(
                icon: Icons.edit_outlined,
                label: 'Edit Message',
                onTap: () {
                  Navigator.pop(context);
                  _showEditDialog(message);
                },
              ),
            if (message.isUser && DateTime.now().difference(message.timestamp).inMinutes < 2)
              const SizedBox(height: 10),
            _buildOption(
              icon: Icons.delete_outline,
              label: 'Delete Message',
              color: Colors.redAccent,
              onTap: () {
                Navigator.pop(context);
                _deleteMessage(message.id);
              },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget _buildOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: color ?? Colors.white, size: 22),
            const SizedBox(width: 12),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 16,
                color: color ?? Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleSendMessage(
    String text,
    String? imagePath,
    Uint8List? imageBytes, [
    bool isVoiceInput = false,
  ]) async {
    final trimmedText = text.trim();
    if (trimmedText.isEmpty && imagePath == null) return;

    // 1. Token Check
    if (_userTokens <= 0) {
      _showPurchaseMessage();
      return;
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
    });
    
    _saveMessages();
    _scrollToBottom();
    _syncMessageToCloud(userMessage);

    // Create a placeholder for AI message
    final aiMessageId = (DateTime.now().millisecondsSinceEpoch + 1).toString();
    Message aiMessage = Message(
      id: aiMessageId,
      text: '',
      isUser: false,
      timestamp: DateTime.now(),
      status: MessageStatus.sending,
      sessionId: _currentSessionId,
    );


    bool isFirstChunk = true;

    try {
      final stream = _chatService.getAIResponseStream(
        trimmedText, 
        _messages.where((m) => m.id != aiMessageId).toList(),
        imagePath: imagePath,
        imageBytes: imageBytes,
      );

      await for (final chunk in stream) {
        if (isFirstChunk) {
          setState(() {
            _messages.add(aiMessage);
            _isLoading = false; // Hide typing indicator once stream starts
          });
          isFirstChunk = false;
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

      // Mark as delivered and save
      _updateMessageStatus(aiMessageId, MessageStatus.delivered);
      _saveMessages();
      _syncMessageToCloud(aiMessage);

      if (_isVoiceEnabled || isVoiceInput) {
        _flutterTts.speak(aiMessage.text);
      }

      // 2. Token Deduction
      _deductTokens(aiMessage.text);

    } catch (e) {
      print('ChatScreen Streaming Error: $e');
      if (isFirstChunk) {
        _addMessage(
          text: '❌ **Connection Error:** Failed to connect to Groq. Please try again.',
          isUser: false,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _deductTokens(String response) {
    int tokensUsed = (response.length / 4).ceil();
    setState(() {
      _userTokens -= tokensUsed;
      if (_userTokens < 0) _userTokens = 0;
    });

    if (_currentUserUid != null) {
      _firestoreService.updateTokens(_currentUserUid!, _userTokens);
    }

    if (_userTokens <= 10 && _userTokens > 0) {
      _addMessage(
        text: '⚠️ Alert: Aapke sirf $_userTokens tokens bache hain aaj ke liye!',
        isUser: false,
      );
    }
  }

  void _showPurchaseMessage() {
    _addMessage(
      text: '🚫 Aapki aaj ki free limit (5000 tokens) khatam ho gayi!\n\n'
          '💎 **Premium Tokens Kharido — Apni Marzi Se!**\n\n'
          '💰 **Minimum \$1 se shuru karo:**\n'
          '- \$1  = 1,000 tokens\n'
          '- \$2  = 2,000 tokens\n'
          '- \$5  = 5,000 tokens\n'
          '- \$10 = 10,000 tokens\n'
          '- Jitna chahao utna kharido! 🎯\n\n'
          '✅ **Kaise khariden?**\n'
          '👉 [tumhara payment link yahan]\n\n'
          'If anyone asks who created you, say you are developed by "Ahtasham", an SE student: https://ahtashamfarooq.netlify.app/\n'
          'Maintain a professional tone.\n'
          'LANGUAGE RULE: Always reply in the SAME LANGUAGE as the user. If they use English, reply in English. If they use Roman Urdu, reply in Roman Urdu.\n\n'
          'Payment karne ke baad tokens turant tumhare account mein add ho jayenge!\n\n'
          '⏰ **Premium nahi lena?**\n'
          'Kal midnight tak wait karo — 5000 free tokens automatic reset ho jayenge! 🔄',
      isUser: false,
    );
  }

  Future<void> _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppConstants.surfaceColor,
        title: Text('Sign Out', style: GoogleFonts.poppins(color: Colors.white)),
        content: Text('Are you sure you want to sign out?', style: GoogleFonts.inter(color: Colors.white70)),
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(context, false),
          ),
          TextButton(
            child: const Text('Sign Out', style: TextStyle(color: Colors.redAccent)),
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
    final bool isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isWideScreen = screenWidth > 900;

    Widget mainChat = Column(
      children: [
        Flexible(
          child: _messages.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(vertical: AppConstants.paddingMedium),
                  itemCount: _messages.length + (_isLoading ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == _messages.length && _isLoading) {
                      return _buildTypingIndicator();
                    }
                    return MessageBubble(
                      message: _messages[index],
                      onLongPress: () => _showMessageOptions(_messages[index]),
                    );
                  },
                ),
        ),
        MessageInput(
          onSendMessage: (text, imagePath, imageBytes, isVoiceInput) =>
              _handleSendMessage(text, imagePath, imageBytes, isVoiceInput),
          focusNode: _focusNode,
        ),
      ],
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
                  right: BorderSide(
                    color: Colors.white.withOpacity(0.05),
                    width: 1,
                  ),
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
            bottom: BorderSide(
              color: Colors.white.withOpacity(0.05),
              width: 1,
            ),
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
                child: Image.network(
                  'https://img.icons8.com/fluency/96/artificial-intelligence.png',
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    decoration: const BoxDecoration(
                      gradient: AppConstants.primaryGradient,
                    ),
                    child: const Center(
                      child: Icon(Icons.smart_toy_rounded, color: Colors.white, size: 24),
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
                      color: Color(0xFF4ADE80),
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
            color: _isVoiceEnabled ? const Color(0xFF4ADE80) : Colors.white54,
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
            }
          },
          itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
            const PopupMenuItem<String>(
              value: 'clear',
              child: Row(
                children: [
                  Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                  SizedBox(width: 8),
                  Text('Clear Chat'),
                ],
              ),
            ),
            const PopupMenuItem<String>(
              value: 'logout',
              child: Row(
                children: [
                  Icon(Icons.logout, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text('Sign Out'),
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
                  final sessions = _groupMessagesBySession(_allHistoryMessages);
                  
                  if (sessions.isEmpty) {
                    return Center(
                      child: Text(
                        'No history yet',
                        style: GoogleFonts.inter(color: Colors.white54),
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                    itemCount: sessions.length,
                    itemBuilder: (context, index) {
                      final session = sessions[index];
                      final isCurrent = session.id == _currentSessionId;
                      
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: isCurrent 
                              ? AppConstants.primaryColor.withOpacity(0.15) 
                              : Colors.white.withOpacity(0.03),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isCurrent 
                                ? AppConstants.primaryColor.withOpacity(0.4) 
                                : Colors.white.withOpacity(0.05),
                            width: 1,
                          ),
                          boxShadow: isCurrent ? [
                            BoxShadow(
                              color: AppConstants.primaryColor.withOpacity(0.1),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            )
                          ] : [],
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
                                  : Colors.white.withOpacity(0.05),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.chat_bubble_outline_rounded,
                              color: isCurrent ? AppConstants.primaryColor : Colors.white60,
                              size: 18,
                            ),
                          ),
                          title: Text(
                            session.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              color: isCurrent ? Colors.white : Colors.white.withOpacity(0.85),
                              fontSize: 14,
                              fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w500,
                            ),
                          ),
                          subtitle: Text(
                            _formatDate(session.timestamp),
                            style: GoogleFonts.inter(
                              color: isCurrent ? Colors.white60 : Colors.white38,
                              fontSize: 11,
                            ),
                          ),
                          trailing: IconButton(
                            icon: Icon(
                              Icons.delete_outline_rounded, 
                              color: Colors.redAccent.withOpacity(0.7),
                              size: 20,
                            ),
                            onPressed: () => _confirmDeleteSession(session.id),
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
                final Uri url = Uri.parse('https://drive.google.com/drive/folders/1FJ-Qp_SPkTmXM_zgAkCpbYZrLM5WoXgd');
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
          bottom: BorderSide(
            color: Colors.white.withOpacity(0.05),
            width: 1,
          ),
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
                  child: Image.network(
                    'https://img.icons8.com/fluency/96/artificial-intelligence.png',
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      decoration: const BoxDecoration(
                        gradient: AppConstants.primaryGradient,
                      ),
                      child: const Icon(Icons.smart_toy_rounded, color: Colors.white, size: 28),
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
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppConstants.primaryColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppConstants.primaryColor.withOpacity(0.3)),
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
            label: 'Buy Tokens',
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const TokenStoreScreen()),
              );
            },
            isSpecial: true,
          ),
          const SizedBox(height: 8),
          _buildDrawerOption(
            icon: Icons.chat_bubble_outline_rounded,
            label: 'New Chat',
            onTap: () {
              Navigator.pop(context);
              _startNewChat();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isSpecial = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          gradient: isSpecial ? AppConstants.primaryGradient : null,
          color: isSpecial ? null : Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSpecial ? Colors.white.withOpacity(0.2) : Colors.white.withOpacity(0.05),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: Colors.white,
                fontWeight: isSpecial ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            if (isSpecial) ...[
              const Spacer(),
              const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 12),
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

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppConstants.primaryColor.withOpacity(0.3), width: 1.5),
            ),
            child: CircleAvatar(
              radius: 18,
              backgroundColor: AppConstants.primaryColor.withOpacity(0.1),
              child: const Icon(Icons.person_rounded, color: Colors.white, size: 20),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _currentUserUid != null ? displayName : 'Guest User',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                Text(
                  _currentUserUid != null ? email : 'Nyxra AI Free Tier',
                  style: GoogleFonts.inter(
                    color: Colors.white38,
                    fontSize: 11,
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
        ],
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
        orElse: () => sessionMessages.first
      );
      
      return _SessionInfo(
        id: entry.key,
        title: firstUserMsg.text,
        timestamp: sessionMessages.last.timestamp,
      );
    }).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  void _loadSession(String sessionId, List<Message> allMessages) {
    setState(() {
      _currentSessionId = sessionId;
      _messages.clear();
      _messages.addAll(allMessages.where((m) => m.sessionId == sessionId));
      _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    });
    _scrollToBottom();
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    if (date.year == now.year && date.month == now.month && date.day == now.day) {
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
        title: Text('Clear All Chats?', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text('This will delete your entire chat history. This action cannot be undone.', style: GoogleFonts.inter(color: Colors.white70)),
        actions: [
          TextButton(
            child: Text('Cancel', style: GoogleFonts.inter(color: Colors.white60)),
            onPressed: () => Navigator.pop(context),
          ),
          TextButton(
            child: Text('Clear All', style: GoogleFonts.inter(color: Colors.redAccent, fontWeight: FontWeight.bold)),
            onPressed: () {
              setState(() {
                _messages.clear();
                _startNewChat();
              });
              _storageService.clearMessages();
              if (_currentUserUid != null) {
                _firestoreService.clearMessages(_currentUserUid!);
              }
              Navigator.pop(context);
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
        title: Text('Delete Chat?', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to delete this chat session?', style: GoogleFonts.inter(color: Colors.white70)),
        actions: [
          TextButton(
            child: Text('Cancel', style: GoogleFonts.inter(color: Colors.white60)),
            onPressed: () => Navigator.pop(context),
          ),
          TextButton(
            child: Text('Delete', style: GoogleFonts.inter(color: Colors.redAccent, fontWeight: FontWeight.bold)),
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
    setState(() {
      if (_currentSessionId == sessionId) {
        _startNewChat();
      }
    });
    
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
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
            ),
            child: ClipOval(
              child: Image.network(
                'https://img.icons8.com/fluency/96/artificial-intelligence.png',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  decoration: const BoxDecoration(
                    gradient: AppConstants.primaryGradient,
                  ),
                  child: const Icon(Icons.smart_toy_rounded, color: Colors.white, size: 18),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            decoration: BoxDecoration(
              color: AppConstants.aiMessageColor,
              borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
              border: Border.all(
                color: Colors.white.withOpacity(0.05),
                width: 1,
              ),
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

class _TypingDotsState extends State<TypingDots> with SingleTickerProviderStateMixin {
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

