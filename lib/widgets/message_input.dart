import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../utils/constants.dart';

class MessageInput extends StatefulWidget {
  final Function(String, String?) onSendMessage;
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
  bool _isTyping = false;
  File? _pickedImage;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      if (Platform.isAndroid) {
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
          _pickedImage = File(image.path);
        });
      }
    } catch (e) {
      print('Error picking image: $e');
    }
  }

  void _removeImage() {
    setState(() {
      _pickedImage = null;
    });
  }

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isNotEmpty || _pickedImage != null) {
      widget.onSendMessage(text, _pickedImage?.path);
      _controller.clear();
      setState(() {
        _isTyping = false;
        _pickedImage = null;
      });
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
            if (_pickedImage != null)
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
                      child: Image.file(
                        _pickedImage!,
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
                        color: Colors.white.withOpacity(0.06),
                        width: 1,
                      ),
                    ),
                    child: TextField(
                      controller: _controller,
                      focusNode: widget.focusNode,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 14,
                      ),
                      maxLines: MediaQuery.of(context).orientation == Orientation.landscape ? 2 : 5,
                      minLines: 1,
                      decoration: InputDecoration(
                        hintText: 'Type a message...',
                        hintStyle: GoogleFonts.inter(
                          color: Colors.white.withOpacity(0.25),
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
                GestureDetector(
                  onTap: _handleSend,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: (_isTyping || _pickedImage != null)
                            ? AppConstants.primaryColor
                            : Colors.white.withOpacity(0.1),
                        width: 1.5,
                      ),
                      boxShadow: (_isTyping || _pickedImage != null) ? [
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
                        color: (_isTyping || _pickedImage != null)
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

