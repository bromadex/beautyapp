import 'package:flutter/material.dart';
import '../theme.dart';

class StarRatingWidget extends StatelessWidget {
  final double rating;
  final int starCount;
  final double size;
  final Color? filledColor;
  final Color? emptyColor;
  final ValueChanged<int>? onRatingChanged;

  const StarRatingWidget({
    super.key,
    required this.rating,
    this.starCount = 5,
    this.size = 28,
    this.filledColor,
    this.emptyColor,
    this.onRatingChanged,
  });

  @override
  Widget build(BuildContext context) {
    final filled_ = filledColor ?? AppColors.warning;
    final empty_ = emptyColor ?? AppColors.textTertiary;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(starCount, (i) {
        final isFilled = i < rating.floor();
        final isHalf = !isFilled && (i < rating);
        return GestureDetector(
          onTap: onRatingChanged != null
              ? () => onRatingChanged!(i + 1)
              : null,
          child: Icon(
            isFilled
                ? Icons.star_rounded
                : isHalf
                    ? Icons.star_half_rounded
                    : Icons.star_outline_rounded,
            color: isFilled || isHalf ? filled_ : empty_,
            size: size,
          ),
        );
      }),
    );
  }
}
