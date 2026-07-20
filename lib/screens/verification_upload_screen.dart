import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../supabase_client.dart';

class VerificationUploadScreen extends StatefulWidget {
  const VerificationUploadScreen({super.key});

  @override
  State<VerificationUploadScreen> createState() =>
      _VerificationUploadScreenState();
}

class _VerificationUploadScreenState extends State<VerificationUploadScreen> {
  Uint8List? _selfieBytes;
  Uint8List? _idBytes;
  bool _loading = false;
  final _picker = ImagePicker();

  Future<void> _pick(bool isSelfie) async {
    final source = isSelfie ? ImageSource.camera : ImageSource.gallery;
    final XFile? picked = await _picker.pickImage(source: source, imageQuality: 80);
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    setState(() {
      if (isSelfie) {
        _selfieBytes = bytes;
      } else {
        _idBytes = bytes;
      }
    });
  }

  Future<String> _uploadFile(Uint8List bytes, String fileName) async {
    final userId = supabase.auth.currentUser!.id;
    final path = '$userId/$fileName';
    // Use uploadBinary for web compatibility
    await supabase.storage
        .from('verification-docs')
        .uploadBinary(path, bytes);
    return path;
  }

  Future<void> _submit() async {
    if (_selfieBytes == null || _idBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please provide both photos')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final userId = supabase.auth.currentUser!.id;

      // Delete any previous submission
      await supabase
          .from('verifications')
          .delete()
          .eq('user_id', userId);

      final selfiePath = await _uploadFile(_selfieBytes!, 'selfie.jpg');
      final idPath = await _uploadFile(_idBytes!, 'id_document.jpg');

      await supabase.from('verifications').insert({
        'user_id': userId,
        'selfie_url': selfiePath,
        'id_document_url': idPath,
        'status': 'pending',
      });

      if (mounted) context.go('/verify/pending');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Identity Verification')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'We need to verify your identity before you can use the platform.',
              style: TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 8),
            const Text(
              'Please provide:\n  1. A selfie (taken now with your camera)\n  2. A photo of your National ID or Passport',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 32),

            // Selfie
            _PhotoCard(
              title: '1. Take a Selfie',
              subtitle: 'Use your front camera. Make sure your face is clearly visible.',
              icon: Icons.camera_front_rounded,
              imageBytes: _selfieBytes,
              onTap: () => _pick(true),
            ),
            const SizedBox(height: 16),

            // ID Document
            _PhotoCard(
              title: '2. Upload ID / Passport',
              subtitle: 'National ID, Passport or Driver\'s Licence. All text must be readable.',
              icon: Icons.credit_card_rounded,
              imageBytes: _idBytes,
              onTap: () => _pick(false),
            ),
            const SizedBox(height: 32),

            FilledButton.icon(
              onPressed: _loading ? null : _submit,
              icon: _loading
                  ? const SizedBox(
                      height: 18, width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_rounded),
              label: Text(_loading ? 'Submitting...' : 'Submit for Review'),
              style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16)),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Uint8List? imageBytes;
  final VoidCallback onTap;

  const _PhotoCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.imageBytes,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = imageBytes != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: hasImage ? Colors.green : Theme.of(context).colorScheme.outline,
            width: hasImage ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: hasImage
            ? ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: Stack(
                  children: [
                    SizedBox(
                      height: 180,
                      width: double.infinity,
                      child: Image.memory(imageBytes!, fit: BoxFit.cover),
                    ),
                    Positioned(
                      top: 8, right: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.green, shape: BoxShape.circle),
                        child: const Icon(Icons.check,
                            color: Colors.white, size: 16),
                      ),
                    ),
                    Positioned(
                      bottom: 8, right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text('Tap to change',
                            style: TextStyle(
                                color: Colors.white, fontSize: 11)),
                      ),
                    ),
                  ],
                ),
              )
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(icon, size: 48,
                        color: Theme.of(context).colorScheme.primary),
                    const SizedBox(height: 12),
                    Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: onTap,
                      child: const Text('Choose Photo'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}