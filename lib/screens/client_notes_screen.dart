import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import '../supabase_client.dart';
import '../theme.dart';

class ClientNotesScreen extends StatefulWidget {
  final String clientId;
  final String? bookingId;
  const ClientNotesScreen({
    super.key,
    required this.clientId,
    this.bookingId,
  });

  @override
  State<ClientNotesScreen> createState() => _ClientNotesScreenState();
}

class _ClientNotesScreenState extends State<ClientNotesScreen> {
  List<Map<String, dynamic>> _notes = [];
  Map<String, dynamic>? _client;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;

    try {
      final results = await Future.wait([
        supabase
            .from('client_notes')
            .select()
            .eq('provider_id', uid)
            .eq('client_id', widget.clientId)
            .order('created_at', ascending: false),
        supabase
            .from('profiles')
            .select('full_name')
            .eq('id', widget.clientId)
            .maybeSingle(),
      ]);

      if (mounted) {
        setState(() {
          _notes = List<Map<String, dynamic>>.from(results[0] as List);
          _client = results[1] as Map<String, dynamic>?;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addNote() async {
    final ctrl = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Note'),
        content: TextField(
          controller: ctrl,
          maxLines: 5,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Private note about this client...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    ctrl.dispose();

    if (note == null || note.isEmpty) return;

    try {
      final uid = supabase.auth.currentUser!.id;
      await supabase.from('client_notes').insert({
        'provider_id': uid,
        'client_id': widget.clientId,
        'booking_id': widget.bookingId,
        'note': note,
      });
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _deleteNote(String noteId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Note?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await supabase.from('client_notes').delete().eq('id', noteId);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final clientName = _client?['full_name'] ?? 'Client';

    return Scaffold(
      appBar: AppBar(title: Text('Notes - $clientName')),
      floatingActionButton: FloatingActionButton(
        onPressed: _addNote,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        child: const Icon(TablerIcons.plus),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _notes.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(TablerIcons.notes,
                          size: 56, color: AppColors.textTertiary),
                      const SizedBox(height: AppSpacing.lg),
                      Text('No notes yet',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: AppSpacing.sm),
                      Text('Add private notes about this client',
                          style:
                              TextStyle(color: AppColors.textTertiary)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: AppSpacing.screenPadding,
                  itemCount: _notes.length,
                  itemBuilder: (_, i) {
                    final note = _notes[i];
                    final createdAt =
                        DateTime.tryParse(note['created_at'] ?? '')?.toLocal();
                    final dateStr = createdAt != null
                        ? '${createdAt.day}/${createdAt.month}/${createdAt.year}'
                        : '';

                    return Card(
                      margin:
                          const EdgeInsets.only(bottom: AppSpacing.md),
                      child: Padding(
                        padding: AppSpacing.cardPadding,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(TablerIcons.note,
                                    size: 16,
                                    color: AppColors.textTertiary),
                                const SizedBox(width: AppSpacing.xs),
                                Text(dateStr,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall),
                                const Spacer(),
                                IconButton(
                                  onPressed: () =>
                                      _deleteNote(note['id']),
                                  icon: const Icon(
                                      TablerIcons.trash,
                                      size: 18),
                                  color: AppColors.error,
                                  visualDensity:
                                      VisualDensity.compact,
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              note['note'] ?? '',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
