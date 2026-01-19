import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../pages/image_view.dart';
import 'gradient_card_overlay.dart';

class SliverImageGrid extends StatelessWidget {
  final int columns;
  final List<Map<String, dynamic>> dataList;
  final String projectName;
  final VoidCallback? onBack;
  final List<dynamic> projectClasses;
  final String projectType;
  final Future<bool?> Function(String)? onAnnotate;

  // New Selection Props
  final Set<String>? selectedPaths;
  final Function(String)? onSelectionChanged;

  const SliverImageGrid({
    super.key,
    required this.columns,
    required this.dataList,
    required this.projectName,
    required this.projectClasses,
    required this.projectType,
    this.onBack,
    this.onAnnotate,
    this.selectedPaths,
    this.onSelectionChanged,
  });

  @override
  Widget build(BuildContext context) {
    bool isSelectionMode = selectedPaths != null && selectedPaths!.isNotEmpty;

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

          final bool isSelected = selectedPaths?.contains(imagePath) ?? false;
          final File imageFile = File(imagePath);

          // --- FIX: Safe Metadata Loading (Prevents Crash on Move) ---
          int modTime;
          try {
            if (imageFile.existsSync()) {
              modTime = imageFile.lastModifiedSync().millisecondsSinceEpoch;
            } else {
              // If file is temporarily missing (being moved), use current time to avoid crash
              modTime = DateTime.now().millisecondsSinceEpoch;
            }
          } catch (e) {
            modTime = DateTime.now().millisecondsSinceEpoch;
          }
          // ----------------------------------------------------------

          // --- LOGIC: Check for Annotation Existence & Content ---
          bool hasAnnotation = false;
          if (projectType == 'segmentation') {
            try {
              if (imageFile.existsSync()) {
                final Directory imageDir = imageFile.parent; // /images
                final Directory projectDir = imageDir.parent; // /projects/X
                final String fileNameNoExt = p.basenameWithoutExtension(imagePath);

                final String annotationPath = p.join(
                    projectDir.path, 'annotation', '${fileNameNoExt}_data.json'
                );

                final file = File(annotationPath);
                if (file.existsSync()) {
                  final content = file.readAsStringSync();
                  if (content.isNotEmpty) {
                    final List<dynamic> jsonLayers = jsonDecode(content);
                    hasAnnotation = jsonLayers.any((layer) {
                      final strokes = layer['strokes'] as List?;
                      return strokes != null && strokes.isNotEmpty;
                    });
                  }
                }
              }
            } catch (e) {
              // Silently fail annotation check if file system is busy
            }
          }
          // ---------------------------------------------

          return GestureDetector(
            onLongPress: () {
              onSelectionChanged?.call(imagePath);
            },
            onTap: () async {
              if (isSelectionMode || (selectedPaths != null && selectedPaths!.isNotEmpty)) {
                onSelectionChanged?.call(imagePath);
              } else {
                // Ensure file exists before trying to open it
                if (!File(imagePath).existsSync()) return;

                final allPaths = dataList.map((e) => e['path'] as String).toList();

                final bool? result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ImageView(
                      allImagePaths: allPaths,
                      initialIndex: index,
                      projectName: projectName,
                      projectType: projectType,
                      onAnnotate: onAnnotate,
                    ),
                  ),
                );

                if (result == true) {
                  onBack?.call();
                }
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: Colors.grey[200],
                border: isSelected
                    ? Border.all(color: Colors.blueAccent, width: 3)
                    : Border.all(color: Colors.white.withValues(alpha: 0.1), width: 0.5),
              ),
              clipBehavior: Clip.hardEdge,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 1. The Image
                  Opacity(
                    opacity: isSelected ? 0.7 : 1.0,
                    child: Hero(
                      tag: imagePath,
                      child: Image.file(
                        imageFile,
                        key: ValueKey("$imagePath$modTime"),
                        fit: BoxFit.cover,
                        cacheWidth: 300,
                        errorBuilder: (ctx, err, stack) => const Center(
                          child: Icon(Icons.broken_image, color: Colors.grey),
                        ),
                      ),
                    ),
                  ),

                  // 2. UI: CLASSIFICATION MODE
                  if (projectType == 'classification' && !isSelected) ...[
                    Positioned.fill(
                      child: GradientCardOverlay(indicatorColor: color),
                    ),
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
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],

                  // 3. UI: SEGMENTATION MODE
                  if (projectType == 'segmentation' && hasAnnotation && !isSelected)
                    Positioned(
                      bottom: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha:0.6),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.lightGreenAccent, width: 1),
                        ),
                        child: const Icon(
                          Icons.brush,
                          size: 14,
                          color: Colors.lightGreenAccent,
                        ),
                      ),
                    ),

                  // 4. SELECTION INDICATOR
                  if (isSelected)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.blueAccent,
                        ),
                        child: const Icon(
                          Icons.check,
                          color: Colors.white,
                          size: 20,
                        ),
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