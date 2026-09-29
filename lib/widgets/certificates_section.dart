import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions, PostgrestException;
import '../supabase_client.dart';
import '../theme.dart';
import '../widgets/ui.dart';

/// A pro's qualifications. Clients see them on the profile; massage and
/// microblading need at least one.
class CertificatesSection extends StatefulWidget {
  const CertificatesSection({super.key});
  @override
  State<CertificatesSection> createState() => _CertificatesSectionState();
}

class _CertificatesSectionState extends State<CertificatesSection> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await supabase
          .from('provider_certificates')
          .select()
          .eq('provider_id', supabase.auth.currentUser!.id)
          .order('created_at', ascending: false);
      _items = List<Map<String, dynamic>>.from(rows);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _add() async {
    final titleCtrl = TextEditingController();
    final issuerCtrl = TextEditingController();
    final yearCtrl = TextEditingController();
    Uint8List? photo;
    bool saving = false;
    await showModalBottomSheet(
      useRootNavigator: true,
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SheetScroll(child: StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Add a certificate', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            TextField(
              controller: titleCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Qualification', hintText: 'e.g. Diploma in Massage Therapy'),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: issuerCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Issued by (optional)'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: yearCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Year'),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 75, maxWidth: 1600);
                if (picked == null) return;
                final bytes = await picked.readAsBytes();
                setSheet(() => photo = bytes);
              },
              icon: Icon(photo == null ? TablerIcons.photo_plus : TablerIcons.check, size: 18),
              label: Text(photo == null ? 'Add a photo of it (optional)' : 'Photo added'),
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (titleCtrl.text.trim().length < 2) return;
                      setSheet(() => saving = true);
                      try {
                        final uid = supabase.auth.currentUser!.id;
                        String? url;
                        if (photo != null) {
                          final path = '$uid/${DateTime.now().millisecondsSinceEpoch}.jpg';
                          await supabase.storage.from('certificates').uploadBinary(path, photo!,
                              fileOptions: const FileOptions(contentType: 'image/jpeg'));
                          url = supabase.storage.from('certificates').getPublicUrl(path);
                        }
                        await supabase.from('provider_certificates').insert({
                          'provider_id': uid,
                          'title': titleCtrl.text.trim(),
                          'issuer': issuerCtrl.text.trim().isEmpty ? null : issuerCtrl.text.trim(),
                          'year': int.tryParse(yearCtrl.text.trim()),
                          'image_url': url,
                        });
                        if (ctx.mounted) Navigator.pop(ctx);
                      } on PostgrestException catch (e) {
                        setSheet(() => saving = false);
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(e.message)));
                        }
                      } catch (e) {
                        setSheet(() => saving = false);
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Could not save: $e')));
                        }
                      }
                    },
              child: Text(saving ? 'Saving…' : 'Save certificate'),
            ),
          ]),
        ),
      )),
    );
    titleCtrl.dispose();
    issuerCtrl.dispose();
    yearCtrl.dispose();
    _load();
  }

  Future<void> _delete(Map<String, dynamic> c) async {
    await supabase.from('provider_certificates').delete().eq('id', c['id']);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox(height: 48, child: Center(child: CircularProgressIndicator()));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Clients see these on your profile. Massage and microblading need at least one.',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
      const SizedBox(height: 10),
      for (final c in _items)
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: AppRadius.mdAll,
            border: Border.all(color: AppColors.border),
          ),
          child: Row(children: [
            Icon(TablerIcons.certificate, color: AppColors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                if (c['issuer'] != null || c['year'] != null)
                  Text([c['issuer'], c['year']].where((x) => x != null).join(' · '),
                      style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
              ]),
            ),
            IconButton(
              tooltip: 'Remove',
              icon: Icon(TablerIcons.trash, size: 20, color: AppColors.textSecondary),
              onPressed: () => _delete(c),
            ),
          ]),
        ),
      OutlinedButton.icon(
        onPressed: _add,
        icon: const Icon(TablerIcons.plus, size: 18),
        label: const Text('Add a certificate'),
      ),
    ]);
  }
}
