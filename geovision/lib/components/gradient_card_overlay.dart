import 'package:flutter/material.dart';

class GradientCardOverlay extends StatelessWidget {
  final Color? indicatorColor;

  const GradientCardOverlay({
    super.key,
    this.indicatorColor,
  });

  @override
  Widget build(BuildContext context) {
    // 1. FIX: Change fallback from Red back to Black.
    // If a class color exists, use it. If not, use a dark shadow.
    final Color baseColor = indicatorColor ?? Colors.black;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            // Top: Invisible
            baseColor.withOpacity(0.0),

            // Middle: Soft tint
            baseColor.withOpacity(0.4),

            // Bottom: Strong lighting (Very opaque)
            baseColor.withOpacity(0.9),
          ],
          // The "Strong Lighting" stops
          stops: const [0.3, 0.7, 1.0],
        ),
      ),
    );
  }
}