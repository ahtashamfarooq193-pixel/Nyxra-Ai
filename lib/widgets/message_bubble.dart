import 'dart:convert';
import 'dart:io' as io;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../models/message.dart';
import '../utils/constants.dart';
import 'package:universal_html/html.dart' as html;
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

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
    final bool canEdit =
        message.isUser &&
        DateTime.now().difference(message.timestamp).inMinutes < 2;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        crossAxisAlignment: message.isUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          GestureDetector(
            // Only right-click (web) opens the actions menu here — long-press is
            // intentionally left free so it triggers native text selection
            // (drag handles + system Copy toolbar) instead of stealing the
            // gesture. Copy/Edit/Delete are still always reachable via the
            // action row below, and via long-press on attached images.
            onSecondaryTapDown: kIsWeb
                ? (details) => _showActionsAtPosition(
                    context,
                    canEdit,
                    details.globalPosition,
                  )
                : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: message.isUser
                    ? AppConstants.primaryColor.withOpacity(0.12)
                    : AppConstants.surfaceOverlay,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(message.isUser ? 18 : 4),
                  bottomRight: Radius.circular(message.isUser ? 4 : 18),
                ),
                border: Border.all(
                  color: message.isUser
                      ? AppConstants.primaryColor.withOpacity(0.25)
                      : AppConstants.borderColor,
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
                      child: GestureDetector(
                        onLongPress: () => _showActions(context, canEdit),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: message.imagePath!.startsWith('data:image')
                              ? Image.memory(
                                  base64Decode(
                                    message.imagePath!.split(',')[1],
                                  ),
                                  height: 200,
                                  width: double.infinity,
                                  fit: BoxFit.contain,
                                )
                              : Image.network(
                                  message.imagePath!,
                                  height: 200,
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) =>
                                      const Icon(
                                        Icons.broken_image,
                                        color: Colors.white24,
                                      ),
                                ),
                        ),
                      ),
                    ),

                  // ─── AI Generated Image (from Pollinations/Flux) ───
                  if (!message.isUser && message.imagePath != null)
                    GestureDetector(
                      onLongPress: () => _showActions(context, canEdit),
                      onTap: () =>
                          _showImagePreview(context, message.imagePath!),
                      child: _buildGeneratedImage(context, message.imagePath!),
                    ),

                  if (!message.isUser && message.documentBase64 != null)
                    _buildDocumentAttachment(context),

                  // ─── Text / Markdown - WITH SELECTION & LONG PRESS MENU ───
                  MarkdownBody(
                    data: message.text,
                    selectable:
                        true, // ✅ Enable native text selection on long press!
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
                          color: Colors.white.withOpacity(0.1),
                          width: 1,
                        ),
                      ),
                      codeblockPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    builders: {'code': _CopyableCodeBuilder()},
                    onTapLink: (text, href, title) async {
                      if (href == null) return;
                      final uri = Uri.tryParse(href);
                      if (uri == null ||
                          !(uri.scheme == 'http' || uri.scheme == 'https')) {
                        return;
                      }
                      await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      );
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
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: AppConstants.faintTextColor,
                  ),
                ),
                const SizedBox(width: 8),
                if (!isSending) ...[
                  _buildActionButton(
                    Icons.copy_rounded,
                    () => onCopy?.call(message),
                  ),
                  if (canEdit)
                    _buildActionButton(
                      Icons.edit_rounded,
                      () => onEdit?.call(message),
                    ),
                  // Download button for AI generated images
                  if (!message.isUser && message.imagePath != null)
                    _buildActionButton(
                      Icons.download_rounded,
                      () => _downloadImage(context, message.imagePath!),
                    ),
                  if (!message.isUser && message.documentBase64 != null)
                    _buildActionButton(
                      Icons.file_download_rounded,
                      () => _downloadDocument(context),
                    ),
                  _buildActionButton(
                    Icons.delete_outline_rounded,
                    () => onDelete?.call(message),
                    isDelete: true,
                  ),
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
  Widget _buildGeneratedImage(BuildContext context, String imagePath) {
    final isDataImage = imagePath.startsWith('data:image');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = constraints.hasBoundedWidth
              ? constraints.maxWidth
              : 420.0;
          final previewWidth = availableWidth > 420.0 ? 420.0 : availableWidth;
          final previewHeight = (previewWidth * 0.78)
              .clamp(140.0, 360.0)
              .toDouble();
          return SizedBox(
            width: previewWidth,
            height: previewHeight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: isDataImage
                      ? Image.memory(
                          base64Decode(
                            imagePath.substring(imagePath.indexOf(',') + 1),
                          ),
                          width: previewWidth,
                          height: previewHeight,
                          fit: BoxFit.cover,
                        )
                      : Image.network(
                          imagePath,
                          width: previewWidth,
                          height: previewHeight,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              const SizedBox(
                                height: 180,
                                child: Center(
                                  child: Icon(
                                    Icons.broken_image,
                                    color: Colors.white24,
                                    size: 48,
                                  ),
                                ),
                              ),
                        ),
                ),
                // Download button overlay
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: GestureDetector(
                    onTap: () => _downloadImage(context, imagePath),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.65),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.download_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Save',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDocumentAttachment(BuildContext context) {
    final fileName = message.documentName ?? 'nyxra-document.docx';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () => _downloadDocument(context),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppConstants.primaryColor.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppConstants.primaryColor.withOpacity(0.25),
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.description_rounded,
                color: AppConstants.primaryColor,
                size: 32,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fileName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Word document • Tap to download',
                      style: GoogleFonts.inter(
                        color: AppConstants.mutedTextColor,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.download_rounded,
                color: AppConstants.primaryColor,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showImagePreview(BuildContext context, String imagePath) async {
    final isDataImage = imagePath.startsWith('data:image');
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.all(20),
        backgroundColor: Colors.black,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Stack(
          children: [
            SizedBox(
              width: MediaQuery.of(dialogContext).size.width * 0.9,
              height: MediaQuery.of(dialogContext).size.height * 0.86,
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 5,
                child: Center(
                  child: isDataImage
                      ? Image.memory(
                          base64Decode(
                            imagePath.substring(imagePath.indexOf(',') + 1),
                          ),
                          fit: BoxFit.contain,
                        )
                      : Image.network(
                          imagePath,
                          fit: BoxFit.contain,
                          loadingBuilder: (_, child, progress) =>
                              progress == null
                              ? child
                              : const CircularProgressIndicator(
                                  color: AppConstants.primaryColor,
                                ),
                          errorBuilder: (context, error, stackTrace) =>
                              const Icon(
                                Icons.broken_image,
                                color: Colors.white38,
                                size: 64,
                              ),
                        ),
                ),
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: IconButton.filled(
                tooltip: 'Close',
                style: IconButton.styleFrom(backgroundColor: Colors.black54),
                onPressed: () => Navigator.pop(dialogContext),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
            ),
            Positioned(
              right: 12,
              bottom: 12,
              child: FilledButton.icon(
                onPressed: () => _downloadImage(context, imagePath),
                icon: const Icon(Icons.download_rounded),
                label: const Text('Download'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _downloadImage(BuildContext context, String imagePath) async {
    try {
      if (kIsWeb) {
        late Uint8List bytes;
        var mimeType = 'image/png';
        if (imagePath.startsWith('data:image')) {
          final commaIndex = imagePath.indexOf(',');
          mimeType = imagePath.substring(5, imagePath.indexOf(';'));
          bytes = base64Decode(imagePath.substring(commaIndex + 1));
        } else {
          final response = await http.get(Uri.parse(imagePath));
          if (response.statusCode != 200) {
            throw Exception('Image server returned ${response.statusCode}');
          }
          bytes = response.bodyBytes;
          mimeType =
              response.headers['content-type']?.split(';').first ?? mimeType;
        }
        final blob = html.Blob([bytes], mimeType);
        final objectUrl = html.Url.createObjectUrlFromBlob(blob);
        html.AnchorElement(href: objectUrl)
          ..download =
              'nyxra-image-${DateTime.now().millisecondsSinceEpoch}.png'
          ..click();
        Future<void>.delayed(const Duration(seconds: 1), () {
          html.Url.revokeObjectUrl(objectUrl);
        });
      } else {
        late Uint8List bytes;
        var mimeType = 'image/png';
        if (imagePath.startsWith('data:image')) {
          final commaIndex = imagePath.indexOf(',');
          mimeType = imagePath.substring(5, imagePath.indexOf(';'));
          bytes = base64Decode(imagePath.substring(commaIndex + 1));
        } else {
          final response = await http.get(Uri.parse(imagePath));
          if (response.statusCode != 200) {
            throw Exception('Image server returned ${response.statusCode}');
          }
          bytes = response.bodyBytes;
          mimeType =
              response.headers['content-type']?.split(';').first ?? mimeType;
        }
        final extension = mimeType.contains('jpeg')
            ? 'jpg'
            : mimeType.split('/').last;
        if (!context.mounted) return;
        await _shareMobileFile(
          context,
          bytes,
          'nyxra-image-${DateTime.now().millisecondsSinceEpoch}.$extension',
          mimeType,
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _downloadDocument(BuildContext context) async {
    try {
      final data = message.documentBase64;
      if (data == null) return;
      final fileName = message.documentName ?? 'nyxra-document.docx';
      if (kIsWeb) {
        final bytes = base64Decode(data);
        final blob = html.Blob(
          [bytes],
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        );
        final objectUrl = html.Url.createObjectUrlFromBlob(blob);
        html.AnchorElement(href: objectUrl)
          ..download = fileName
          ..click();
        Future<void>.delayed(const Duration(seconds: 1), () {
          html.Url.revokeObjectUrl(objectUrl);
        });
      } else {
        await _shareMobileFile(
          context,
          base64Decode(data),
          fileName,
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not download document: $error')),
        );
      }
    }
  }

  Future<void> _shareMobileFile(
    BuildContext context,
    Uint8List bytes,
    String fileName,
    String mimeType,
  ) async {
    final directory = await getTemporaryDirectory();
    final safeName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '-');
    final file = io.File(
      '${directory.path}${io.Platform.pathSeparator}$safeName',
    );
    await file.writeAsBytes(bytes, flush: true);
    if (!context.mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: mimeType, name: safeName)],
        subject: safeName,
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  Widget _buildActionButton(
    IconData icon,
    VoidCallback onTap, {
    bool isDelete = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Icon(
          icon,
          size: 14,
          color: isDelete
              ? AppConstants.errorColor.withOpacity(0.5)
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
              title: const Text(
                'Copy Message',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                onCopy?.call(message);
              },
            ),
            if (!message.isUser && message.imagePath != null)
              ListTile(
                leading: const Icon(
                  Icons.download_rounded,
                  color: Colors.white,
                ),
                title: const Text(
                  'Save Image',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _downloadImage(context, message.imagePath!);
                },
              ),
            if (!message.isUser && message.documentBase64 != null)
              ListTile(
                leading: const Icon(
                  Icons.file_download_rounded,
                  color: Colors.white,
                ),
                title: const Text(
                  'Download Word Document',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _downloadDocument(context);
                },
              ),
            if (canEdit)
              ListTile(
                leading: const Icon(Icons.edit_rounded, color: Colors.white),
                title: const Text(
                  'Edit Message',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(context);
                  onEdit?.call(message);
                },
              ),
            ListTile(
              leading: const Icon(
                Icons.delete_outline_rounded,
                color: Colors.redAccent,
              ),
              title: const Text(
                'Delete Permanently',
                style: TextStyle(color: Colors.redAccent),
              ),
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

  void _showActionsAtPosition(
    BuildContext context,
    bool canEdit,
    Offset position,
  ) {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        overlay.size.width - position.dx,
        overlay.size.height - position.dy,
      ),
      items: [
        PopupMenuItem(
          child: Row(
            children: [
              const Icon(Icons.copy_rounded, color: Colors.white),
              const SizedBox(width: 12),
              const Text('Copy Message', style: TextStyle(color: Colors.white)),
            ],
          ),
          onTap: () => onCopy?.call(message),
        ),
        if (!message.isUser && message.imagePath != null)
          PopupMenuItem(
            child: Row(
              children: [
                const Icon(Icons.download_rounded, color: Colors.white),
                const SizedBox(width: 12),
                const Text('Save Image', style: TextStyle(color: Colors.white)),
              ],
            ),
            onTap: () => _downloadImage(context, message.imagePath!),
          ),
        if (!message.isUser && message.documentBase64 != null)
          PopupMenuItem(
            onTap: () => _downloadDocument(context),
            child: const Row(
              children: [
                Icon(Icons.file_download_rounded, color: Colors.white),
                SizedBox(width: 12),
                Text(
                  'Download Word Document',
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
        if (canEdit)
          PopupMenuItem(
            child: Row(
              children: [
                const Icon(Icons.edit_rounded, color: Colors.white),
                const SizedBox(width: 12),
                const Text(
                  'Edit Message',
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ),
            onTap: () => onEdit?.call(message),
          ),
        PopupMenuItem(
          child: Row(
            children: [
              const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
              const SizedBox(width: 12),
              const Text('Delete', style: TextStyle(color: Colors.redAccent)),
            ],
          ),
          onTap: () => onDelete?.call(message),
        ),
      ],
      color: AppConstants.surfaceColor,
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
    final code = element.textContent.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => Clipboard.setData(ClipboardData(text: code)),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              decoration: BoxDecoration(
                color: AppConstants.aiMessageColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppConstants.primaryColor.withOpacity(0.3),
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppConstants.primaryColor.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      child: SelectableText(
                        code,
                        style: GoogleFonts.firaCode(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  Builder(
                    builder: (context) => InkWell(
                      onTap: () async {
                        await Clipboard.setData(ClipboardData(text: code));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '✅ Copied: $code',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              backgroundColor: AppConstants.primaryColor,
                              behavior: SnackBarBehavior.floating,
                              width: 200,
                              duration: const Duration(seconds: 1),
                            ),
                          );
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: AppConstants.primaryColor.withOpacity(0.2),
                          borderRadius: const BorderRadius.horizontal(
                            right: Radius.circular(12),
                          ),
                        ),
                        child: const Icon(
                          Icons.copy_all_rounded,
                          size: 18,
                          color: AppConstants.primaryColor,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
