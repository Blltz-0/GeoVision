import 'dart:io';
import 'package:flutter/material.dart';
import '../pages/image_view.dart';
// 1. Import your overlay component
import 'gradient_card_overlay.dart';

class SliverImageGrid extends StatelessWidget {
  final int columns;
  final List<Map<String, dynamic>> dataList;
  final String projectName;
  final VoidCallback? onBack;
  final List<dynamic> projectClasses;

  const SliverImageGrid({
    super.key,
    required this.columns,
    required this.dataList,
    required this.projectName,
    required this.projectClasses,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    Color getClassColor(String className) {
      final cls = projectClasses.firstWhere(
            (c) => c['name'] == className,
        orElse: () => {'color': Colors.grey.toARGB32()},
      );
      return Color(cls['color']);
    }

    return SliverGrid(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1.0,
      ),
      delegate: SliverChildBuilderDelegate(
            (BuildContext context, int index) {
          final item = dataList[index];
          final imagePath = item['path'];
          final label = item['label'] ?? "Unclassified";
          final color = getClassColor(label);

          return GestureDetector(
            onTap: () async {
              final allPaths = dataList.map((e) => e['path'] as String).toList();

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

              if (result == true) {
                onBack?.call();
              }
            },
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: Colors.grey[200],
                // Optional: Add border if you want distinct edges
                border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 0.5),
              ),
              clipBehavior: Clip.hardEdge,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // LAYER 1: The Image (Optimized)
                  Hero(
                    tag: imagePath,
                    child: Image.file(
                      File(imagePath),
                      fit: BoxFit.cover,
                      cacheWidth: 300, // Keeps memory usage low
                      errorBuilder: (ctx, err, stack) => const Center(
                          child: Icon(Icons.broken_image, color: Colors.grey)),
                    ),
                  ),

                  // LAYER 2: Your Gradient Overlay
                  // We pass the class color so the gradient matches the tag
                  Positioned.fill(
                    child: GradientCardOverlay(
                      indicatorColor: color,
                    ),
                  ),

                  // LAYER 3: The Text Label (Floating on top)
                  Positioned(
                    bottom: 6,
                    left: 8,
                    right: 8,
                    child: Text(
                      label,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          shadows: [
                            Shadow(offset: Offset(0, 1), blurRadius: 2, color: Colors.black)
                          ]
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
        childCount: dataList.length,
      ),
    );
  }
}