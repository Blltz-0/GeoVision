import 'package:flutter/material.dart';
import 'dart:io';
import 'gradient_card_overlay.dart';

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
        border: Border.all(color: Colors.grey.withOpacity(0.2)), // Fixed withValues to withOpacity (standard)
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
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

            // LAYER 2: The Gradient Overlay
            // We use Positioned.fill so the gradient covers the whole image area
            // (or keep your Positioned logic if you only want it at the bottom)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              top: 0, // Added 'top: 0' so the gradient fills the full height
              child: GradientCardOverlay(
                indicatorColor: classColor, // ✅ FIX: Use the variable passed in the constructor
              ),
            ),

            // LAYER 3: The Text Label (Optional, if you want to see the class name)
            if (className != null)
              Positioned(
                bottom: 8,
                left: 8,
                child: Text(
                  className!,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}