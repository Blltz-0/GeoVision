import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:native_exif/native_exif.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:geovision/components/class_selector_dropdown.dart';
import '../../components/image_grid.dart';
import '../../functions/metadata_handle.dart';
import '../../functions/camera/image_processor.dart';

class ImagesPage extends StatefulWidget {
  final String projectName;
  final List<File> images;
  final Map<String, String> labelMap;
  final List<dynamic> projectClasses;
  final bool isLoading;
  final String projectType;

  // 1. ADD CALLBACK HERE
  final Function(String)? onAnnotate;

  final VoidCallback? onDataChanged;
  final VoidCallback? onClassesUpdated;

  const ImagesPage({
    super.key,
    required this.projectName,
    required this.images,
    required this.labelMap,
    required this.projectClasses,
    required this.isLoading,
    required this.projectType,
    this.onDataChanged,
    this.onClassesUpdated,
    this.onAnnotate, // 2. Receive it
  });

  @override
  State<ImagesPage> createState() => _ImagesPageState();
}

class _ImagesPageState extends State<ImagesPage> {
  final Set<String> _collapsedClasses = {};
  String _filterClass = "All";
  bool _isImporting = false;
  bool _groupByClass = false;

  Future<void> _importImage() async {
    // Permission Check
    if (Platform.isAndroid) {
      var status = await Permission.accessMediaLocation.status;
      if (!status.isGranted) status = await Permission.accessMediaLocation.request();
      if (await Permission.photos.request().isDenied) return;
    }

    // Pick Multiple Images
    final ImagePicker picker = ImagePicker();
    final List<XFile> pickedFiles = await picker.pickMultiImage();

    if (pickedFiles.isEmpty) return;

    setState(() => _isImporting = true);

    String targetClass = "Unclassified";
    if (_filterClass != "All") {
      targetClass = _filterClass;
    }

    int successCount = 0;

    try {
      for (final file in pickedFiles) {
        try {
          await _processSingleImport(file, targetClass);
          successCount++;
        } catch (e) {
          debugPrint("Failed to import ${file.name}: $e");
        }
      }

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

  Future<void> _processSingleImport(XFile file, String targetClass) async {
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

    await compute(cropSquareImage, file.path);

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

    await File(file.path).copy(newPath);

    await FileImage(File(newPath)).evict();
    await ResizeImage(FileImage(File(newPath)), width: 300).evict();

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

  List<Widget> _buildGroupedSlivers(List<File> imagesToDisplay) {
    // 1. Get unique classes
    final Set<String> uniqueClasses = imagesToDisplay.map((file) {
      final filename = file.path.split(Platform.pathSeparator).last;
      return widget.labelMap[filename] ?? "Unclassified";
    }).toSet();

    final sortedClasses = uniqueClasses.toList()..sort();

    List<Widget> slivers = [];

    for (var className in sortedClasses) {
      // 2. Filter images
      final classImages = imagesToDisplay.where((file) {
        final filename = file.path.split(Platform.pathSeparator).last;
        final label = widget.labelMap[filename] ?? "Unclassified";
        return label == className;
      }).toList();

      // 3. Get Color
      final classDef = widget.projectClasses.firstWhere(
            (c) => c['name'] == className,
        orElse: () => {'color': Colors.grey.toARGB32()},
      );
      Color headerColor = Color(classDef['color']);

      // 4. Prepare Grid Data
      final gridData = classImages.map((file) {
        final filename = file.path.split(Platform.pathSeparator).last;
        return {
          "path": file.path,
          "label": widget.labelMap[filename],
        };
      }).toList();

      // 5. Check if Expanded
      // If it is NOT in the collapsed set, it is expanded.
      final bool isExpanded = !_collapsedClasses.contains(className);

      // --- PART A: THE CLICKABLE HEADER ---
      slivers.add(
        SliverToBoxAdapter(
          child: InkWell(
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _collapsedClasses.add(className);
                } else {
                  _collapsedClasses.remove(className);
                }
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              margin: const EdgeInsets.only(top: 15, bottom: 5, left: 10, right: 10),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: headerColor, width: 2),
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(radius: 6, backgroundColor: headerColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "$className (${classImages.length})",
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  // The Chevron Icon that rotates based on state
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.grey,
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      // --- PART B: THE LAZY GRID ---
      // We only add the SliverGrid to the array if the group is expanded.
      // Since it's a SliverGrid, it retains pure lazy loading behavior.
      if (isExpanded) {
        slivers.add(
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            sliver: SliverImageGrid(
              columns: 3,
              dataList: gridData,
              projectName: widget.projectName,
              onBack: () => widget.onDataChanged?.call(),
              projectClasses: widget.projectClasses, projectType: widget.projectType,onAnnotate: widget.onAnnotate,
            ),
          ),
        );
      }
    }

    // Bottom padding
    slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 80)));

    return slivers;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isLoading || _isImporting) {
      return const Center(child: CircularProgressIndicator());
    }

    List<File> filteredImages = widget.images;
    if (_filterClass != "All") {
      filteredImages = widget.images.where((file) {
        final filename = file.path.split(Platform.pathSeparator).last;
        final fileClass = widget.labelMap[filename] ?? "Unclassified";
        return fileClass == _filterClass;
      }).toList();
    }

    final List<Map<String, dynamic>> flatGridData = filteredImages.map((file) {
      final filename = file.path.split(Platform.pathSeparator).last;
      return {
        "path": file.path,
        "label": widget.labelMap[filename],
      };
    }).toList();

    return Scaffold(
      body: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.projectType == 'classification') ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "${filteredImages.length} Images",
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[600],
                            ),
                          ),
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
                  ] else ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                      child: Text(
                        "${filteredImages.length} Images",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[600],
                        ),
                      ),
                    ),
                  ]
                ],
              ),
            ),
          ),

          if (filteredImages.isEmpty)
            const SliverFillRemaining(
              child: Center(
                child: Text("No images found"),
              ),
            )

          else if (_groupByClass && widget.projectType == 'classification')
            ..._buildGroupedSlivers(filteredImages)

          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              sliver: SliverImageGrid(
                columns: 3,
                dataList: flatGridData,
                projectName: widget.projectName,
                onBack: () => widget.onDataChanged?.call(),
                projectClasses: widget.projectClasses,
                projectType: widget.projectType,
                onAnnotate: widget.onAnnotate, // 4. Pass it down
              ),
            ),

          if ((!_groupByClass || widget.projectType != 'classification') && filteredImages.isNotEmpty)
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