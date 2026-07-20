import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../supabase_client.dart';
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
      // Immediately fetch messages to show the sent message
      await _fetchMessages();
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Send failed: $e'), backgroundColor: Colors.red),
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

      // Get signed URL (valid 1 year — long enough for chat history)
      final signedUrl = await supabase.storage
          .from('chat-images')
          .createSignedUrl(path, 60 * 60 * 24 * 365);

      await _sendMessage(imageUrl: signedUrl);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Image upload failed: $e'), backgroundColor: Colors.red),
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Chat')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(_error!),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final bookingStatus = _booking?['status'] as String? ?? '';
    final canChat = bookingStatus == 'confirmed' || bookingStatus == 'completed';

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_chatTitle(),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            Text(
              'Booking ${bookingStatus[0].toUpperCase()}${bookingStatus.substring(1)}',
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Messages list - reversed order so newest at bottom
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.chat_bubble_outline,
                            size: 56, color: Colors.grey),
                        const SizedBox(height: 12),
                        const Text('No messages yet',
                            style: TextStyle(color: Colors.grey)),
                        const SizedBox(height: 4),
                        Text(
                          canChat
                              ? 'Send a message to get started'
                              : 'Chat available for confirmed bookings',
                          style: const TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) {
                      final msg = _messages[i];
                      final isMine = msg['sender_id'] == _myId;

                      // Show date separator when day changes
                      final showDate = i == 0 ||
                          _isDifferentDay(
                              _messages[i - 1]['sent_at'],
                              msg['sent_at']);

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
                color: Theme.of(context).scaffoldBackgroundColor,
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: SafeArea(
                child: Row(children: [
                  // Image picker button
                  IconButton(
                    icon: const Icon(Icons.image_outlined),
                    color: Theme.of(context).colorScheme.primary,
                    onPressed: _sending ? null : _pickAndSendImage,
                    tooltip: 'Send image',
                  ),

                  // Text field
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: TextField(
                        controller: _messageCtrl,
                        decoration: const InputDecoration(
                          hintText: 'Type a message...',
                          border: InputBorder.none,
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        ),
                        maxLines: 4,
                        minLines: 1,
                        textCapitalization: TextCapitalization.sentences,
                        onSubmitted: (_) => _sendMessage(text: _messageCtrl.text),
                      ),
                    ),
                  ),

                  const SizedBox(width: 8),

                  // Send button
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: _sending
                        ? const SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : IconButton(
                            key: const ValueKey('send'),
                            icon: const Icon(Icons.send_rounded),
                            color: Theme.of(context).colorScheme.primary,
                            onPressed: () => _sendMessage(text: _messageCtrl.text),
                          ),
                  ),
                ]),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(12),
              color: Colors.grey.shade100,
              child: const Text(
                'Chat is only available for confirmed bookings',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 13),
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

// ── Date separator ───────────────────────────────────────────

class _DateSeparator extends StatelessWidget {
  final String? iso;
  const _DateSeparator({this.iso});

  @override
  Widget build(BuildContext context) {
    final dt = iso != null ? DateTime.tryParse(iso!)?.toLocal() : null;
    final label = dt != null ? '${dt.day}/${dt.month}/${dt.year}' : '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(children: [
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ),
        const Expanded(child: Divider()),
      ]),
    );
  }
}