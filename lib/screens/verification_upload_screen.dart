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

  int get _currentStep {
    if (_selfieBytes == null) return 0;
    if (_idBytes == null) return 1;
    return 2;
  }

  Future<void> _pick(bool isSelfie) async {
    final source = isSelfie ? ImageSource.camera : ImageSource.gallery;
    final XFile? picked =
        await _picker.pickImage(source: source, imageQuality: 80);
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
    if (_selfieBytes == null || _idBytes == null) {
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
      appBar: AppBar(title: const Text('Identity Verification')),
      body: SingleChildScrollView(
        padding: AppSpacing.screenPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header card
            Container(
              padding: AppSpacing.cardPadding,
              decoration: BoxDecoration(
                gradient: AppColors.heroGradient,
                borderRadius: AppRadius.lgAll,
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: AppRadius.mdAll,
                    ),
                    child: const Icon(
                      Icons.verified_user_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Verify Your Identity',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: AppSpacing.xs),
                        Text(
                          'Complete 2 simple steps to get verified and start using the platform.',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),

            // Progress stepper
            _ProgressStepper(currentStep: _currentStep),
            const SizedBox(height: AppSpacing.xxl),

            // Step 1: Selfie
            _PhotoCard(
              stepNumber: 1,
              title: 'Take a Selfie',
              subtitle:
                  'Use your front camera. Make sure your face is clearly visible.',
              icon: Icons.camera_front_rounded,
              imageBytes: _selfieBytes,
              onTap: () => _pick(true),
              isActive: _currentStep == 0,
            ),
            const SizedBox(height: AppSpacing.lg),

            // Step 2: ID Document
            _PhotoCard(
              stepNumber: 2,
              title: 'Upload ID / Passport',
              subtitle:
                  'National ID, Passport or Driver\'s Licence. All text must be readable.',
              icon: Icons.credit_card_rounded,
              imageBytes: _idBytes,
              onTap: () => _pick(false),
              isActive: _currentStep == 1,
            ),
            const SizedBox(height: AppSpacing.xxxl),

            // Submit button
            FilledButton.icon(
              onPressed: _loading ? null : _submit,
              icon: _loading
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send_rounded),
              label: Text(_loading ? 'Submitting...' : 'Submit for Review'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                shape: RoundedRectangleBorder(
                  borderRadius: AppRadius.mdAll,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Progress Stepper
// ---------------------------------------------------------------------------
class _ProgressStepper extends StatelessWidget {
  final int currentStep;

  const _ProgressStepper({required this.currentStep});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _StepDot(
          label: 'Selfie',
          stepIndex: 0,
          currentStep: currentStep,
        ),
        Expanded(
          child: Container(
            height: 2,
            color: currentStep > 0
                ? AppColors.success
                : Colors.grey.shade300,
          ),
        ),
        _StepDot(
          label: 'ID Document',
          stepIndex: 1,
          currentStep: currentStep,
        ),
        Expanded(
          child: Container(
            height: 2,
            color: currentStep > 1
                ? AppColors.success
                : Colors.grey.shade300,
          ),
        ),
        _StepDot(
          label: 'Submit',
          stepIndex: 2,
          currentStep: currentStep,
        ),
      ],
    );
  }
}

class _StepDot extends StatelessWidget {
  final String label;
  final int stepIndex;
  final int currentStep;

  const _StepDot({
    required this.label,
    required this.stepIndex,
    required this.currentStep,
  });

  @override
  Widget build(BuildContext context) {
    final isCompleted = currentStep > stepIndex;
    final isActive = currentStep == stepIndex;

    return Column(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isCompleted
                ? AppColors.success
                : isActive
                    ? AppColors.primary
                    : Colors.grey.shade200,
            border: isActive
                ? Border.all(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    width: 3,
                  )
                : null,
          ),
          child: Center(
            child: isCompleted
                ? const Icon(Icons.check, color: Colors.white, size: 18)
                : Text(
                    '${stepIndex + 1}',
                    style: TextStyle(
                      color: isActive ? Colors.white : AppColors.textTertiary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
            color: isCompleted
                ? AppColors.success
                : isActive
                    ? AppColors.primary
                    : AppColors.textTertiary,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Photo Card with dashed border when empty
// ---------------------------------------------------------------------------
class _PhotoCard extends StatelessWidget {
  final int stepNumber;
  final String title;
  final String subtitle;
  final IconData icon;
  final Uint8List? imageBytes;
  final VoidCallback onTap;
  final bool isActive;

  const _PhotoCard({
    required this.stepNumber,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.imageBytes,
    required this.onTap,
    required this.isActive,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = imageBytes != null;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: hasImage
              ? Colors.white
              : isActive
                  ? AppColors.primary.withValues(alpha: 0.03)
                  : AppColors.surfaceLight,
          borderRadius: AppRadius.lgAll,
          border: hasImage
              ? Border.all(color: AppColors.success, width: 2)
              : null,
          boxShadow: hasImage
              ? [
                  BoxShadow(
                    color: AppColors.success.withValues(alpha: 0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: hasImage ? _buildImageView() : _buildEmptyView(context),
      ),
    );
  }

  Widget _buildImageView() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.lg - 1),
      child: Stack(
        children: [
          SizedBox(
            height: 200,
            width: double.infinity,
            child: Image.memory(imageBytes!, fit: BoxFit.cover),
          ),
          // Success badge
          Positioned(
            top: AppSpacing.sm,
            right: AppSpacing.sm,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: AppColors.success,
                borderRadius: AppRadius.smAll,
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check, color: Colors.white, size: 14),
                  SizedBox(width: 4),
                  Text(
                    'Done',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Tap to change
          Positioned(
            bottom: AppSpacing.sm,
            right: AppSpacing.sm,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: AppRadius.smAll,
              ),
              child: const Text(
                'Tap to retake',
                style: TextStyle(color: Colors.white, fontSize: 11),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyView(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(
        color: isActive ? AppColors.primary : Colors.grey.shade300,
        borderRadius: AppRadius.lg,
        strokeWidth: 1.5,
        dashWidth: 8,
        dashSpace: 5,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.xxl,
          horizontal: AppSpacing.lg,
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: isActive
                    ? AppColors.primary.withValues(alpha: 0.1)
                    : Colors.grey.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 36,
                color: isActive ? AppColors.primary : AppColors.textTertiary,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
                color: isActive
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textTertiary,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton.icon(
              onPressed: onTap,
              icon: Icon(
                stepNumber == 1 ? Icons.camera_alt_rounded : Icons.upload_rounded,
                size: 18,
              ),
              label: Text(
                stepNumber == 1 ? 'Open Camera' : 'Choose Photo',
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: isActive ? AppColors.primary : AppColors.textSecondary,
                side: BorderSide(
                  color: isActive ? AppColors.primary : Colors.grey.shade300,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: AppRadius.mdAll,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dashed Border Painter
// ---------------------------------------------------------------------------
class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double borderRadius;
  final double strokeWidth;
  final double dashWidth;
  final double dashSpace;

  _DashedBorderPainter({
    required this.color,
    required this.borderRadius,
    required this.strokeWidth,
    required this.dashWidth,
    required this.dashSpace,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, size.width, size.height),
          Radius.circular(borderRadius),
        ),
      );

    final dashPath = _createDashedPath(path);
    canvas.drawPath(dashPath, paint);
  }

  Path _createDashedPath(Path source) {
    final result = Path();
    for (final metric in source.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final end = (distance + dashWidth).clamp(0, metric.length).toDouble();
        result.addPath(metric.extractPath(distance, end), Offset.zero);
        distance += dashWidth + dashSpace;
      }
    }
    return result;
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      color != oldDelegate.color ||
      borderRadius != oldDelegate.borderRadius;
}
