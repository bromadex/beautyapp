import 'package:flutter/material.dart';

class ChatBubble extends StatelessWidget {
  final String? message;
  final String? imageUrl;
  final bool isMine;
  final String time;
  final bool isRead;

  const ChatBubble({
    super.key,
    this.message,
    this.imageUrl,
    required this.isMine,
    required this.time,
    required this.isRead,
  });

  @override
  Widget build(BuildContext context) {
    final bubbleColor = isMine
        ? Theme.of(context).colorScheme.primary
        : Colors.grey.shade200;
    final textColor = isMine ? Colors.white : Colors.black87;

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
        ),
        child: Column(
          crossAxisAlignment:
              isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              padding: imageUrl != null
                  ? EdgeInsets.zero
                  : const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: imageUrl != null ? Colors.transparent : bubbleColor,
                borderRadius: BorderRadius.only(
                  topLeft:     const Radius.circular(18),
                  topRight:    const Radius.circular(18),
                  bottomLeft:  Radius.circular(isMine ? 18 : 4),
                  bottomRight: Radius.circular(isMine ? 4 : 18),
                ),
              ),
              child: imageUrl != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        imageUrl!,
                        width: 200,
                        fit: BoxFit.cover,
                        loadingBuilder: (_, child, progress) =>
                            progress == null
                                ? child
                                : const SizedBox(
                                    height: 120,
                                    width: 200,
                                    child: Center(
                                        child: CircularProgressIndicator()),
                                  ),
                        errorBuilder: (_, __, ___) => const Icon(
                            Icons.broken_image,
                            size: 48),
                      ),
                    )
                  : Text(message ?? '',
                      style: TextStyle(color: textColor, fontSize: 15)),
            ),
            const SizedBox(height: 3),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(time,
                    style: const TextStyle(
                        fontSize: 10, color: Colors.grey)),
                if (isMine) ...[
                  const SizedBox(width: 4),
                  Icon(
                    isRead ? Icons.done_all : Icons.done,
                    size: 12,
                    color: isRead ? Colors.blue : Colors.grey,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}