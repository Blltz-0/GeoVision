
import 'dart:io';
import 'package:flutter/material.dart';
import '../pages/image_view.dart'; // Ensure this points to your ImageView file

class ImageGrid extends StatelessWidget {
  final int columns;
  final int itemCount;
  final List<Map<String, dynamic>> dataList;
  final String projectName;
  final VoidCallback? onBack;
  final List<dynamic> projectClasses;

  // --- NEW PARAMETERS ---
  final ScrollPhysics? physics;
  final bool shrinkWrap;

  const ImageGrid({
    super.key,
    required this.columns,
    required this.itemCount,
    required this.dataList,
    required this.projectName,
    required this.projectClasses,
    this.onBack,
    // Add them to constructor with defaults
    this.physics,
    this.shrinkWrap = false,
  });

  @override
  Widget build(BuildContext context) {
    // Helper to get color from class list
    Color getClassColor(String className) {
      final cls = projectClasses.firstWhere(
            (c) => c['name'] == className,
        orElse: () => {'color': Colors.grey.toARGB32()},
      );
      return Color(cls['color']);
    }

    return GridView.builder(
      // --- USE THEM HERE ---
      physics: physics,
      shrinkWrap: shrinkWrap,

      padding: const EdgeInsets.only(bottom: 20),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: itemCount,
      itemBuilder: (BuildContext context, int index) {
        final item = dataList[index];
        final imagePath = item['path'];
        final label = item['label'] ?? "Unclassified";
        final color = getClassColor(label);

        return GestureDetector(
          onTap: () async {
            // Collect all paths for swipe navigation
            final allPaths = dataList.map((e) => e['path'] as String).toList();

            // 1. Wait for ImageView to close and capture the result
            final bool? result = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ImageView(
                  allImagePaths: allPaths,
                  initialIndex: index,
                  projectName: projectName,
                ),
              ),
            );

            // 2. If result is true, it means an image was renamed or deleted
            if (result == true) {
              onBack?.call(); // Refresh the grid
            }
          },
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: Colors.grey[200],
            ),
            clipBehavior: Clip.hardEdge,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 1. The Image
                Hero(
                  tag: imagePath,
                  child: Image.file(
                    File(imagePath), // Requires import 'dart:io' as java.io alias or plain File
                    fit: BoxFit.cover,
                    errorBuilder: (ctx, err, stack) => const Center(
                        child: Icon(Icons.broken_image, color: Colors.grey)),
                  ),
                ),

                // 2. The Tag Overlay
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    color: color.withValues(alpha:0.8),
                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

