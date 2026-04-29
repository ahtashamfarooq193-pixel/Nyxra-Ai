import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../models/message.dart';
import '../utils/constants.dart';

class MessageBubble extends StatelessWidget {
  final Message message;
  final VoidCallback? onLongPress;

  const MessageBubble({
    super.key,
    required this.message,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final bool isSending = message.status == MessageStatus.sending;

    return GestureDetector(
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Column(
          crossAxisAlignment: message.isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
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
                boxShadow: message.isUser ? [
                  BoxShadow(
                    color: AppConstants.primaryColor.withOpacity(0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ] : [],
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
                            : (kIsWeb 
                                ? Image.network(
                                    message.imagePath!,
                                    height: 150,
                                    fit: BoxFit.cover,
                                  )
                                : Image.network( 
                                    message.imagePath!,
                                    height: 150,
                                    fit: BoxFit.cover,
                                  )),
                      ),
                    ),
                  MarkdownBody(
                    data: message.text,
                    styleSheet: MarkdownStyleSheet(
                      p: GoogleFonts.inter(
                        fontSize: 15,
                        color: Colors.white.withOpacity(0.95),
                        height: 1.5,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 0.2,
                      ),
                      strong: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                      em: const TextStyle(fontStyle: FontStyle.italic),
                      listBullet: const TextStyle(color: Colors.white70),
                      code: GoogleFonts.firaCode(
                        backgroundColor: Colors.black26,
                        fontSize: 13,
                        color: Colors.white.withOpacity(0.8),
                      ),
                      codeblockDecoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      blockquote: const TextStyle(color: Colors.white60),
                      blockquoteDecoration: const BoxDecoration(
                        border: Border(left: BorderSide(color: Colors.white24, width: 4)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4, right: 4),
              child: Text(
                (isSending && message.isUser) ? 'Sending...' : _formatTime(message.timestamp),
                style: GoogleFonts.inter(
                  fontSize: 10,
                  color: Colors.white38,
                  fontWeight: FontWeight.w400,
                ),
              ),
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
