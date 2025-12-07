import 'package:flutter/material.dart';
import 'dart:io';
import 'gradient_card_overlay.dart'; // <--- Import the overlay widget

class ImageCard extends StatelessWidget {
  final String imagePath;
  final String? className;
  final Color? classColor;

  const ImageCard({
    super.key,
    required this.imagePath,
    this.className,
    this.classColor,
  });

  @override
  Widget build(BuildContext context) {

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.withValues(alpha:0.2)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand, // Ensures children fill the box
          children: [
            // LAYER 1: The Image
            Hero(
              tag: imagePath,
              child: Image.file(
                File(imagePath),
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: Colors.grey[300],
                    child: const Center(child: Icon(Icons.broken_image, color: Colors.grey)),
                  );
                },
              ),
            ),

            // LAYER 2: The Gradient Overlay (Scrim)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: GradientCardOverlay(
                indicatorColor: classColor, // Shows the Red/Green dot
              ),
            ),
          ],
        ),
      ),
    );
  }
}