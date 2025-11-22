import 'package:flutter/material.dart';
import 'dart:io';

class ImageCard extends StatelessWidget{
  //Properties
  final String imagePath;

  //Constructor
  const ImageCard({
    super.key,
    required this.imagePath,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        // Optional: Add a tiny border so white images don't blend into background
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),

      // 3. ClipRRect cuts the image to match the rounded corners
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),

        // 4. Image.file loads the picture from storage
        child: Image.file(
          File(imagePath),

          // 5. BoxFit.cover makes it fill the square without stretching
          fit: BoxFit.cover,

          // 6. Safety: Shows an icon if the image is broken/missing
          errorBuilder: (context, error, stackTrace) {
            return Container(
              color: Colors.grey[300],
              child: const Center(child: Icon(Icons.broken_image, color: Colors.grey)),
            );
          },
        ),
      ),
    );
  }
}