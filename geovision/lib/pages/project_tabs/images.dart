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
// Note: Ensure this points to the UPDATED SliverImageGrid file above
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
  bool _groupByClass = false;

  Future<void> _importImage() async {
    // 1. Permission Check
    if (Platform.isAndroid) {
      var status = await Permission.accessMediaLocation.status;
      if (!status.isGranted) status = await Permission.accessMediaLocation.request();
      if (await Permission.photos.request().isDenied) return;
    }

    // 2. Pick Multiple Images
    final ImagePicker picker = ImagePicker();
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

  // --- HELPER: Build Grouped Sections as SLIVERS ---
  // This replaces your old _buildGroupedView function
  List<Widget> _buildGroupedSlivers(List<File> imagesToDisplay) {
    // Get unique classes from the current list
    final Set<String> uniqueClasses = imagesToDisplay.map((file) {
      final filename = file.path.split(Platform.pathSeparator).last;
      return widget.labelMap[filename] ?? "Unclassified";
    }).toSet();

    // Sort classes alphabetically
    final sortedClasses = uniqueClasses.toList()..sort();

    List<Widget> slivers = [];

    for (var className in sortedClasses) {
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

      // 1. Add the Header for this class
      slivers.add(
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              margin: const EdgeInsets.only(top: 15, bottom: 5, left: 10, right: 10),
              decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: headerColor, width: 2))
              ),
              child: Row(
                children: [
                  CircleAvatar(radius: 6, backgroundColor: headerColor),
                  const SizedBox(width: 8),
                  Text(
                    "$className (${classImages.length})",
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87
                    ),
                  ),
                ],
              ),
            ),
          )
      );

      // 2. Add the Grid for this class
      slivers.add(
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            sliver: SliverImageGrid(
              columns: 3,
              dataList: gridData,
              projectName: widget.projectName,
              onBack: () => widget.onDataChanged?.call(),
              projectClasses: widget.projectClasses,
            ),
          )
      );
    }

    // Bottom padding for the grouped list
    slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 80)));

    return slivers;
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
      // CHANGED: Use CustomScrollView with Slivers for lazy loading
      body: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          // 1. Header Section (Dropdown + Toggle)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // --- SWITCH UI ---
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                                      duration: const Duration(milliseconds: 700),
                                      content: Text(_groupByClass ? "Grouped by Class" : "Ungrouped"),
                                      behavior: SnackBarBehavior.floating,
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

                  // Dropdown
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
                ],
              ),
            ),
          ),

          // 2. Empty State
          if (filteredImages.isEmpty)
            const SliverFillRemaining(
              child: Center(
                child: Text("No images found"),
              ),
            )

          // 3. Conditional View
          else if (_groupByClass)
          // Use spread operator to insert list of Slivers
            ..._buildGroupedSlivers(filteredImages)

          else
          // Single Flat Grid Sliver
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              sliver: SliverImageGrid(
                columns: 3,
                dataList: flatGridData,
                projectName: widget.projectName,
                onBack: () => widget.onDataChanged?.call(),
                projectClasses: widget.projectClasses,
              ),
            ),

          // Extra padding for FAB in flat view (grouped view adds it inside _buildGroupedSlivers)
          if (!_groupByClass && filteredImages.isNotEmpty)
            const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
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