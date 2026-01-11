import 'package:flutter/material.dart';
import '../pages/project_container.dart'; // Updated import to match your file structure
import '../functions/metadata_handle.dart';

class ProjectList extends StatelessWidget {
  final List<Map<String, dynamic>> dataList;
  final VoidCallback onRefresh;

  const ProjectList({
    super.key,
    required this.dataList,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (dataList.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20.0),
          child: Text(
            "No projects found.",
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: dataList.length,
      itemBuilder: (context, index) {
        final item = dataList[index];
        // Extract type (default to classification if missing)
        final String type = item['type'] ?? 'classification';

        return _ProjectListItem(
          title: item["title"],
          type: type, // Pass type to the item
          onReturn: onRefresh,
        );
      },
    );
  }
}

class _ProjectListItem extends StatelessWidget {
  final String title;
  final String type; // Added type
  final VoidCallback onReturn;

  const _ProjectListItem({
    required this.title,
    required this.type, // Added type
    required this.onReturn,
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
    // 1. Determine UI elements based on Type
    final bool isSegmentation = type == 'segmentation';

    final IconData leadingIcon = isSegmentation ? Icons.brush : Icons.grid_view;
    final Color themeColor = isSegmentation ? Colors.green : Colors.green;
    final String labelText = isSegmentation ? "SEGMENTATION" : "CLASSIFICATION";

    return GestureDetector(
      onTap: () async {
        await Navigator.push(context, MaterialPageRoute(
          builder: (context) => ProjectContainerPage(projectName: title),
        ));
        onReturn();
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ],
          border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
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

            return Row(
              children: [
                // 2. Dynamic Icon & Color
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: themeColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(leadingIcon, color: themeColor, size: 28),
                ),

                const SizedBox(width: 16),

                // 3. Project Name & Type Label
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        labelText, // Shows "CLASSIFICATION" or "SEGMENTATION"
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[500],
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                // 4. Stats Section (Tags & Images)
                Row(
                  children: [
                    // Classes/Tags Column
                    _buildStatColumn(Icons.label_outline, classCount.toString(), Colors.orange),

                    const SizedBox(width: 20),

                    // Images Column
                    _buildStatColumn(Icons.image_outlined, imageCount.toString(), Colors.blue),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildStatColumn(IconData icon, String count, Color color) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(height: 4),
        Text(
          count,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.grey[700],
          ),
        ),
      ],
    );
  }
}