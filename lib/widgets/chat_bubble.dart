import 'package:flutter/material.dart';
import '../theme.dart';

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
    final textColor =
        isMine ? Colors.white : AppColors.textPrimary;

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(
            vertical: AppSpacing.xs, horizontal: AppSpacing.md),
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
                      horizontal: AppSpacing.lg, vertical: AppSpacing.md),
              decoration: BoxDecoration(
                gradient: isMine && imageUrl == null
                    ? const LinearGradient(
                        colors: [AppColors.primary, Color(0xFFFF6BAE)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: imageUrl != null
                    ? Colors.transparent
                    : (isMine ? null : Colors.grey.shade100),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(AppRadius.xl),
                  topRight: Radius.circular(AppRadius.xl),
                  bottomLeft:
                      Radius.circular(isMine ? AppRadius.xl : AppSpacing.xs),
                  bottomRight:
                      Radius.circular(isMine ? AppSpacing.xs : AppRadius.xl),
                ),
              ),
              child: imageUrl != null
                  ? ClipRRect(
                      borderRadius: AppRadius.mdAll,
                      child: Image.network(
                        imageUrl!,
                        width: 200,
                        fit: BoxFit.cover,
                        loadingBuilder: (_, child, progress) =>
                            progress == null
                                ? child
                                : Container(
                                    height: 120,
                                    width: 200,
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      borderRadius: AppRadius.mdAll,
                                    ),
                                    child: Center(
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ),
                        errorBuilder: (_, __, ___) => Container(
                          height: 120,
                          width: 200,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: AppRadius.mdAll,
                          ),
                          child: const Icon(Icons.broken_image_rounded,
                              size: 40, color: AppColors.textTertiary),
                        ),
                      ),
                    )
                  : Text(message ?? '',
                      style: TextStyle(
                        color: textColor,
                        fontSize: 15,
                        height: 1.35,
                      )),
            ),
            const SizedBox(height: 3),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(time,
                    style: const TextStyle(
                        fontSize: 10, color: AppColors.textTertiary)),
                if (isMine) ...[
                  const SizedBox(width: AppSpacing.xs),
                  Icon(
                    isRead ? Icons.done_all : Icons.done,
                    size: 12,
                    color: isRead ? AppColors.info : AppColors.textTertiary,
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
