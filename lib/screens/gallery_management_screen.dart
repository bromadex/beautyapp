import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../supabase_client.dart';

class GalleryManagementScreen extends StatefulWidget {
  const GalleryManagementScreen({super.key});
  @override
  State<GalleryManagementScreen> createState() =>
      _GalleryManagementScreenState();
}

class _GalleryManagementScreenState extends State<GalleryManagementScreen> {
  List<Map<String, dynamic>> _images     = [];
  List<Map<String, dynamic>> _categories = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final userId = supabase.auth.currentUser!.id;
    final cats = await supabase
        .from('service_categories').select().order('sort_order');
    final imgs = await supabase
        .from('hairstyle_gallery')
        .select('*, service_categories(name)')
        .eq('provider_id', userId)
        .order('uploaded_at', ascending: false);
    if (mounted) {
      setState(() {
        _categories = List<Map<String, dynamic>>.from(cats);
        _images     = List<Map<String, dynamic>>.from(imgs);
        _loading    = false;
      });
    }
  }

  Future<void> _uploadImage() async {
  final picker = ImagePicker();
  final picked = await picker.pickImage(
      source: ImageSource.gallery, imageQuality: 85);
  if (picked == null) return;
  final bytes = await picked.readAsBytes();

  // Show caption + category dialog
  final result = await _showUploadDialog(bytes);
  if (result == null) return;

  final userId   = supabase.auth.currentUser!.id;
  final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
  final path     = '$userId/$fileName';

  try {
    // Remove fileOptions entirely for web compatibility
    await supabase.storage
        .from('hairstyle-gallery')
        .uploadBinary(path, bytes);

    final publicUrl = supabase.storage
        .from('hairstyle-gallery')
        .getPublicUrl(path);

    await supabase.from('hairstyle_gallery').insert({
      'provider_id': userId,
      'image_url':   publicUrl,
      'caption':     result['caption'],
      'category_id': result['category_id'],
    });

    _load();
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: $e'),
            backgroundColor: Colors.red),
      );
    }
  }
}


  Future<Map<String, dynamic>?> _showUploadDialog(Uint8List preview) async {
  final captionCtrl = TextEditingController();
  String? selectedCat;

  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        title: const Text('Add to Gallery'),
        content: SizedBox(
          width: MediaQuery.of(ctx).size.width - 80,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Preview image
                Container(
                  height: 160,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: Image.memory(
                      preview,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.broken_image, size: 48),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedCat,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    border: OutlineInputBorder(),
                  ),
                  items: _categories.map((c) => DropdownMenuItem(
                    value: c['id'] as String,
                    child: Text('${c['icon'] ?? ''} ${c['name']}'),
                  )).toList(),
                  onChanged: (v) =>
                      setDialogState(() => selectedCat = v),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: captionCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Caption (optional)',
                    hintText: 'e.g. Box braids – medium length',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (selectedCat == null) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Please select a category')),
                );
                return;
              }
              Navigator.pop(ctx, {
                'caption': captionCtrl.text.trim(),
                'category_id': selectedCat,
              });
            },
            child: const Text('Upload'),
          ),
        ],
      ),
    ),
  );
}

  Future<void> _delete(Map<String, dynamic> image) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove Image?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Remove')),
        ],
      ),
    );
    if (confirm != true) return;

    // Extract storage path from public URL
    final url  = image['image_url'] as String;
    final uri  = Uri.parse(url);
    final path = uri.pathSegments
        .skipWhile((s) => s != 'hairstyle-gallery')
        .skip(1)
        .join('/');

    await supabase.storage.from('hairstyle-gallery').remove([path]);
    await supabase.from('hairstyle_gallery').delete().eq('id', image['id']);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hairstyle Gallery')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _uploadImage,
        icon: const Icon(Icons.add_photo_alternate_outlined),
        label: const Text('Add Photo'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _images.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.photo_library_outlined,
                          size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text('No photos yet'),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: _uploadImage,
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                        label: const Text('Add Your First Photo'),
                      ),
                    ],
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 6,
                    mainAxisSpacing: 6,
                  ),
                  itemCount: _images.length,
                  itemBuilder: (_, i) {
                    final img = _images[i];
                    return GestureDetector(
                      onLongPress: () => _delete(img),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              img['image_url'],
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  const Icon(Icons.broken_image),
                            ),
                          ),
                          if (img['caption'] != null &&
                              (img['caption'] as String).isNotEmpty)
                            Positioned(
                              bottom: 0, left: 0, right: 0,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: Colors.black45,
                                  borderRadius: BorderRadius.vertical(
                                      bottom: Radius.circular(8)),
                                ),
                                child: Text(
                                  img['caption'],
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 10),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
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
}