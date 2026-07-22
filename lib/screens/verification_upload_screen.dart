import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../supabase_client.dart';
import '../theme.dart';

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

  bool get _bothSelected => _selfieBytes != null && _idBytes != null;

  Future<void> _pick(bool isSelfie) async {
    final XFile? picked =
        await _picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
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
    await supabase.storage.from('verification-docs').uploadBinary(path, bytes);
    return path;
  }

  Future<void> _submit() async {
    if (!_bothSelected) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please provide both photos'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
        ),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final userId = supabase.auth.currentUser!.id;

      await supabase.from('verifications').delete().eq('user_id', userId);

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
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify Identity'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: AppColors.heroGradient,
                    borderRadius: AppRadius.lgAll,
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 52, height: 52,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.shield_rounded, color: Colors.white, size: 26),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Quick & Secure',
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Upload a selfie and your ID to verify your identity. This usually takes under 24 hours.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13, height: 1.4),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Progress indicator
                _ProgressBar(
                  selfieUploaded: _selfieBytes != null,
                  idUploaded: _idBytes != null,
                ),

                const SizedBox(height: 20),

                // Selfie upload card
                _UploadCard(
                  title: 'Selfie Photo',
                  subtitle: 'A clear photo of your face. Good lighting, no sunglasses.',
                  icon: Icons.face_rounded,
                  imageBytes: _selfieBytes,
                  onTap: () => _pick(true),
                  accentColor: AppColors.primary,
                ),

                const SizedBox(height: 14),

                // ID upload card
                _UploadCard(
                  title: 'ID Document',
                  subtitle: 'National ID, Passport, or Driver\'s Licence. All text must be readable.',
                  icon: Icons.badge_rounded,
                  imageBytes: _idBytes,
                  onTap: () => _pick(false),
                  accentColor: AppColors.info,
                ),

                const SizedBox(height: 10),

                // Tips
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.06),
                    borderRadius: AppRadius.mdAll,
                    border: Border.all(color: AppColors.warning.withValues(alpha: 0.15)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.lightbulb_outline_rounded, color: AppColors.warning, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Use good lighting and avoid blurry images. Your ID details must be clearly visible.',
                          style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Submit button
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  child: FilledButton(
                    onPressed: _loading ? null : (_bothSelected ? _submit : null),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey.shade200,
                      disabledForegroundColor: Colors.grey.shade400,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
                      elevation: _bothSelected ? 2 : 0,
                      shadowColor: AppColors.primary.withValues(alpha: 0.3),
                    ),
                    child: _loading
                        ? const SizedBox(
                            height: 20, width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(_bothSelected ? Icons.send_rounded : Icons.photo_camera_rounded, size: 18),
                              const SizedBox(width: 8),
                              Text(
                                _bothSelected ? 'Submit for Review' : 'Upload Both Photos to Continue',
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                  ),
                ),

                if (_bothSelected) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Your data is encrypted and only used for verification purposes.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: AppColors.textTertiary),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final bool selfieUploaded;
  final bool idUploaded;
  const _ProgressBar({required this.selfieUploaded, required this.idUploaded});

  @override
  Widget build(BuildContext context) {
    final progress = (selfieUploaded ? 1 : 0) + (idUploaded ? 1 : 0);

    return Column(
      children: [
        Row(
          children: [
            Text(
              '$progress of 2 photos uploaded',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: progress == 2 ? AppColors.success : AppColors.textSecondary,
              ),
            ),
            const Spacer(),
            if (progress == 2)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_rounded, size: 14, color: AppColors.success),
                    const SizedBox(width: 4),
                    Text('Ready', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.success)),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress / 2,
            minHeight: 6,
            backgroundColor: Colors.grey.shade100,
            valueColor: AlwaysStoppedAnimation(
              progress == 2 ? AppColors.success : AppColors.primary,
            ),
          ),
        ),
      ],
    );
  }
}

class _UploadCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Uint8List? imageBytes;
  final VoidCallback onTap;
  final Color accentColor;

  const _UploadCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.imageBytes,
    required this.onTap,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = imageBytes != null;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: AppRadius.lgAll,
          border: Border.all(
            color: hasImage ? AppColors.success : Colors.grey.shade200,
            width: hasImage ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: hasImage
                  ? AppColors.success.withValues(alpha: 0.1)
                  : Colors.black.withValues(alpha: 0.03),
              blurRadius: hasImage ? 12 : 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: hasImage ? _buildWithImage() : _buildEmpty(),
      ),
    );
  }

  Widget _buildWithImage() {
    return Column(
      children: [
        ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
          child: SizedBox(
            height: 160,
            width: double.infinity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.memory(imageBytes!, fit: BoxFit.cover),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Colors.black.withValues(alpha: 0.4), Colors.transparent],
                    ),
                  ),
                ),
                Positioned(
                  top: 10, right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.success,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_rounded, color: Colors.white, size: 14),
                        SizedBox(width: 4),
                        Text('Uploaded', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.check_circle_rounded, color: AppColors.success, size: 18),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('Change', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmpty() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: accentColor, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                const SizedBox(height: 3),
                Text(subtitle, style: TextStyle(fontSize: 12, color: AppColors.textTertiary, height: 1.3)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.add_a_photo_rounded, color: accentColor, size: 20),
          ),
        ],
      ),
    );
  }
}
