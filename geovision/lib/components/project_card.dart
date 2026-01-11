import 'package:flutter/material.dart';
import '../pages/project_container.dart';
import '../functions/metadata_handle.dart';

class ProjectCard extends StatelessWidget {
  final String title;
  final VoidCallback? onReturn;
  final IconData? iconData;

  const ProjectCard({
    super.key,
    required this.title,
    required this.onReturn,
    this.iconData,
  });

  Future<Map<String, int>> _fetchProjectStats() async {
    final results = await Future.wait([
      MetadataService.readCsvData(title),
      MetadataService.getClasses(title),
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
        // Just navigate directly. The ProjectContainerPage will handle the timestamp update.
        await Navigator.push(context, MaterialPageRoute(
          builder: (context) => ProjectContainerPage(projectName: title),
        ));

        // Refresh the home page list when returning
        if (onReturn != null) {
          onReturn!();
        }
      },
      child: Container(
        width: 100,
        height: 100,
        margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 5),
        padding: const EdgeInsets.all(12),
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
            int imageCount = 0;
            int classCount = 0;

            if (snapshot.hasData) {
              imageCount = snapshot.data!['images'] ?? 0;
              classCount = snapshot.data!['classes'] ?? 0;
            }

            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                        iconData ?? Icons.folder,
                        color: Colors.green[800],
                        size: 20
                    ),

                    const SizedBox(width: 12),

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildStatBadge(Icons.image, imageCount.toString(), Colors.blue[800]!),
                          const SizedBox(height: 4),
                          _buildStatBadge(Icons.label, classCount.toString(), Colors.orange[900]!),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildStatBadge(IconData icon, String text, Color color) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[800],
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}