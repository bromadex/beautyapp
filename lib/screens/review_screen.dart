import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import '../supabase_client.dart';
import '../services/notification_service.dart';
import '../theme.dart';
import '../widgets/star_rating_widget.dart';

class ReviewScreen extends StatefulWidget {
  final String bookingId;
  const ReviewScreen({super.key, required this.bookingId});

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  Map<String, dynamic>? _booking;
  bool _loading = true;
  bool _submitting = false;

  int _rating = 0;
  final _commentCtrl = TextEditingController();

  Uint8List? _imageBytes;
  String? _imageFileName;

  @override
  void initState() {
    super.initState();
    _loadBooking();
  }

  Future<void> _loadBooking() async {
    try {
      final booking = await supabase
          .from('bookings')
          .select('*, services(service_name), profiles!bookings_provider_id_fkey(full_name)')
          .eq('id', widget.bookingId)
          .maybeSingle();

      if (booking == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Booking not found')),
          );
          context.go('/home');
        }
        return;
      }

      setState(() {
        _booking = booking;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading booking: $e')),
        );
        context.go('/home');
      }
    }
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result != null && result.files.single.bytes != null) {
      setState(() {
        _imageBytes = result.files.single.bytes;
        _imageFileName = result.files.single.name;
      });
    }
  }

  Future<String?> _uploadPhoto() async {
    if (_imageBytes == null) return null;
    final uid = supabase.auth.currentUser!.id;
    final fileName = '${DateTime.now().millisecondsSinceEpoch}_$_imageFileName';
    final path = '$uid/$fileName';

    await supabase.storage
        .from('after-service-photos')
        .uploadBinary(path, _imageBytes!);

    return supabase.storage.from('after-service-photos').getPublicUrl(path);
  }

  Future<void> _submitReview() async {
    if (_rating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please select a star rating'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    setState(() => _submitting = true);

    try {
      final uid = supabase.auth.currentUser!.id;
      String? imageUrl;

      if (_imageBytes != null) {
        imageUrl = await _uploadPhoto();

        // Add to provider's gallery (pending approval)
        if (imageUrl != null) {
          await supabase.from('hairstyle_gallery').insert({
            'provider_id': _booking!['provider_id'],
            'image_url': imageUrl,
            'caption': 'After service photo by client',
            'is_approved': false,
            'submitted_by_client': true,
          });
        }
      }

      // Insert review
      await supabase.from('reviews').insert({
        'booking_id': widget.bookingId,
        'client_id': uid,
        'provider_id': _booking!['provider_id'],
        'rating': _rating,
        'comment': _commentCtrl.text.trim(),
        'after_service_image_url': imageUrl,
      });

      // Notify provider
      final clientName = (await supabase
              .from('profiles')
              .select('full_name')
              .eq('id', uid)
              .maybeSingle())?['full_name'] ??
          'A client';
      final stars = '${'★' * _rating.round()}';
      NotificationService.send(
        userId: _booking!['provider_id'],
        type: 'review',
        title: 'New ${_rating.toStringAsFixed(0)}-Star Review $stars',
        body: _commentCtrl.text.trim().isNotEmpty
            ? '$clientName: "${_commentCtrl.text.trim()}"'
            : '$clientName left a ${_rating.toStringAsFixed(0)}-star review',
        referenceId: _booking!['provider_id'],
      );

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: AppRadius.xlAll),
            content: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.favorite_rounded, color: Colors.white, size: 36),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    'Thank You!',
                    style: Theme.of(dialogContext).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Your review has been submitted. It helps other clients find great stylists!',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                  ),
                ],
              ),
            ),
            actions: [
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    Navigator.pop(context);
                    context.go('/client/bookings');
                  },
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error submitting review: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
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

    final providerName = _booking?['profiles']?['full_name'] ?? 'your stylist';
    final serviceName = _booking?['services']?['service_name'] ?? 'the service';
    final ratingLabels = ['', 'Poor', 'Fair', 'Good', 'Very Good', 'Excellent'];

    return Scaffold(
      appBar: AppBar(title: const Text('Leave a Review')),
      body: SingleChildScrollView(
        padding: AppSpacing.screenPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Provider info card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.xxl),
              decoration: BoxDecoration(
                color: AppColors.cardLight,
                borderRadius: AppRadius.lgAll,
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        providerName.isNotEmpty ? providerName[0].toUpperCase() : '?',
                        style: const TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'How was $providerName?',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    serviceName,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.xxl),

            // Star Rating section
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.xxl),
              decoration: BoxDecoration(
                color: AppColors.cardLight,
                borderRadius: AppRadius.lgAll,
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                children: [
                  Text(
                    'Your Rating',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  StarRatingWidget(
                    rating: _rating.toDouble(),
                    size: 48,
                    onRatingChanged: (r) => setState(() => _rating = r),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Text(
                      _rating == 0 ? 'Tap to rate' : ratingLabels[_rating],
                      key: ValueKey(_rating),
                      style: TextStyle(
                        color: _rating == 0 ? AppColors.textTertiary : AppColors.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.xxl),

            // Comment field
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Your Comment',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _commentCtrl,
              maxLines: 5,
              decoration: InputDecoration(
                hintText: 'How was the experience? Would you recommend this stylist?',
                alignLabelWithHint: true,
                border: OutlineInputBorder(borderRadius: AppRadius.mdAll),
              ),
            ),

            const SizedBox(height: AppSpacing.xxl),

            // Photo Upload section
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Add a Photo',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Share a photo of your finished hairstyle. It may appear in the stylist\'s gallery.',
                style: TextStyle(fontSize: 13, color: AppColors.textTertiary),
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            if (_imageBytes != null) ...[
              ClipRRect(
                borderRadius: AppRadius.lgAll,
                child: Stack(
                  children: [
                    Image.memory(
                      _imageBytes!,
                      height: 220,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                    Positioned(
                      top: AppSpacing.sm,
                      right: AppSpacing.sm,
                      child: Material(
                        color: Colors.black45,
                        borderRadius: AppRadius.smAll,
                        child: InkWell(
                          borderRadius: AppRadius.smAll,
                          onTap: _pickImage,
                          child: const Padding(
                            padding: EdgeInsets.all(AppSpacing.sm),
                            child: Icon(Icons.refresh_rounded, color: Colors.white, size: 20),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              InkWell(
                onTap: _pickImage,
                borderRadius: AppRadius.lgAll,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxxl),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.04),
                    borderRadius: AppRadius.lgAll,
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.2),
                      style: BorderStyle.solid,
                    ),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.add_photo_alternate_outlined,
                          color: AppColors.primary,
                          size: 24,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        'Tap to upload a photo',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Optional',
                        style: TextStyle(
                          color: AppColors.textTertiary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: AppSpacing.xxxl),

            // Submit Button
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _submitting ? null : _submitReview,
                child: _submitting
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Submit Review'),
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
          ],
        ),
      ),
    );
  }
}
