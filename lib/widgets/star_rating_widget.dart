import 'package:flutter/material.dart';

class StarRatingWidget extends StatelessWidget {
  final double rating;
  final int starCount;
  final double size;
  final Color color;
  final ValueChanged<int>? onRatingChanged;

  const StarRatingWidget({
    super.key,
    required this.rating,
    this.starCount = 5,
    this.size = 28,
    this.color = Colors.amber,
    this.onRatingChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(starCount, (i) {
        final filled = i < rating.floor();
        final half = !filled && (i < rating);
        return GestureDetector(
          onTap: onRatingChanged != null
              ? () => onRatingChanged!(i + 1)
              : null,
          child: Icon(
            filled
                ? Icons.star_rounded
                : half
                    ? Icons.star_half_rounded
                    : Icons.star_outline_rounded,
            color: color,
            size: size,
          ),
        );
      }),
    );
  }
}