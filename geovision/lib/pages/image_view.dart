import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Adjust these imports to match your project structure
import '../components/class_creator.dart';
import '../functions/metadata_handle.dart';
import '../components/ellipsis_menu.dart';
import 'annotation_page.dart';

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

  // --- 1. LOCAL STATE FOR PATHS ---
  // We copy the paths here so we can update them when a file is renamed
  late List<String> _currentImagePaths;
  bool _hasChanges = false; // Tracks if we need to tell the previous screen to refresh

  List<Map<String, dynamic>> _metadataCache = [];
  Map<String, Color> _classColorMap = {};

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);

    // Initialize our local list from the widget data
    _currentImagePaths = List.from(widget.allImagePaths);

    _loadMetadata();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// Helper to safely get filename from any path string (handles / and \)
  String _getFilename(String path) {
    return path.split(Platform.pathSeparator).last;
  }

  Future<void> _loadMetadata() async {
    final data = await MetadataService.readCsvData(widget.projectName);
    final classDefs = await MetadataService.getClasses(widget.projectName);

    if (mounted) {
      setState(() {
        _metadataCache = data;
        _classColorMap = {};
        for (var cls in classDefs) {
          int colorInt = cls['color'] ?? 0xFF000000;
          _classColorMap[cls['name']] = Color(colorInt);
        }
      });
    }
  }

  // Find info for the currently visible image
  Map<String, dynamic> _getCurrentImageInfo(String imagePath) {
    if (_metadataCache.isEmpty) return {};

    final String targetName = _getFilename(imagePath);

    return _metadataCache.firstWhere(
          (element) {
        String csvPath = element['path']?.toString() ?? "";
        return _getFilename(csvPath) == targetName;
      },
      orElse: () => {},
    );
  }

  void showImageInformation(BuildContext context, String imagePath) {
    final String targetFilename = _getFilename(imagePath);

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Image Information'),
          content: SizedBox(
            height: 200,
            width: double.maxFinite,
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: MetadataService.readCsvData(widget.projectName),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Text('No data found.');
                }

                final Map<String, dynamic> imageInfo = snapshot.data!.firstWhere(
                      (element) {
                    final String csvPath = element['path']?.toString() ?? "";
                    return _getFilename(csvPath) == targetFilename;
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
                      const SizedBox(height: 5),
                      Text(targetFilename,
                          style: const TextStyle(fontSize: 10, color: Colors.grey),
                          textAlign: TextAlign.center),
                    ],
                  );
                }

                final String lat = imageInfo['lat']?.toString() ?? "N/A";
                final String lng = imageInfo['lng']?.toString() ?? "N/A";
                String dateString = "Unknown";
                String timeString = "Unknown";

                if (imageInfo['time'] != null) {
                  try {
                    final DateTime dt = DateTime.parse(imageInfo['time']);
                    dateString = "${dt.year}-${dt.month}-${dt.day}";
                    timeString = "${dt.hour}:${dt.minute.toString().padLeft(2, '0')}";
                  } catch (_) {
                    dateString = "Invalid Date";
                  }
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Text("File: $targetFilename", style: const TextStyle(fontWeight: FontWeight.bold)),
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
              },
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Close'),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
          ],
        );
      },
    );
  }

  void _showTaggingSheet() async {
    // 1. Capture the path before any async gaps to be safe
    final currentPath = _currentImagePaths[_currentIndex];

    // 2. Fetch data (Async)
    final classes = await MetadataService.getClasses(widget.projectName);

    // 3. Check mounted BEFORE showing the sheet
    if (!mounted) return;

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

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
            if (classes.isEmpty)
              const Padding(
                padding: EdgeInsets.all(15),
                child: Text(
                  "No classes defined yet.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: classes.map((cls) => ListTile(
                  leading: CircleAvatar(
                      backgroundColor: Color(cls['color']), radius: 12
                  ),
                  title: Text(cls['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                  onTap: () async {
                    // --- ASYNC OPERATION ---
                    String? newPath = await MetadataService.tagImage(
                      widget.projectName,
                      currentPath,
                      cls['name'],
                    );

                    // --- FIX: CHECK MOUNTED AFTER AWAIT ---
                    if (!mounted) return;

                    Navigator.pop(context); // Close sheet safely

                    if (newPath != null) {
                      // Clear cache logic...
                      await FileImage(File(currentPath)).evict();
                      await FileImage(File(newPath)).evict();

                      if (!mounted) return; // Check again before setState

                      setState(() {
                        _currentImagePaths[_currentIndex] = newPath;
                        _hasChanges = true;
                        _loadMetadata();
                      });

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text("Renamed & Tagged as '${cls['name']}'")),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Error renaming file.")),
                      );
                    }
                  },
                )).toList(),
              ),
            ),
            const Divider(),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.add),
              label: const Text("Create New Class"),
              onPressed: () async {
                // Close the current sheet first
                Navigator.pop(context);

                // Navigate to create page (ASYNC)
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => CreateClassPage(projectName: widget.projectName),
                  ),
                );

                // --- FIX: CHECK MOUNTED BEFORE RE-OPENING SHEET ---
                if (!mounted) return;

                // Now safe to call a method that uses 'context'
                _showTaggingSheet();
              },
            )
          ],
        ),
      ),
    ).whenComplete(() {
      // safe to call this without context
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Intercept back button to ensure we pass changes back to ImageGrid
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.pop(context, _hasChanges);
      },
      child: Scaffold(
        backgroundColor: Colors.black.withValues(alpha: 0.9),
        appBar: AppBar(
          backgroundColor: Colors.black,
          iconTheme: const IconThemeData(color: Colors.white),
          elevation: 0,
          title: Text(
            // Use local list for count
            "${_currentIndex + 1} of ${_currentImagePaths.length}",
            style: const TextStyle(color: Colors.white),
          ),
          actions: [
            EllipsisMenu(
              onInfo: () => showImageInformation(context, _currentImagePaths[_currentIndex]),
              onDelete: () async {
                final navigator = Navigator.of(context);
                final messenger = ScaffoldMessenger.of(context);
                final String currentPath = _currentImagePaths[_currentIndex];

                await MetadataService.deleteImage(
                  projectName: widget.projectName,
                  imagePath: currentPath,
                );

                // Return 'true' to signal a deletion happened
                navigator.pop(true);
                messenger.showSnackBar(const SnackBar(
                  content: Text("Image Deleted"),
                  backgroundColor: Colors.redAccent,
                  duration: Duration(seconds: 1),
                ));
              },
              onTag: _showTaggingSheet,
            ),
          ],
        ),
        body: PageView.builder(
          controller: _pageController,
          itemCount: _currentImagePaths.length, // Use local list
          onPageChanged: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          itemBuilder: (context, index) {
            final imagePath = _currentImagePaths[index]; // Use local list
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
                // Top Information Bar
                Container(
                  height: 100,
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  color: Colors.black54,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _getFilename(imagePath),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: tagColor.withValues(alpha: 0.8),
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
                      Row(
                        children: [
                          const Icon(Icons.calendar_today, color: Colors.white70, size: 14),
                          const SizedBox(width: 5),
                          Text(dateString, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                          const SizedBox(width: 15),
                          const Icon(Icons.location_on, color: Colors.redAccent, size: 14),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              "$lat, $lng",
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Image Viewer
                Expanded(
                  child: InteractiveViewer(
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
                ),
              ],
            );
          },
        ),
        floatingActionButton: FloatingActionButton.extended(
          heroTag: 'fab_annotate',
          shape: const StadiumBorder(),
          backgroundColor: Colors.white,
          label: const Text("Annotate", style: TextStyle(color: Colors.black87)),
          icon: const Icon(Icons.brush_rounded),
          onPressed: () {
            // Get the current path from your local state
            final String currentPath = _currentImagePaths[_currentIndex];

            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => AnnotationPage(imagePath: currentPath),
              ),
            );
          },
          tooltip: 'Import Image',
        ),
      ),
    );
  }
}