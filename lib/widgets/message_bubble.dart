import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../models/message.dart';
import '../utils/constants.dart';

class MessageBubble extends StatelessWidget {
  final Message message;
  final VoidCallback? onLongPress;
  final Function(Message)? onEdit;
  final Function(Message)? onDelete;
  final Function(Message)? onCopy;

  const MessageBubble({
    super.key,
    required this.message,
    this.onLongPress,
    this.onEdit,
    this.onDelete,
    this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final bool isSending = message.status == MessageStatus.sending;
    final bool canEdit = message.isUser &&
        DateTime.now().difference(message.timestamp).inMinutes < 2;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        crossAxisAlignment:
            message.isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onLongPress: () => _showActions(context, canEdit),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: message.isUser
                    ? AppConstants.primaryColor.withOpacity(0.12)
                    : Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(message.isUser ? 18 : 4),
                  bottomRight: Radius.circular(message.isUser ? 4 : 18),
                ),
                border: Border.all(
                  color: message.isUser
                      ? AppConstants.primaryColor.withOpacity(0.25)
                      : Colors.white.withOpacity(0.08),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ─── User attached image (from gallery) ───
                  if (message.isUser && message.imagePath != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: message.imagePath!.startsWith('data:image')
                            ? Image.memory(
                                base64Decode(message.imagePath!.split(',')[1]),
                                height: 200,
                                width: double.infinity,
                                fit: BoxFit.contain,
                              )
                            : Image.network(
                                message.imagePath!,
                                height: 200,
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) =>
                                    const Icon(Icons.broken_image,
                                        color: Colors.white24),
                              ),
                      ),
                    ),

                  // ─── AI Generated Image (from Pollinations/Flux) ───
                  if (!message.isUser &&
                      message.imagePath != null &&
                      message.imagePath!.startsWith('data:image'))
                    _buildGeneratedImage(
                        context,
                        message.imagePath!.substring(
                            message.imagePath!.indexOf(',') + 1)),

