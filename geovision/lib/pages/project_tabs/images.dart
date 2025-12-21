import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:native_exif/native_exif.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

// Your custom imports
import 'package:geovision/components/class_selector_dropdown.dart';
import '../../components/image_grid.dart';
import '../../functions/metadata_handle.dart';
import '../../functions/camera/image_processor.dart';

class ImagesPage extends StatefulWidget {
  final String projectName;

  // --- DATA FROM PARENT ---
  final List<File> images;
  final Map<String, String> labelMap;
  final List<dynamic> projectClasses;
  final bool isLoading;

  // Callbacks
  final VoidCallback? onDataChanged;
  final VoidCallback? onClassesUpdated;

  const ImagesPage({
    super.key,
    required this.projectName,
    required this.images,
    required this.labelMap,
    required this.projectClasses,
    required this.isLoading,
    this.onDataChanged,
    this.onClassesUpdated,
  });

  @override
  State<ImagesPage> createState() => _ImagesPageState();
}

class _ImagesPageState extends State<ImagesPage> {
  String _filterClass = "All";
  bool _isImporting = false;
  bool _groupByClass = false; // <--- 1. NEW STATE VARIABLE

  Future<void> _importImage() async {
    // 1. Permission Check
    if (Platform.isAndroid) {
      var status = await Permission.accessMediaLocation.status;
      if (!status.isGranted) status = await Permission.accessMediaLocation.request();
      if (await Permission.photos.request().isDenied) return;
    }

    // 2. Pick Multiple Images
    final ImagePicker picker = ImagePicker();
    // CHANGED: Use pickMultiImage() to get a List<XFile>
    final List<XFile> pickedFiles = await picker.pickMultiImage();

    if (pickedFiles.isEmpty) return;

    setState(() => _isImporting = true);

    // 3. Determine Class (Applies to the whole batch)
    String targetClass = "Unclassified";
    if (_filterClass != "All") {
      targetClass = _filterClass;
    }

    int successCount = 0;

    try {
      // 4. Loop through every selected file
      for (final file in pickedFiles) {
        try {
          // We moved the complex logic into a helper function to keep this clean
          await _processSingleImport(file, targetClass);
          successCount++;
        } catch (e) {
          debugPrint("Failed to import ${file.name}: $e");
        }
      }

      // 5. UI Feedback
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Successfully imported $successCount images")),
        );
        widget.onDataChanged?.call();
      }

    } catch (e) {
      debugPrint("Batch Import Error: $e");
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  // Helper to process a single file from the batch
  Future<void> _processSingleImport(XFile file, String targetClass) async {
    // A. Capture Original GPS (Before processing wipes it)
    Position? importedPosition;
    try {
      final exif = await Exif.fromPath(file.path);
      final latLong = await exif.getLatLong();
      await exif.close();

      if (latLong != null) {
        importedPosition = Position(
          latitude: latLong.latitude,
          longitude: latLong.longitude,
          timestamp: DateTime.now(),
          accuracy: 0, altitude: 0, heading: 0, speed: 0, speedAccuracy: 0, altitudeAccuracy: 0, headingAccuracy: 0,
        );
      }
    } catch (e) {
      debugPrint("Could not read EXIF for ${file.name}: $e");
    }

    // B. Resize & Crop (using your image_processor.dart)
    await compute(cropSquareImage, file.path);

    // C. Generate Filename
    final appDir = await getApplicationDocumentsDirectory();
    final projectDir = Directory('${appDir.path}/projects/${widget.projectName}/images');

    if (!await projectDir.exists()) {
      await projectDir.create(recursive: true);
    }

    final String fileName = await MetadataService.generateNextFileName(
        projectDir,
        widget.projectName,
        targetClass
    );
    final String newPath = '${projectDir.path}/$fileName';

    // D. Copy File
    await File(file.path).copy(newPath);

    // E. Save Metadata & CSV
    await MetadataService.embedMetadata(
      filePath: newPath,
      lat: importedPosition?.latitude ?? 0.0,
      lng: importedPosition?.longitude ?? 0.0,
      className: targetClass,
    );

    await MetadataService.saveToCsv(
      projectName: widget.projectName,
      imagePath: newPath,
      position: importedPosition,
      className: targetClass,
    );
  }

  // --- 2. HELPER: Build Grouped Sections ---
  Widget _buildGroupedView(List<File> imagesToDisplay) {
    // Get unique classes from the current list
    final Set<String> uniqueClasses = imagesToDisplay.map((file) {
      final filename = file.path.split(Platform.pathSeparator).last;
      return widget.labelMap[filename] ?? "Unclassified";
    }).toSet();

    // Sort classes alphabetically
    final sortedClasses = uniqueClasses.toList()..sort();

    return Column(
      children: sortedClasses.map((className) {
        // Filter images for this specific class
        final classImages = imagesToDisplay.where((file) {
          final filename = file.path.split(Platform.pathSeparator).last;
          final label = widget.labelMap[filename] ?? "Unclassified";
          return label == className;
        }).toList();

        // Get class color
        final classDef = widget.projectClasses.firstWhere(
                (c) => c['name'] == className,
            orElse: () => {'color': Colors.grey.toARGB32()}
        );
        Color headerColor = Color(classDef['color']);

        // Prepare grid data
        final gridData = classImages.map((file) {
          final filename = file.path.split(Platform.pathSeparator).last;
          return {
            "path": file.path,
            "label": widget.labelMap[filename],
          };
        }).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Section Header
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              margin: const EdgeInsets.only(top: 15, bottom: 5),
              decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: headerColor, width: 2))
              ),
              child: Row(
                children: [
                  CircleAvatar(radius: 6, backgroundColor: headerColor),
                  const SizedBox(width: 8),
                  Text(
                    "$className (${classImages.length})",
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87
                    ),
                  ),
                ],
              ),
            ),
            // The Grid for this section
            ImageGrid(
              columns: 3,
              itemCount: gridData.length,
              dataList: gridData,
              projectName: widget.projectName,
              onBack: () => widget.onDataChanged?.call(),
              projectClasses: widget.projectClasses,
              // IMPORTANT: disable scrolling inside the grid so the outer ScrollView handles it
              physics: const NeverScrollableScrollPhysics(),
              shrinkWrap: true,
            ),
          ],
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isLoading || _isImporting) {
      return const Center(child: CircularProgressIndicator());
    }

    // Filter based on Dropdown Selection first
    List<File> filteredImages = widget.images;
    if (_filterClass != "All") {
      filteredImages = widget.images.where((file) {
        final filename = file.path.split(Platform.pathSeparator).last;
        final fileClass = widget.labelMap[filename] ?? "Unclassified";
        return fileClass == _filterClass;
      }).toList();
    }

    // Data for Flat View
    final List<Map<String, dynamic>> flatGridData = filteredImages.map((file) {
      final filename = file.path.split(Platform.pathSeparator).last;
      return {
        "path": file.path,
        "label": widget.labelMap[filename],
      };
    }).toList();

    return Scaffold(
      body: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        child: Container(
          constraints: BoxConstraints(
            minHeight: MediaQuery.of(context).size.height,
          ),
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Dropdown

              // --- SWITCH UI ---
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween, // Places items at edges
                  children: [
                    // LEFT: Image Count
                    Text(
                      "${filteredImages.length} Images",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[600],
                      ),
                    ),

                    // RIGHT: Group Switch
                    Row(
                      children: [
                        Text(
                            "Group by Class",
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey[600])
                        ),
                        const SizedBox(width: 8),
                        Transform.scale(
                          scale: 0.8,
                          child: Switch(
                            value: _groupByClass,
                            activeThumbColor: Colors.lightGreen,
                            onChanged: (val) {
                              setState(() => _groupByClass = val);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  duration: Duration(milliseconds: 700),
                                  content: Text(_groupByClass ? "Grouped by Class" : "Ungrouped"),
                                  behavior: SnackBarBehavior.floating, // This makes it float
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],

                    ),
                  ],
                ),
              ),
              ClassSelectorDropdown(
                projectName: widget.projectName,
                selectedClass: _filterClass,
                classes: widget.projectClasses,
                onClassAdded: widget.onClassesUpdated,
                onClassSelected: (String newClass) {
                  setState(() => _filterClass = newClass);
                },
              ),

              const SizedBox(height: 10),

              // Empty State
              if (filteredImages.isEmpty)
                const Center(child: Padding(
                  padding: EdgeInsets.only(top: 50.0),
                  child: Text("No images found"),
                ))

              // --- 4. CONDITIONAL VIEW ---
              else if (_groupByClass)
                _buildGroupedView(filteredImages)
              else
                ImageGrid(
                  columns: 3,
                  itemCount: flatGridData.length,
                  dataList: flatGridData,
                  projectName: widget.projectName,
                  onBack: () => widget.onDataChanged?.call(),
                  projectClasses: widget.projectClasses,
                  physics: const NeverScrollableScrollPhysics(),
                  shrinkWrap: true,
                ),

              // Extra padding for FAB
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),

      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_images',
        shape: const StadiumBorder(),
        backgroundColor: Colors.white,
        label: const Text("Upload Image", style: TextStyle(color: Colors.black87)),
        icon: const Icon(Icons.add_a_photo_outlined),
        onPressed: _importImage,
        tooltip: 'Import Image',
      ),
    );
  }
}