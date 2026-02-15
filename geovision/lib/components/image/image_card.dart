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
        border: Border.all(color: Colors.grey.withValues(alpha:0.2)),
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
                cacheHeight: 300,
                cacheWidth: 300,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: Colors.grey[300],
                    child: const Center(child: Icon(Icons.broken_image, color: Colors.grey)),
                  );
                },
              ),
            ),

            // LAYER 2: The Gradient Overlay
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              top: 0,
              child: GradientCardOverlay(
                indicatorColor: classColor,
              ),
            ),

            // LAYER 3: The Text Label
            if (className != null)
              Positioned(
                bottom: 8,
                left: 8,
                child: Text(
                  className!,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      shadows: [
                        Shadow(offset: Offset(0,1), blurRadius: 2, color: Colors.black)
                      ]
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}