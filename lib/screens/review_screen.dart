import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import '../supabase_client.dart';
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
        const SnackBar(content: Text('Please select a star rating')),
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

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.favorite_rounded, color: Colors.pink, size: 60),
                const SizedBox(height: 16),
                const Text('Thank You!',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text(
                  'Your review has been submitted. It helps other clients find great stylists!',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
            actions: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
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
          SnackBar(content: Text('Error submitting review: $e'), backgroundColor: Colors.red),
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final providerName = _booking?['profiles']?['full_name'] ?? 'your stylist';
    final serviceName = _booking?['services']?['service_name'] ?? 'the service';

    return Scaffold(
      appBar: AppBar(title: const Text('Leave a Review')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Provider info
            CircleAvatar(
              radius: 36,
              backgroundColor: Colors.pink.shade100,
              child: Text(
                providerName.isNotEmpty ? providerName[0].toUpperCase() : '?',
                style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 12),
            Text('How was $providerName?',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(serviceName, style: const TextStyle(color: Colors.grey, fontSize: 14)),

            const SizedBox(height: 28),

            // Star Rating
            const Text('Your Rating',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            const SizedBox(height: 12),
            StarRatingWidget(
              rating: _rating.toDouble(),
              size: 48,
              onRatingChanged: (r) => setState(() => _rating = r),
            ),
            const SizedBox(height: 6),
            Text(
              _rating == 0
                  ? 'Tap to rate'
                  : ['', 'Poor', 'Fair', 'Good', 'Very Good', 'Excellent'][_rating],
              style: TextStyle(
                  color: _rating == 0 ? Colors.grey : Colors.amber.shade700,
                  fontWeight: FontWeight.w600),
            ),

            const SizedBox(height: 28),

            // Comment
            TextField(
              controller: _commentCtrl,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: 'Write a comment (optional)',
                hintText: 'How was the experience? Would you recommend this stylist?',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                alignLabelWithHint: true,
              ),
            ),

            const SizedBox(height: 24),

            // Photo Upload
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Add a Photo (optional)',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            ),
            const SizedBox(height: 8),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Share a photo of your finished hairstyle. It may appear in the stylist\'s gallery.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
            const SizedBox(height: 12),

            if (_imageBytes != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(
                  _imageBytes!,
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _pickImage,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Change Photo'),
              ),
            ] else ...[
              OutlinedButton.icon(
                onPressed: _pickImage,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('Upload Photo'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],

            const SizedBox(height: 32),

            // Submit Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submitReview,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _submitting
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Submit Review',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}