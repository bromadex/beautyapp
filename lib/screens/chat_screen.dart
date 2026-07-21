import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../supabase_client.dart';
import '../services/notification_service.dart';
import '../theme.dart';
import '../widgets/chat_bubble.dart';

class ChatScreen extends StatefulWidget {
  final String bookingId;
  const ChatScreen({super.key, required this.bookingId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _picker = ImagePicker();

  List<Map<String, dynamic>> _messages = [];
  Map<String, dynamic>? _booking;
  bool _loading = true;
  bool _sending = false;
  String? _error;
  String? _myId;
  String? _otherId;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _myId = supabase.auth.currentUser!.id;
    _load();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _messageCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Load booking to get participant IDs
      final booking = await supabase
          .from('bookings')
          .select(
              'client_id, provider_id, status, client:profiles!bookings_client_id_fkey(full_name), provider:profiles!bookings_provider_id_fkey(full_name), services(service_name)')
          .eq('id', widget.bookingId)
          .maybeSingle();

      if (booking == null) {
        if (mounted) {
          setState(() {
            _error = 'Booking not found';
            _loading = false;
          });
        }
        return;
      }

      _otherId = booking['client_id'] == _myId
          ? booking['provider_id'] as String
          : booking['client_id'] as String;

      // Load messages
      await _fetchMessages();

      // Mark received messages as read
      await supabase
          .from('messages')
          .update({'is_read': true})
          .eq('booking_id', widget.bookingId)
          .eq('receiver_id', _myId!);

      if (mounted) {
        setState(() {
          _booking = booking;
          _loading = false;
        });
        _subscribeRealtime();
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _fetchMessages() async {
    final data = await supabase
        .from('messages')
        .select()
        .eq('booking_id', widget.bookingId)
        .order('sent_at', ascending: true); // Oldest first (bottom = newest)
    if (mounted) {
      setState(() {
        _messages = List<Map<String, dynamic>>.from(data);
      });
    }
  }

  void _subscribeRealtime() {
    _channel = supabase
        .channel('chat_${widget.bookingId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'booking_id',
            value: widget.bookingId,
          ),
          callback: (_) async {
            await _fetchMessages();
            // Mark new incoming messages as read immediately
            await supabase
                .from('messages')
                .update({'is_read': true})
                .eq('booking_id', widget.bookingId)
                .eq('receiver_id', _myId!);
            _scrollToBottom();
          },
        )
        .subscribe();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage({String? text, String? imageUrl}) async {
    if ((text == null || text.trim().isEmpty) && imageUrl == null) return;
    if (_otherId == null) return;

    setState(() => _sending = true);
    try {
      await supabase.from('messages').insert({
        'booking_id': widget.bookingId,
        'sender_id': _myId,
        'receiver_id': _otherId,
        'message': text?.trim(),
        'image_url': imageUrl,
        'is_read': false,
      });
      _messageCtrl.clear();

      // Notify receiver
      final senderName = (await supabase
              .from('profiles')
              .select('full_name')
              .eq('id', _myId!)
              .maybeSingle())?['full_name'] ??
          'Someone';
      NotificationService.send(
        userId: _otherId!,
        type: 'message',
        title: 'New Message from $senderName',
        body: imageUrl != null
            ? '$senderName sent a photo'
            : text?.trim() ?? 'New message',
        referenceId: widget.bookingId,
      );
      // Immediately fetch messages to show the sent message
      await _fetchMessages();
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Send failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickAndSendImage() async {
    final picked = await _picker.pickImage(
        source: ImageSource.gallery, imageQuality: 80);
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    final fileName = '${_myId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final path = '$_myId/$fileName';

    try {
      await supabase.storage.from('chat-images').uploadBinary(path, bytes);

      // Get signed URL (valid 1 year -- long enough for chat history)
      final signedUrl = await supabase.storage
          .from('chat-images')
          .createSignedUrl(path, 60 * 60 * 24 * 365);

      await _sendMessage(imageUrl: signedUrl);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Image upload failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  String _formatTime(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '';
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _chatTitle() {
    if (_booking == null) return 'Chat';
    final isClient = _booking!['client_id'] == _myId;
    String otherName;
    String serviceName;

    if (isClient) {
      final provider = _booking!['provider'] as Map?;
      otherName = provider?['full_name'] ?? 'Provider';
    } else {
      final client = _booking!['client'] as Map?;
      otherName = client?['full_name'] ?? 'Client';
    }

    final services = _booking!['services'] as Map?;
    serviceName = services?['service_name'] ?? 'Booking';

    return '$otherName · $serviceName';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Chat')),
        body: Center(
          child: Padding(
            padding: AppSpacing.screenPadding,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.chat_bubble_outline,
                      size: 48, color: AppColors.error),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Could not load chat',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _error!,
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.xxl),
                FilledButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final bookingStatus = _booking?['status'] as String? ?? '';
    final canChat = bookingStatus == 'confirmed' || bookingStatus == 'completed';
    final statusColor = StatusColors.foreground(bookingStatus);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _chatTitle(),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  StatusColors.label(bookingStatus),
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textTertiary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Messages list
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(AppSpacing.xl),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.08),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.chat_bubble_outline_rounded,
                              size: 40, color: AppColors.primary),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Text(
                          'No messages yet',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          canChat
                              ? 'Send a message to get started'
                              : 'Chat available for confirmed bookings',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.md,
                      horizontal: AppSpacing.xs,
                    ),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) {
                      final msg = _messages[i];
                      final isMine = msg['sender_id'] == _myId;

                      // Show date separator when day changes
                      final showDate = i == 0 ||
                          _isDifferentDay(
                              _messages[i - 1]['sent_at'], msg['sent_at']);

                      return Column(
                        children: [
                          if (showDate) _DateSeparator(iso: msg['sent_at']),
                          ChatBubble(
                            message: msg['message'],
                            imageUrl: msg['image_url'],
                            isMine: isMine,
                            time: _formatTime(msg['sent_at']),
                            isRead: msg['is_read'] as bool,
                          ),
                        ],
                      );
                    },
                  ),
          ),

          // Input bar
          if (canChat)
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.sm,
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    // Image picker button
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.image_outlined, size: 22),
                        color: AppColors.primary,
                        onPressed: _sending ? null : _pickAndSendImage,
                        tooltip: 'Send image',
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),

                    // Text field
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.surfaceLight,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: Colors.grey.shade200,
                          ),
                        ),
                        child: TextField(
                          controller: _messageCtrl,
                          decoration: InputDecoration(
                            hintText: 'Type a message...',
                            hintStyle: TextStyle(
                              color: AppColors.textTertiary,
                              fontSize: 14,
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.lg,
                              vertical: AppSpacing.md,
                            ),
                          ),
                          maxLines: 4,
                          minLines: 1,
                          textCapitalization: TextCapitalization.sentences,
                          onSubmitted: (_) =>
                              _sendMessage(text: _messageCtrl.text),
                        ),
                      ),
                    ),

                    const SizedBox(width: AppSpacing.sm),

                    // Send button
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: _sending
                          ? Container(
                              width: 44,
                              height: 44,
                              padding: const EdgeInsets.all(10),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.primary,
                              ),
                            )
                          : Container(
                              key: const ValueKey('send'),
                              decoration: const BoxDecoration(
                                gradient: AppColors.primaryGradient,
                                shape: BoxShape.circle,
                              ),
                              child: IconButton(
                                icon: const Icon(Icons.send_rounded, size: 20),
                                color: Colors.white,
                                onPressed: () =>
                                    _sendMessage(text: _messageCtrl.text),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              margin: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.08),
                borderRadius: AppRadius.mdAll,
                border: Border.all(
                  color: AppColors.warning.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 16, color: AppColors.warning),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    'Chat is only available for confirmed bookings',
                    style: TextStyle(
                      color: AppColors.warning,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  bool _isDifferentDay(String? a, String? b) {
    if (a == null || b == null) return false;
    final da = DateTime.tryParse(a)?.toLocal();
    final db = DateTime.tryParse(b)?.toLocal();
    if (da == null || db == null) return false;
    return da.day != db.day || da.month != db.month || da.year != db.year;
  }
}

// -- Date separator ----------------------------------------------------------

class _DateSeparator extends StatelessWidget {
  final String? iso;
  const _DateSeparator({this.iso});

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(date).inDays;

    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';

    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final dt = iso != null ? DateTime.tryParse(iso!)?.toLocal() : null;
    final label = dt != null ? _formatDate(dt) : '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs + 2,
          ),
          decoration: BoxDecoration(
            color: Colors.grey.shade200.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textTertiary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
