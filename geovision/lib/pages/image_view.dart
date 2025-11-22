import 'dart:io';
import 'package:flutter/material.dart';

import '../components/ellipsis_menu.dart';
import '../functions/metadata_handle.dart';

class ImageView extends StatefulWidget {
  final List<String> allImagePaths;
  final int initialIndex;
  final String projectName;

  const ImageView({
    super.key,
    required this.allImagePaths,
    required this.initialIndex,
    required this.projectName,
  });

  @override
  State<ImageView> createState() => _ImageViewState();
}

class _ImageViewState extends State<ImageView> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    // 2. Initialize the controller to start at the clicked image
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void showImageInformation(BuildContext context, String imagePath){
    final String currentPath = widget.allImagePaths[_currentIndex];
    final String currentFilename = currentPath.split(Platform.pathSeparator).last;

    showDialog(
      context: context,
      builder: (BuildContext dialogContext){
        return AlertDialog(
          title: const Text('Image Information'),
          content: SizedBox(
            height: 200,
            width: double.maxFinite,
            child: FutureBuilder<List<Map<String,dynamic>>>(
              future: MetadataService.readCsvData(widget.projectName),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.isEmpty){
                  return const Text('No data found.');
                }

                final Map<String,dynamic> imageInfo = snapshot.data!.firstWhere(
                  (element) {
                    final String csvPath = element['path']?.toString() ?? "";
                    return csvPath.contains(currentFilename);
                  },
                  orElse: () => {},
                );

                if (imageInfo.isEmpty) {
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, color: Colors.orange, size: 40),
                      const SizedBox(height: 10),
                      const Text("Image not found in records."),
                      Text(currentFilename, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                    ],
                  );
                }

                final String lat = imageInfo['lat']?.toString() ?? "N/A";
                final String lng = imageInfo['lng']?.toString() ?? "N/A";

                // Parse Date Safely
                String dateString = "Unknown";
                String timeString = "Unknown";

                if (imageInfo['time'] != null) {
                  try {
                    final DateTime dt = DateTime.parse(imageInfo['time']);
                    dateString = "${dt.year}-${dt.month}-${dt.day}";
                    timeString = "${dt.hour}:${dt.minute.toString().padLeft(2, '0')}";
                  } catch (e) {
                    // If date format is corrupt, just show raw string or error
                    dateString = "Invalid Date";
                  }
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Text("File: $currentFilename", style: const TextStyle(fontWeight: FontWeight.bold)),
                    const Divider(),
                    Row(children: [
                      const Icon(Icons.calendar_today, size: 16, color: Colors.blue),
                      const SizedBox(width: 8),
                      Text("Date: $dateString"),
                    ]),
                    Row(children: [
                      const Icon(Icons.access_time, size: 16, color: Colors.blue),
                      const SizedBox(width: 8),
                      Text("Time: $timeString"),
                    ]),
                    Row(children: [
                      const Icon(Icons.location_on, size: 16, color: Colors.red),
                      const SizedBox(width: 8),
                      Text("Lat: $lat"),
                    ]),
                    Row(children: [
                      const Icon(Icons.location_on, size: 16, color: Colors.red),
                      const SizedBox(width: 8),
                      Text("Lng: $lng"),
                    ]),
                  ],
                );
              }
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Close'),
              onPressed: (){Navigator.of(dialogContext).pop();},
            ),
          ],
        );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 0.3),
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        title: Text(
          "${_currentIndex + 1} of ${widget.allImagePaths.length}",
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          EllipsisMenu(
            onInfo: () {
              showImageInformation(context, widget.allImagePaths[_currentIndex]);
            },
            onDelete: () async {
              final navigator = Navigator.of(context);
              final messenger = ScaffoldMessenger.of(context);

              final String currentPath = widget.allImagePaths[_currentIndex];

              await MetadataService.deleteImage(
                projectName: widget.projectName,
                imagePath: currentPath,
              );

              navigator.pop();

              messenger.showSnackBar(
                  const SnackBar(
                    content: Text("Image Deleted"),
                    backgroundColor: Colors.redAccent,
                    duration: Duration(seconds: 1),
                  )
                );
              }
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.allImagePaths.length,

        onPageChanged: (index) {
          setState(() {
            _currentIndex = index;
          });
        },

        itemBuilder: (context, index){
          final imagePath = widget.allImagePaths[index];

          return Column(
            children: [
              SizedBox(height: 100,),
              InteractiveViewer(
                  panEnabled: true,
                  boundaryMargin: const EdgeInsets.all(20),
                  minScale: 1,
                  maxScale: 4.0,
                  child: Hero(
                    tag: imagePath,
                    child: Image.file(
                      File(imagePath),
                      fit: BoxFit.contain,
                    ),
                  ),
              ),
            ],
          );
        },
      ),
    );
  }


}
