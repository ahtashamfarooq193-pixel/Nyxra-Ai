import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../utils/constants.dart';
import 'dart:io' as io;

class MessageInput extends StatefulWidget {
  final Function(String, String?, Uint8List?, bool) onSendMessage;
  final FocusNode? focusNode;

  const MessageInput({
    super.key,
    required this.onSendMessage,
    this.focusNode,
  });

  @override
  State<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<MessageInput> {
  final TextEditingController _controller = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isTyping = false;
  bool _isListening = false;
  XFile? _pickedXFile;

  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    
    // Add listener to controller for ultimate Enter-to-send detection
    _controller.addListener(_onControllerChanged);
    
    _initSpeech();
  }

  void _onControllerChanged() {
    final text = _controller.text;
    if (text.endsWith('\n')) {
      final bool isShiftPressed = HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.shiftLeft) || 
                                  HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.shiftRight);
      
      if (!isShiftPressed && (kIsWeb || (Theme.of(context).platform != TargetPlatform.android && Theme.of(context).platform != TargetPlatform.iOS))) {
        // Remove the newline and send
        _controller.text = text.substring(0, text.length - 1);
        _handleSend();
      }
    }
  }

  void _initSpeech() async {
    try {
      await _speech.initialize();
      setState(() {});
    } catch (e) {
      print('Speech initialization error: $e');
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      if (!kIsWeb) {
        // Permission handling for mobile
        var status = await Permission.photos.request();
        if (status.isDenied || status.isPermanentlyDenied) {
          status = await Permission.storage.request();
        }
        if (status.isPermanentlyDenied) {
          openAppSettings();
          return;
        }
      }

      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        setState(() {
          _pickedXFile = image;
        });
      }
    } catch (e) {
      print('Error picking image: $e');
    }
  }

  void _removeImage() {
    setState(() {
      _pickedXFile = null;
    });
  }

  Future<void> _handleSend({bool isVoiceInput = false}) async {
    final text = _controller.text.trim();
    if (text.isNotEmpty || _pickedXFile != null) {
      Uint8List? imageBytes;
      if (_pickedXFile != null) {
        imageBytes = await _pickedXFile!.readAsBytes();
      }

      widget.onSendMessage(text, _pickedXFile?.path, imageBytes, isVoiceInput);
      _controller.clear();
      setState(() {
        _isTyping = false;
        _pickedXFile = null;
      });
    }
  }

  void _listen() async {
    if (!_isListening) {
      if (!kIsWeb) {
        // Check microphone permission for mobile
        var status = await Permission.microphone.status;
        if (status.isDenied) {
          status = await Permission.microphone.request();
          if (status.isDenied) return;
        }
        if (status.isPermanentlyDenied) {
          openAppSettings();
          return;
        }
      }

      bool available = await _speech.initialize(
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            setState(() => _isListening = false);
          }
        },
        onError: (error) => setState(() => _isListening = false),
      );
      
      if (available) {
        setState(() => _isListening = true);
        _speech.listen(
          onResult: (val) {
            setState(() {
              _controller.text = val.recognizedWords;
              _isTyping = _controller.text.isNotEmpty;
              if (val.finalResult) {
                _isListening = false;
                _handleSend(isVoiceInput: true);
              }
            });
          },
        );
      }
    } else {
      setState(() => _isListening = false);
      _speech.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isLandscape ? 6 : 10, 
        vertical: isLandscape ? 4 : 8
      ),
      decoration: BoxDecoration(
        color: AppConstants.surfaceColor.withOpacity(0.98),
        border: Border(
          top: BorderSide(
            color: Colors.white.withOpacity(0.05),
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_pickedXFile != null)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: kIsWeb 
                        ? Image.network(
                            _pickedXFile!.path,
                            height: 80,
                            width: 80,
                            fit: BoxFit.cover,
                          )
                        : Image.file(
                            io.File(_pickedXFile!.path),
                            height: 80,
                            width: 80,
                            fit: BoxFit.cover,
                          ),
                    ),
                    Positioned(
                      top: 2,
                      right: 2,
                      child: GestureDetector(
                        onTap: _removeImage,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(
                            color: Colors.black87,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close, size: 12, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                  child: IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      Icons.add_rounded,
                      color: Colors.white.withOpacity(0.8),
                      size: 26,
                    ),
                    onPressed: _pickImage,
                  ),
                ),
                Flexible(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: _isListening 
                          ? AppConstants.primaryColor.withOpacity(0.5)
                          : Colors.white.withOpacity(0.06),
                        width: 1,
                      ),
                    ),
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                        maxLines: null,
                        minLines: 1,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _handleSend(),
                        decoration: InputDecoration(
                          hintText: _isListening ? 'Listening...' : 'Type a message...',
                          hintStyle: GoogleFonts.inter(
                            color: _isListening 
                              ? AppConstants.primaryColor.withOpacity(0.5)
                              : Colors.white.withOpacity(0.25),
                            fontSize: 14,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                        onChanged: (value) {
                          setState(() {
                            _isTyping = value.trim().isNotEmpty;
                          });
                        },
                      ),
                  ),
                ),
                const SizedBox(width: 10),
                if (!_isTyping && _pickedXFile == null)
                  GestureDetector(
                    onTap: _listen,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: _isListening 
                          ? AppConstants.primaryColor.withOpacity(0.1)
                          : Colors.transparent,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _isListening 
                            ? AppConstants.primaryColor 
                            : Colors.white.withOpacity(0.1),
                          width: 1.5,
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          _isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                          color: _isListening 
                            ? AppConstants.primaryColor 
                            : Colors.white.withOpacity(0.4),
                          size: 22,
                        ),
                      ),
                    ),
                  )
                else
                  GestureDetector(
                    onTap: () => _handleSend(),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: (_isTyping || _pickedXFile != null)
                              ? AppConstants.primaryColor
                              : Colors.white.withOpacity(0.1),
                          width: 1.5,
                        ),
                        boxShadow: (_isTyping || _pickedXFile != null) ? [
                          BoxShadow(
                            color: AppConstants.primaryColor.withOpacity(0.15),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          )
                        ] : [],
                      ),
                      child: Center(
                        child: Icon(
                          Icons.arrow_upward_rounded,
                          color: (_isTyping || _pickedXFile != null)
                              ? AppConstants.primaryColor
                              : Colors.white.withOpacity(0.2),
                          size: 22,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );

  }
}

