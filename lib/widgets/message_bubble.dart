import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
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
        crossAxisAlignment: message.isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
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
                  if (message.imagePath != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: message.imagePath!.startsWith('data:image')
                            ? Image.memory(
                                base64Decode(message.imagePath!.split(',')[1]),
                                height: 200,
                                width: double.infinity,
                                fit: BoxFit.cover,
                              )
                            : Image.network(
                                message.imagePath!,
                                height: 150,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image, color: Colors.white24),
                              ),
                      ),
                    ),
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
                        color: Colors.white.withOpacity(0.8),
                      ),
                      codeblockDecoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Action Buttons for Desktop / Quick Access
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!message.isUser) const SizedBox(width: 4),
                Text(
                  (isSending && message.isUser) ? 'Sending...' : _formatTime(message.timestamp),
                  style: GoogleFonts.inter(fontSize: 10, color: Colors.white38),
                ),
                const SizedBox(width: 8),
                if (!isSending) ...[
                  _buildActionButton(Icons.copy_rounded, () => onCopy?.call(message)),
                  if (canEdit) _buildActionButton(Icons.edit_rounded, () => onEdit?.call(message)),
                  _buildActionButton(Icons.delete_outline_rounded, () => onDelete?.call(message), isDelete: true),
                ],
                if (message.isUser) const SizedBox(width: 4),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(IconData icon, VoidCallback onTap, {bool isDelete = false}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Icon(
          icon,
          size: 14,
          color: isDelete ? Colors.redAccent.withOpacity(0.5) : Colors.white24,
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
              title: const Text('Copy Message', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                onCopy?.call(message);
              },
            ),
            if (canEdit)
              ListTile(
                leading: const Icon(Icons.edit_rounded, color: Colors.white),
                title: const Text('Edit Message', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  onEdit?.call(message);
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
              title: const Text('Delete Permanently', style: TextStyle(color: Colors.redAccent)),
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