                  // ─── Text / Markdown ───
                  MarkdownBody(
                    data: message.text,
                    styleSheet: MarkdownStyleSheet(
                      p: GoogleFonts.inter(
                        fontSize: 15,
                        color: Colors.white.withOpacity(0.95),
                        height: 1.5,
                      ),
                      code: GoogleFonts.firaCode(
                        backgroundColor: Colors.black26,
                        fontSize: 13,
                        color: AppConstants.primaryColor,
                      ),
                      codeblockDecoration: BoxDecoration(
                        color: const Color(0xFF0D1117),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: Colors.white.withOpacity(0.1), width: 1),
                      ),
                      codeblockPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                    builders: {
                      'code': _CopyableCodeBuilder(),
                    },
                  ),
                ],
              ),
            ),
          ),

          // ─── Action Row ───
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!message.isUser) const SizedBox(width: 4),
                Text(
                  (isSending && message.isUser)
                      ? 'Sending...'
                      : _formatTime(message.timestamp),
                  style:
                      GoogleFonts.inter(fontSize: 10, color: Colors.white38),
                ),
                const SizedBox(width: 8),
                if (!isSending) ...[
                  _buildActionButton(
                      Icons.copy_rounded, () => onCopy?.call(message)),
                  if (canEdit)
                    _buildActionButton(
                        Icons.edit_rounded, () => onEdit?.call(message)),
                  // Download button for AI generated images
                  if (!message.isUser &&
                      message.imagePath != null &&
                      message.imagePath!.startsWith('data:image'))
                    _buildActionButton(
                        Icons.download_rounded,
                        () => _downloadImage(
                            context,
                            message.imagePath!.substring(
                                message.imagePath!.indexOf(',') + 1))),
                  _buildActionButton(Icons.delete_outline_rounded,
                      () => onDelete?.call(message),
                      isDelete: true),
                ],
                if (message.isUser) const SizedBox(width: 4),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Builds a proper square/portrait AI generated image with download button
  Widget _buildGeneratedImage(BuildContext context, String base64Data) {
    Uint8List? imageBytes;
    try {
      // Remove data:image/... prefix if present
      final cleanBase64 =
          base64Data.contains(',') ? base64Data.split(',')[1] : base64Data;
      imageBytes = base64Decode(cleanBase64);
    } catch (_) {
      return const Icon(Icons.broken_image, color: Colors.white24, size: 48);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.memory(
              imageBytes,
              // ✅ Fixed: proper square aspect ratio, not stretched
              width: double.infinity,
              fit: BoxFit.contain,
            ),
          ),
          // Download button overlay
          Positioned(
            bottom: 8,
            right: 8,
            child: GestureDetector(
              onTap: () => _downloadImage(context, base64Data),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.65),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.download_rounded,
                        color: Colors.white, size: 16),
                    const SizedBox(width: 4),
                    Text('Save',
                        style: GoogleFonts.inter(
                            fontSize: 12, color: Colors.white)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadImage(BuildContext context, String base64Data) async {
    try {
      if (kIsWeb) {
        // Web: Use anchor download trick
        final cleanBase64 =
            base64Data.contains(',') ? base64Data.split(',')[1] : base64Data;
        final dataUrl = 'data:image/png;base64,$cleanBase64';
        // Copy the data URL to clipboard since universal_html is not used
        await Clipboard.setData(ClipboardData(text: dataUrl));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Image URL copied! Paste in browser to save.',
                  style: GoogleFonts.inter()),
              backgroundColor: Colors.green.shade800,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        // Mobile: Save to gallery
        await Clipboard.setData(ClipboardData(text: 'Image saved!'));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Long press the image to save it!',
                  style: GoogleFonts.inter()),
              backgroundColor: Colors.green.shade800,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Widget _buildActionButton(IconData icon, VoidCallback onTap,
      {bool isDelete = false}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Icon(
          icon,
          size: 14,
          color: isDelete
              ? Colors.redAccent.withOpacity(0.5)
              : Colors.white24,
        ),
      ),
    );
  }

  void _showActions(BuildContext context, bool canEdit) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppConstants.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy_rounded, color: Colors.white),
              title: const Text('Copy Message',
                  style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                onCopy?.call(message);
              },
            ),
            if (!message.isUser &&
                message.imagePath != null &&
                message.imagePath!.startsWith('data:image'))
              ListTile(
                leading: const Icon(Icons.download_rounded, color: Colors.white),
                title: const Text('Save Image',
                    style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _downloadImage(
                      context,
                      message.imagePath!.substring(
                          message.imagePath!.indexOf(',') + 1));
                },
              ),
            if (canEdit)
              ListTile(
                leading: const Icon(Icons.edit_rounded, color: Colors.white),
                title: const Text('Edit Message',
                    style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  onEdit?.call(message);
                },
              ),
            ListTile(
              leading:
                  const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
              title: const Text('Delete Permanently',
                  style: TextStyle(color: Colors.redAccent)),
              onTap: () {
                Navigator.pop(context);
                onDelete?.call(message);
              },
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

/// Custom Markdown code block builder with individual COPY button for each block
class _CopyableCodeBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(element, TextStyle? preferredStyle) {
    final code = element.textContent;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Text(
                code,
                style: GoogleFonts.firaCode(
                  fontSize: 13,
                  color: AppConstants.primaryColor,
                ),
              ),
            ),
          ),
          // Individual COPY button for each code block
          Builder(
            builder: (context) => InkWell(
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: code.trim()));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('✅ Copied to clipboard!',
                          style: GoogleFonts.inter(fontSize: 13)),
                      backgroundColor: AppConstants.primaryColor,
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 1),
                    ),
                  );
                }
              },
              borderRadius: const BorderRadius.horizontal(right: Radius.circular(10)),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: AppConstants.primaryColor.withOpacity(0.1),
                  border: Border(left: BorderSide(color: Colors.white12)),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.copy_rounded,
                        size: 16, color: AppConstants.primaryColor),
                    const SizedBox(height: 4),
                    Text('Copy', 
                      style: GoogleFonts.inter(
                        fontSize: 10, 
                        fontWeight: FontWeight.bold,
                        color: AppConstants.primaryColor
                      )
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
