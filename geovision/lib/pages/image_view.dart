import 'dart:io';
import 'package:flutter/material.dart';
import '../components/class_creator.dart';
import '../components/ellipsis_menu.dart';
import '../functions/metadata_handle.dart';
import 'package:flutter/services.dart';

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

  List<Map<String, dynamic>> _metadataCache = [];

  Map<String, Color> _classColorMap = {};

  @override
  void initState() {
    super.initState();
    // 2. Initialize the controller to start at the clicked image
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _loadMetadata();
  }

  Future<void> _loadMetadata() async {
    // 1. Read CSV (Data)
    final data = await MetadataService.readCsvData(widget.projectName);

    // 2. Read Classes (Colors)
    final classDefs = await MetadataService.getClasses(widget.projectName);

    if (mounted) {
      setState(() {
        _metadataCache = data;

        // 3. Convert List to Map for easy lookup: {"Crack": Colors.red, "Wall": Colors.blue}
        _classColorMap = {};
        for (var cls in classDefs) {
          _classColorMap[cls['name']] = Color(cls['color']);
        }
      });
    }
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

  void _showTaggingSheet() async {
    // 1. Get the current image path
    final currentPath = widget.allImagePaths[_currentIndex];

    // 2. Load available classes from disk
    final classes = await MetadataService.getClasses(widget.projectName);

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              "Assign Class",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 15),

            // 3. List Existing Classes
            if (classes.isEmpty)
              const Padding(
                padding: EdgeInsets.all(15),
                child: Text(
                  "No classes defined yet.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),

            // Generate a tile for each class
            Flexible(
              child: ListView(
                shrinkWrap: true, // Important for BottomSheet
                children: classes.map((cls) => ListTile(
                  leading: CircleAvatar(
                      backgroundColor: Color(cls['color']),
                      radius: 12
                  ),
                  title: Text(cls['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                  onTap: () async {
                    // Show loading or blocking UI here if needed

                    // 1. Perform the Rename & Tagging
                    await MetadataService.tagImage(
                        widget.projectName,
                        currentPath,
                        cls['name']
                    );

                    // 2. Close Bottom Sheet
                    Navigator.pop(context);

                    // 3. CRITICAL: Close the Image Viewer Page too!
                    // Why? Because "currentPath" is now a dead link.
                    // We need to go back to the Grid so it can reload the new filename.
                    Navigator.pop(context);

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("Renamed & Tagged as '${cls['name']}'")),
                    );
                  },
                )).toList(),
              ),
            ),

            const Divider(),

            // 4. Button to Create NEW Class
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.add),
              label: const Text("Create New Class"),
              onPressed: () async {
                // Close the bottom sheet first
                Navigator.pop(context);

                // Navigate to your CreateClassPage
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => CreateClassPage(projectName: widget.projectName),
                  ),
                );

                // Re-open this sheet so the user can select the new class immediately
                if (mounted) _showTaggingSheet();
              },
            )
          ],
        ),
      ),
    ).whenComplete(() {
      // 2. RESTORE SYSTEM NAVIGATION
      // This runs immediately when the sheet closes (by tap, swipe, or button)
      // "edgeToEdge" is the standard modern Android look.
      // If that looks wrong on your specific phone, use 'SystemUiMode.manual, overlays: SystemUiOverlay.values'
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    });
  }

  Map<String, dynamic> _getCurrentImageInfo(String imagePath) {
    if (_metadataCache.isEmpty) return {};

    final String filename = imagePath.split(Platform.pathSeparator).last;

    // Find the row where the path contains this filename
    return _metadataCache.firstWhere(
          (element) {
        String csvPath = element['path']?.toString() ?? "";
        return csvPath.contains(filename);
      },
      orElse: () => {}, // Return empty if not found
    );
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
            },
            onTag: _showTaggingSheet,
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
        itemBuilder: (context, index) {
          final imagePath = widget.allImagePaths[index];

          // 1. GET DATA FOR THIS SPECIFIC INDEX
          // We assume you have the _metadataCache logic from previous steps.
          // If not, see the helper function below.
          final info = _getCurrentImageInfo(imagePath);
          String className = info['class'] ?? "Unclassified";

          Color tagColor = _classColorMap[className] ?? Colors.grey;

          String lat = info['lat']?.toString() ?? "--";
          String lng = info['lng']?.toString() ?? "--";
          String dateString = "--";

          if (info['time'] != null) {
            try {
              final dt = DateTime.parse(info['time']);
              dateString = "${dt.year}-${dt.month}-${dt.day} ${dt.hour}:${dt.minute}";
            } catch (_) {}
          }

          return Column(
            children: [
              // -------------------------------------------------------
              // 2. THE INFO HEADER (Replaces your SizedBox 100)
              // -------------------------------------------------------
              Container(
                height: 100,
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                color: Colors.black54, // Semi-transparent background
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top Row: Filename + Class Tag
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            imagePath.split(Platform.pathSeparator).last,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: tagColor.withOpacity(0.8),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            className,
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        )
                      ],
                    ),
                    const Spacer(),
                    // Bottom Row: Date + GPS
                    Row(
                      children: [
                        const Icon(Icons.calendar_today, color: Colors.white70, size: 14),
                        const SizedBox(width: 5),
                        Text(dateString, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                        const SizedBox(width: 15),
                        const Icon(Icons.location_on, color: Colors.redAccent, size: 14),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text("$lat, $lng",
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // -------------------------------------------------------
              // 3. THE IMAGE (Must be Expanded to fill remaining space)
              // -------------------------------------------------------
              InteractiveViewer(
                panEnabled: true,
                boundaryMargin: const EdgeInsets.all(20),
                minScale: 1,
                maxScale: 4.0,
                child: Hero(
                  tag: imagePath,
                  child: Image.file(
                    File(imagePath),
                    fit: BoxFit.contain, // Ensures whole image is visible
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
