import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../models/message.dart';
import '../widgets/message_bubble.dart';
import '../widgets/message_input.dart';
import '../services/chat_service.dart';
import '../services/storage_service.dart';
import '../services/firestore_service.dart';
import '../utils/constants.dart';
import '../splashscreen.dart';
import 'package:flutter_tts/flutter_tts.dart';

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
  late String _currentSessionId; // Current active session
  final FlutterTts _flutterTts = FlutterTts();
  bool _isVoiceEnabled = false;

  @override
  void initState() {
    super.initState();
    _currentUserUid = FirebaseAuth.instance.currentUser?.uid;
    _startNewChat();
    
    // Auto-focus input
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).requestFocus(_focusNode);
    });

    _initTts();
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
        text: 'Hello! I\'m Zenith AI. How can I help you today?',
        isUser: false,
        timestamp: DateTime.now(),
        sessionId: _currentSessionId,
      ));
    });
  }


  Future<void> _loadMessages() async {
    // 1. Try loading from Firestore if user is logged in
    List<Message> messages = [];
    if (_currentUserUid != null) {
      messages = await _firestoreService.loadMessages(_currentUserUid!);
    }

    // 2. If Firestore is empty, fallback to local storage
    if (messages.isEmpty) {
      messages = await _storageService.loadMessages();
    }

    if (mounted) {
      setState(() {
        _messages.clear();
        _messages.addAll(messages);
      });
      
      if (_messages.isEmpty) {
        // Add welcome message if empty
        _addMessage(
          text: 'Hello! I\'m Shamii Assistant. How can I help you today?',
          isUser: false,
        );
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      }
    }
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
  }


  void _deleteMessage(String id) {
    setState(() {
      _messages.removeWhere((m) => m.id == id);
    });
    _saveMessages();
    // Note: In a full implementation, we would also delete from Firestore
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

  Future<void> _handleSendMessage(String text, String? imagePath) async {
    final trimmedText = text.trim();
    if (trimmedText.isEmpty && imagePath == null) return;

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

      if (_isVoiceEnabled) {
        _flutterTts.speak(aiMessage.text);
      }

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
    final double screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: AppConstants.backgroundColor,
      resizeToAvoidBottomInset: true,
      appBar: isLandscape ? null : AppBar(
        elevation: 0,
        backgroundColor: AppConstants.backgroundColor.withOpacity(0.8),
        surfaceTintColor: Colors.transparent,
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
                  'Zenith AI',
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
      ),
      drawer: _buildHistoryDrawer(),
      body: Column(
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
            onSendMessage: _handleSendMessage,
            focusNode: _focusNode,
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryDrawer() {
    return Drawer(
      backgroundColor: AppConstants.backgroundColor,
      child: Column(
        children: [
          _buildDrawerHeader(),
          Expanded(
            child: FutureBuilder<List<Message>>(
              future: _currentUserUid != null 
                  ? _firestoreService.loadMessages(_currentUserUid!) 
                  : _storageService.loadMessages(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                
                final allMessages = snapshot.data ?? [];
                final sessions = _groupMessagesBySession(allMessages);
                
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
                          _loadSession(session.id, allMessages);
                          Navigator.pop(context);
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
          _buildDrawerFooter(),
        ],
      ),
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
        crossAxisAlignment: CrossAxisAlignment.start,
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
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Zenith AI',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    'Chat History',
                    style: GoogleFonts.inter(
                      color: AppConstants.primaryColor.withOpacity(0.8),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          InkWell(
            onTap: () {
              _startNewChat();
              Navigator.pop(context);
            },
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.add_rounded, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'New Chat',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerFooter() {
    final user = FirebaseAuth.instance.currentUser;
    final displayName = user?.displayName ?? 'Guest User';
    final email = user?.email ?? 'Zenith AI Free Tier';

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
                  _currentUserUid != null ? email : 'Zenith AI Free Tier',
                  style: GoogleFonts.inter(
                    color: Colors.white38,
                    fontSize: 11,
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
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
          },
        );
      }),
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

