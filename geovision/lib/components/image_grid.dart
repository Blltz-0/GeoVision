import 'package:flutter/material.dart';
import '../pages/image_view.dart';
import 'image_card.dart';

class ImageGrid extends StatelessWidget {
  final int columns;
  final int itemCount;
  final List<Map<String, dynamic>> dataList;
  final String projectName;
  final VoidCallback onBack;

  // ✅ DEFINITION ADDED HERE
  final List<dynamic> projectClasses;

  const ImageGrid({
    super.key,
    required this.columns,
    required this.itemCount,
    required this.dataList,
    required this.projectName,
    required this.onBack,
    // ✅ CONSTRUCTOR UPDATED HERE
    required this.projectClasses,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
      ),
      physics: const NeverScrollableScrollPhysics(),
      itemCount: dataList.length,
      itemBuilder: (context, index) {
        final item = dataList[index];
        final String imagePath = item['path'];

        // 1. Get the class string (e.g. "Cat")
        final String? csvClass = item['label'];

        // 2. Find the Color manually from the raw list
        Color? resolvedColor;

        if (csvClass != null && csvClass.isNotEmpty) {
          try {
            // Robust match: trim spaces and ignore casing
            final matchingClass = projectClasses.firstWhere(
                    (cls) => cls['name'].toString().trim().toLowerCase() == csvClass.trim().toLowerCase()
            );

            // Convert int color to Color object
            resolvedColor = Color(matchingClass['color']);

          } catch (e) {
            resolvedColor = null; // Class not found -> Black shadow
          }
        }

        return GestureDetector(
            onTap: () {
              List<String> allPaths = dataList.map((item) => item['path'] as String).toList();
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => ImageView(
                        allImagePaths: allPaths,
                        initialIndex: index,
                        projectName: projectName,
                      )
                  )
              ).then((_) {
                onBack();
              });
            },
            child: ImageCard(
              imagePath: imagePath,
              className: csvClass,
              classColor: resolvedColor,
            )
        );
      },
    );
  }
}