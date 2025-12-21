import 'package:flutter/material.dart';
import '../pages/project_container.dart';
import '../functions/metadata_handle.dart'; // Import your service

class ProjectCard extends StatelessWidget {
  final String title;
  final VoidCallback? onReturn;

  const ProjectCard({
    super.key,
    required this.title,
    required this.onReturn,
  });

  /// 1. Helper to fetch stats (Image count & Class count)
  Future<Map<String, int>> _fetchProjectStats() async {
    // Run both fetch operations in parallel
    final results = await Future.wait([
      MetadataService.readCsvData(title), // Get all images
      MetadataService.getClasses(title),  // Get all defined classes
    ]);

    final List<Map<String, dynamic>> images = results[0];
    final List<dynamic> classes = results[1] as List<dynamic>;

    return {
      'images': images.length,
      'classes': classes.length,
    };
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        await Navigator.push(context, MaterialPageRoute(
          builder: (context) => ProjectContainerPage(projectName: title),
        ));
        if (onReturn != null) {
          onReturn!();
        }
      },
      child: Container(
        // Removed fixed width: 75 so it can expand to fit the stats
        height: 90,
        margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 5),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.lightGreenAccent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            )
          ],
        ),
        child: FutureBuilder<Map<String, int>>(
          future: _fetchProjectStats(),
          builder: (context, snapshot) {
            // Default values while loading
            int imageCount = 0;
            int classCount = 0;

            if (snapshot.hasData) {
              imageCount = snapshot.data!['images'] ?? 0;
              classCount = snapshot.data!['classes'] ?? 0;
            }

            return Column(
              children: [
                Row(
                  children: [
                    // 1. Folder Icon (Left)
                    const Icon(Icons.folder, color: Colors.green, size: 30),

                    // 2. Info Column (Right)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Title
                        const SizedBox(height: 4),

                        // Stats Row (Images & Labels)
                        _buildStatBadge(Icons.image, imageCount.toString(), Colors.blue),
                        const SizedBox(width: 12),
                        // Class/Tag Count
                        _buildStatBadge(Icons.label, classCount.toString(), Colors.orange),
                      ],
                    ),

                  ],
                ),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // Helper widget for the small icons with numbers
  Widget _buildStatBadge(IconData icon, String text, Color color) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[700],
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}