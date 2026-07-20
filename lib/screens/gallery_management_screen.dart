import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../supabase_client.dart';
import '../theme.dart';

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
  bool _uploading = false;

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

    final result = await _showUploadDialog(bytes);
    if (result == null) return;

    setState(() => _uploading = true);

    final userId   = supabase.auth.currentUser!.id;
    final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
    final path     = '$userId/$fileName';

    try {
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
          SnackBar(
            content: Text('Upload failed: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<Map<String, dynamic>?> _showUploadDialog(Uint8List preview) async {
    final captionCtrl = TextEditingController();
    String? selectedCat;

    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: AppRadius.xlAll),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: AppRadius.smAll,
                ),
                child: const Icon(Icons.add_photo_alternate_outlined,
                    color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: AppSpacing.md),
              const Text('Add to Gallery'),
            ],
          ),
          content: SizedBox(
            width: MediaQuery.of(ctx).size.width - 80,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Preview image
                  Container(
                    height: 180,
                    decoration: BoxDecoration(
                      borderRadius: AppRadius.mdAll,
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: ClipRRect(
                      borderRadius: AppRadius.mdAll,
                      child: Image.memory(
                        preview,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        errorBuilder: (_, __, ___) => Container(
                          color: Colors.grey.shade100,
                          child: const Icon(Icons.broken_image_outlined,
                              size: 48, color: AppColors.textTertiary),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  DropdownButtonFormField<String>(
                    value: selectedCat,
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      prefixIcon: Icon(Icons.category_outlined),
                    ),
                    borderRadius: AppRadius.mdAll,
                    items: _categories.map((c) => DropdownMenuItem(
                      value: c['id'] as String,
                      child: Text('${c['icon'] ?? ''} ${c['name']}'),
                    )).toList(),
                    onChanged: (v) =>
                        setDialogState(() => selectedCat = v),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: captionCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Caption (optional)',
                      hintText: 'e.g. Box braids -- medium length',
                      prefixIcon: Icon(Icons.short_text_rounded),
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
            FilledButton.icon(
              onPressed: () {
                if (selectedCat == null) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                      content: const Text('Please select a category'),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: AppRadius.mdAll),
                    ),
                  );
                  return;
                }
                Navigator.pop(ctx, {
                  'caption': captionCtrl.text.trim(),
                  'category_id': selectedCat,
                });
              },
              icon: const Icon(Icons.cloud_upload_outlined),
              label: const Text('Upload'),
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
        shape: RoundedRectangleBorder(borderRadius: AppRadius.xlAll),
        title: const Text('Remove Image?'),
        content: const Text('This photo will be permanently removed from your gallery.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              child: const Text('Remove')),
        ],
      ),
    );
    if (confirm != true) return;

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
      appBar: AppBar(
        title: const Text('Gallery'),
        actions: [
          if (_images.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.md),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: AppRadius.smAll,
                  ),
                  child: Text(
                    '${_images.length} photos',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _uploading ? null : _uploadImage,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_photo_alternate_outlined),
        label: const Text('Add Photo'),
      ),
      body: Stack(
        children: [
          _loading
              ? Center(
                  child: CircularProgressIndicator(color: AppColors.primary))
              : _images.isEmpty
                  ? _buildEmptyState()
                  : _buildGalleryGrid(),

          // Upload progress overlay
          if (_uploading)
            Container(
              color: Colors.black38,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.xxxl),
                  decoration: BoxDecoration(
                    color: AppColors.cardLight,
                    borderRadius: AppRadius.xlAll,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 24,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: AppColors.primary),
                      const SizedBox(height: AppSpacing.xl),
                      const Text(
                        'Uploading photo...',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
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
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: AppSpacing.screenPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.camera_alt_outlined,
                size: 48,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            const Text(
              'Your gallery is empty',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Showcase your best work to attract\nmore clients to your services.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            FilledButton.icon(
              onPressed: _uploadImage,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('Add Your First Photo'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xxl,
                  vertical: AppSpacing.lg,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGalleryGrid() {
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 80,
      ),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: AppSpacing.sm,
        mainAxisSpacing: AppSpacing.sm,
      ),
      itemCount: _images.length,
      itemBuilder: (_, i) {
        final img = _images[i];
        return _GalleryImageCard(
          imageUrl: img['image_url'] as String,
          caption: img['caption'] as String?,
          onDelete: () => _delete(img),
        );
      },
    );
  }
}

class _GalleryImageCard extends StatefulWidget {
  final String imageUrl;
  final String? caption;
  final VoidCallback onDelete;

  const _GalleryImageCard({
    required this.imageUrl,
    this.caption,
    required this.onDelete,
  });

  @override
  State<_GalleryImageCard> createState() => _GalleryImageCardState();
}

class _GalleryImageCardState extends State<_GalleryImageCard> {
  bool _showOverlay = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _showOverlay = !_showOverlay),
      onLongPress: widget.onDelete,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          borderRadius: AppRadius.mdAll,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: AppRadius.mdAll,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                widget.imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: Colors.grey.shade100,
                  child: const Icon(Icons.broken_image_outlined,
                      color: AppColors.textTertiary),
                ),
              ),

              // Tap overlay with delete button
              if (_showOverlay)
                Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                  ),
                  child: Center(
                    child: IconButton(
                      onPressed: widget.onDelete,
                      icon: const Icon(Icons.delete_outline_rounded),
                      color: Colors.white,
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.error.withValues(alpha: 0.8),
                        padding: const EdgeInsets.all(AppSpacing.sm),
                      ),
                    ),
                  ),
                ),

              // Caption bar
              if (widget.caption != null &&
                  widget.caption!.isNotEmpty &&
                  !_showOverlay)
                Positioned(
                  bottom: 0, left: 0, right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.7),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: Text(
                      widget.caption!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
