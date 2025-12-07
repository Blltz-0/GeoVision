import 'package:flutter/material.dart';

class GradientCardOverlay extends StatelessWidget {
  final Color? indicatorColor; // The little colored dot for the class

  const GradientCardOverlay({
    super.key,
    this.indicatorColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      // The Gradient Scrim
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black54, // The dark shadow
            Colors.black87,
          ],
          stops: [0.0, 0.6, 1.0], // Starts fading in at 60% down
        ),
      ),
      padding: const EdgeInsets.all(8.0),
      alignment: Alignment.bottomLeft, // Text sits at bottom left
    );
  }
}