import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:geovision/components/classes/class_selector_dropdown.dart';
import '../../components/classes/class_picker.dart';
import '../../components/image/image_grid.dart';
import '../../functions/data_service/metadata_handle.dart';
import '../../functions/image/image_metadata.dart';
import '../../functions/image/image_resizer.dart';

class ImagesPage extends StatefulWidget {
  final String projectName;
  final List<File> images;
  final Map<String, String> labelMap;
  final List<dynamic> projectClasses;
  final bool isLoading;
  final String projectType;
  final Future<bool?> Function(String)? onAnnotate;

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
    this.onAnnotate,
  });

  @override
  State<ImagesPage> createState() => _ImagesPageState();
}

class _ImagesPageState extends State<ImagesPage> {
  final Set<String> _collapsedClasses = {};
  String _filterClass = "All";

  final Set<String> _selectedPaths = {};
  bool get _isSelectionMode => _selectedPaths.isNotEmpty;

  bool _groupByClass = false;
  bool _isUploading = false;
  int _totalUploads = 0;
  int _currentUploadCount = 0;

  final List<File> _tempUploadedImages = [];

  // --- SELECTION LOGIC ---
  void _toggleSelection(String path) {
    setState(() {
      if (_selectedPaths.contains(path)) {
        _selectedPaths.remove(path);
      } else {
        _selectedPaths.add(path);
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedPaths.clear();
    });
  }

  void _selectAll(List<File> currentViewImages) {
    setState(() {
      final visiblePaths = currentViewImages.map((e) => e.path).toSet();
      if (_selectedPaths.containsAll(visiblePaths)) {
        _selectedPaths.removeAll(visiblePaths);
      } else {
        _selectedPaths.addAll(visiblePaths);
      }
    });
  }

  // --- BULK ACTIONS ---
  Future<void> _deleteSelectedImages() async {
    final count = _selectedPaths.length;
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Images"),
        content: Text("Are you sure you want to delete $count image(s)?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    List<String> pathsToDelete = _selectedPaths.toList();

    for (String path in pathsToDelete) {
      try {
        await MetadataService.deleteImage(
          projectName: widget.projectName,
          imagePath: path,
          projectType: widget.projectType,
        );
        final filename = path.split(Platform.pathSeparator).last;
        widget.labelMap.remove(filename);
      } catch (e) {
        debugPrint("Error deleting $path: $e");
      }
    }

    widget.images.removeWhere((f) => pathsToDelete.contains(f.path));
    _clearSelection();
    widget.onDataChanged?.call();
  }

  Future<void> _tagSelectedImages() async {
    // Replaced complex inline method with the new Helper Class
    String? targetClass = await ClassPickerDialog.show(
      context: context,
      projectName: widget.projectName,
      onClassesUpdated: widget.onClassesUpdated,
    );

    if (targetClass == null) return;

    List<String> pathsToProcess = _selectedPaths.toList();
    _clearSelection();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Moving ${pathsToProcess.length} images to '$targetClass'..."),
          duration: const Duration(seconds: 2),
        ),
      );
    }
    _processTaggingBackground(pathsToProcess, targetClass);
  }

  Future<void> _processTaggingBackground(List<String> paths, String targetClass) async {
    int successCount = 0;

    for (String path in paths) {
      try {
        String oldFilename = path.split(Platform.pathSeparator).last;

        String? newPath = await MetadataService.tagImage(
          widget.projectName,
          path,
          targetClass,
          projectType: widget.projectType,
        );

        if (newPath != null) {
          await FileImage(File(path)).evict();
          await FileImage(File(newPath)).evict();

          String newFilename = newPath.split(Platform.pathSeparator).last;

          setState(() {
            widget.labelMap.remove(oldFilename);
            widget.labelMap[newFilename] = targetClass;

            final mainIndex = widget.images.indexWhere((f) => f.path == path);
            if (mainIndex != -1) {
              widget.images[mainIndex] = File(newPath);
            }

            final tempIndex = _tempUploadedImages.indexWhere((f) => f.path == path);
            if (tempIndex != -1) {
              _tempUploadedImages[tempIndex] = File(newPath);
            }
          });
          successCount++;
        }
      } catch (e) {
        debugPrint("Error tagging $path: $e");
      }
    }

    widget.onDataChanged?.call();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Updated $successCount images to $targetClass")),
      );
    }
  }

  // --- OPTIMIZED BATCH PROCESSOR ---
  Future<void> _processBatchBackground(
      List<XFile> files, String targetClass, Map<String, dynamic> history) async {

    List<Map<String, dynamic>> recordsToSave = [];
    final appDir = await getApplicationDocumentsDirectory();
    final projectDir = Directory('${appDir.path}/projects/${widget.projectName}/images');
    if (!await projectDir.exists()) await projectDir.create(recursive: true);

    int globalCounter = await MetadataService.getLatestIndex(
        projectDir, widget.projectName, targetClass, projectType: widget.projectType
    );

    String cleanProject = widget.projectName.replaceAll(RegExp(r'[^\w\s]+'), '').replaceAll(' ', '_');
    String cleanClass = targetClass.replaceAll(RegExp(r'[^\w\s]+'), '').replaceAll(' ', '_');
    if (cleanClass.isEmpty && widget.projectType == 'classification') cleanClass = "Unclassified";

    for (int i = 0; i < files.length; i++) {
      if (!mounted) break;

      globalCounter++;
      String nextName = widget.projectType == 'segmentation'
          ? "${cleanProject}_$globalCounter.png"
          : "${cleanProject}_${cleanClass}_$globalCounter.png";

      String finalPath = '${projectDir.path}/$nextName';

      if (widget.projectType == 'segmentation') {
        try {
          final String baseImageName = p.basenameWithoutExtension(nextName);
          final Directory annotationDir = Directory('${appDir.path}/projects/${widget.projectName}/annotation');

          if (await annotationDir.exists()) {
            final List<FileSystemEntity> existingAnnos = annotationDir.listSync();
            for (var entity in existingAnnos) {
              if (entity is File && p.basename(entity.path).startsWith(baseImageName)) {
                await entity.delete();
              }
            }
          }
        } catch (e) {
          debugPrint("Error clearing orphaned annotations: $e");
        }
      }

      try {
        // A. Read Metadata (Using Helper)
        Map<String, Object>? metadata = await ImageMetadata.readMetadata(files[i].path);

        // B. Heavy Processing (Using Worker)
        final request = ImageWorkerRequest(
            files[i].path,
            finalPath,
            640,
            0
        );
        final bool success = await compute(backgroundSquarePad, request);

        if (success) {
          // C. Restore Metadata (Using Helper)
          if (metadata != null) await ImageMetadata.writeMetadata(finalPath, metadata);

          recordsToSave.add({
            'path': finalPath,
            'lat': metadata?['lat'],
            'lng': metadata?['lng'],
            'time': metadata?['DateTimeOriginal'],
          });

          history[nextName] = {'originalName': files[i].name, 'size': await files[i].length()};
          _tempUploadedImages.add(File(finalPath));
          widget.labelMap[nextName] = targetClass;
          _currentUploadCount++;

          if (i % 5 == 0 || i == files.length - 1) {
            if (mounted) setState(() {});
            await Future.delayed(const Duration(milliseconds: 50));
          }
        }
      } catch (e) {
        debugPrint("Error processing $nextName: $e");
      }
    }

    // 2. SAVE TO CSV
    for (var record in recordsToSave) {
      Position? pos;
      if (record['lat'] != null && record['lng'] != null) {
        pos = Position(
          latitude: record['lat'] as double,
          longitude: record['lng'] as double,
          timestamp: DateTime.now(),
          accuracy: 0, altitude: 0, heading: 0, speed: 0, speedAccuracy: 0,
          altitudeAccuracy: 0, headingAccuracy: 0,
        );
      }

      DateTime? photoTime;
      if (record['time'] != null) {
        try {
          String t = record['time'].toString().replaceAll(':', '-');
          photoTime = DateTime.parse("${t.substring(0, 10)} ${t.substring(11)}");
        } catch (_) {}
      }

      await MetadataService.saveToCsv(
        projectName: widget.projectName,
        imagePath: record['path'],
        position: pos,
        className: targetClass,
        projectType: widget.projectType,
        customTime: photoTime,
      );
    }

    await ImageMetadata.saveUploadHistory(widget.projectName, history);

    if (mounted) {
      setState(() { _isUploading = false; _tempUploadedImages.clear();});
      widget.onDataChanged?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Imported $_currentUploadCount images.")),
      );
    }
  }

  // --- IMPORT ACTIONS ---
  void _showUploadOptions() {
    if (_isUploading) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (BuildContext ctx) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library, color: Colors.blue),
                title: const Text('Select Images'),
                subtitle: const Text('Pick from Gallery'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickFromGallery();
                },
              ),
              ListTile(
                leading: const Icon(Icons.folder, color: Colors.amber),
                title: const Text('Select Folder'),
                subtitle: const Text('Import all images from a folder'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickFromFolder();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickFromGallery() async {
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;

      if (androidInfo.version.sdkInt >= 33) {
        // Android 13+ uses .photos
        if (await Permission.photos.request().isDenied) return;
      } else {
        // Android 12 and below uses .storage
        if (await Permission.storage.request().isDenied) return;
      }
    }
    final ImagePicker picker = ImagePicker();
    final List<XFile> pickedFiles = await picker.pickMultiImage();
    if (pickedFiles.isNotEmpty) {
      await _processImportSequence(pickedFiles);
    }
  }

  Future<void> _pickFromFolder() async {
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
    if (selectedDirectory == null) return;
    final dir = Directory(selectedDirectory);
    List<XFile> folderImages = [];
    try {
      final List<FileSystemEntity> entities = dir.listSync(recursive: false);
      for (var entity in entities) {
        if (entity is File) {
          final String path = entity.path.toLowerCase();
          if (path.endsWith('.jpg') || path.endsWith('.jpeg') ||
              path.endsWith('.png') || path.endsWith('.webp')) {
            folderImages.add(XFile(entity.path));
          }
        }
      }
    } catch (e) {
      debugPrint("Directory access error: $e");
      return;
    }
    if (folderImages.isNotEmpty) {
      await _processImportSequence(folderImages);
    }
  }

  Future<void> _processImportSequence(List<XFile> pickedFiles) async {
    // Using Helper
    Map<String, dynamic> history = await ImageMetadata.loadUploadHistory(widget.projectName);
    List<XFile> filesToProcess = [];
    List<String> duplicateNames = [];

    for (var file in pickedFiles) {
      int fileSize = await file.length();
      String fileNameOnly = file.path.split(Platform.pathSeparator).last;
      bool isDuplicate = false;

      for (var entry in history.values) {
        if (entry is Map) {
          if (entry['originalName'] == fileNameOnly && entry['size'] == fileSize) {
            isDuplicate = true;
            break;
          }
        }
      }

      if (isDuplicate) {
        duplicateNames.add(fileNameOnly);
      } else {
        filesToProcess.add(file);
      }
    }

    if (!mounted) return;

    if (duplicateNames.isNotEmpty) {
      bool? uploadDuplicates = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text("Duplicate Files Detected"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("${duplicateNames.length} image(s) from this folder are already in the project."),
              const SizedBox(height: 10),
              Container(
                constraints: const BoxConstraints(maxHeight: 120),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(8),
                  children: duplicateNames.map((n) => Text("• $n", style: const TextStyle(fontSize: 11))).toList(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text("Skip Duplicates"),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text("Upload Anyway"),
            ),
          ],
        ),
      );

      if (uploadDuplicates == true) {
        for (var name in duplicateNames) {
          final originalFile = pickedFiles.firstWhere((f) => f.path.endsWith(name));
          filesToProcess.add(originalFile);
        }
      }
    }

    if (filesToProcess.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No new images to upload.")));
      return;
    }
    if (!mounted) return;

    String targetClass = "Unclassified";
    if (widget.projectType == 'classification') {
      // Using Helper
      String? selected = await ClassPickerDialog.show(
          context: context,
          projectName: widget.projectName,
          onClassesUpdated: widget.onClassesUpdated
      );
      if (selected == null) return;
      targetClass = selected;
    } else if (_filterClass != "All") {
      targetClass = _filterClass;
    }

    setState(() {
      _isUploading = true;
      _totalUploads = filesToProcess.length;
      _currentUploadCount = 0;
    });

    _processBatchBackground(filesToProcess, targetClass, history);
  }

  // --- BUILD UI ---
  List<Widget> _buildGroupedSlivers(List<File> imagesToDisplay) {
    final Set<String> uniqueClasses = imagesToDisplay.map((file) {
      final filename = file.path.split(Platform.pathSeparator).last;
      return widget.labelMap[filename] ?? "Unclassified";
    }).toSet();

    final sortedClasses = uniqueClasses.toList()..sort();
    List<Widget> slivers = [];

    for (var className in sortedClasses) {
      final classImages = imagesToDisplay.where((file) {
        final filename = file.path.split(Platform.pathSeparator).last;
        return (widget.labelMap[filename] ?? "Unclassified") == className;
      }).toList();

      final classDef = widget.projectClasses.firstWhere(
            (c) => c['name'] == className,
        orElse: () => {'color': Colors.grey.toARGB32()},
      );
      Color headerColor = Color(classDef['color']);

      final gridData = classImages.map((file) {
        final filename = file.path.split(Platform.pathSeparator).last;
        return {
          "path": file.path,
          "label": widget.labelMap[filename],
        };
      }).toList();

      final bool isExpanded = !_collapsedClasses.contains(className);

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
                border: Border(bottom: BorderSide(color: headerColor, width: 2)),
              ),
              child: Row(
                children: [
                  CircleAvatar(radius: 6, backgroundColor: headerColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text("$className (${classImages.length})",
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Icon(isExpanded ? Icons.expand_less : Icons.expand_more, color: Colors.grey),
                ],
              ),
            ),
          ),
        ),
      );

      if (isExpanded) {
        slivers.add(
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            sliver: SliverImageGrid(
              columns: 3,
              dataList: gridData,
              projectName: widget.projectName,
              onBack: () { setState(() {}); widget.onDataChanged?.call(); },
              projectClasses: widget.projectClasses,
              projectType: widget.projectType,
              onAnnotate: widget.onAnnotate,
              selectedPaths: _selectedPaths,
              onSelectionChanged: _toggleSelection,
            ),
          ),
        );
      }
    }
    slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 80)));
    return slivers;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isLoading) return const Center(child: CircularProgressIndicator());

    List<File> allImages = [...widget.images, ..._tempUploadedImages]
        .where((file) => file.existsSync())
        .toList();
    List<File> filteredImages = allImages;
    if (_filterClass != "All") {
      filteredImages = allImages.where((file) {
        final filename = file.path.split(Platform.pathSeparator).last;
        return (widget.labelMap[filename] ?? "Unclassified") == _filterClass;
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
        body: Column(
          children: [
            if (_isSelectionMode)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  border: Border(bottom: BorderSide(color: Colors.blue.withValues(alpha: 0.2))),
                ),
                child: SafeArea(
                  top: false, bottom: false,
                  child: Row(
                    children: [
                      IconButton(icon: const Icon(Icons.close), onPressed: _clearSelection),
                      const SizedBox(width: 8),
                      Text("${_selectedPaths.length} Selected", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const Spacer(),
                      IconButton(icon: const Icon(Icons.select_all), onPressed: () => _selectAll(filteredImages)),
                      if (widget.projectType == 'classification')
                        IconButton(icon: const Icon(Icons.label), onPressed: _tagSelectedImages),
                      IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: _deleteSelectedImages),
                    ],
                  ),
                ),
              ),

            if (_isUploading)
              LinearProgressIndicator(value: _totalUploads > 0 ? _currentUploadCount / _totalUploads : 0),

            Expanded(
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
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
                                  Text(_isUploading ? "Uploading $_currentUploadCount / $_totalUploads..." : "${filteredImages.length} Images", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[600])),
                                  Row(
                                    children: [
                                      Text("Group by Class", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey[600])),
                                      Switch(value: _groupByClass, onChanged: (val) => setState(() => _groupByClass = val)),
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
                              onClassSelected: (newClass) => setState(() => _filterClass = newClass),
                            ),
                          ] else ...[
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text("${filteredImages.length} Images", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[600])),
                                  if (_isUploading) Text("Processing...", style: const TextStyle(fontSize: 12, color: Colors.green)),
                                ],
                              ),
                            ),
                          ]
                        ],
                      ),
                    ),
                  ),

                  if (filteredImages.isEmpty && !_isUploading)
                    const SliverFillRemaining(child: Center(child: Text("No images found")))
                  else if (_groupByClass && widget.projectType == 'classification')
                    ..._buildGroupedSlivers(filteredImages)
                  else
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      sliver: SliverImageGrid(
                        columns: 3,
                        dataList: flatGridData,
                        projectName: widget.projectName,
                        onBack: () { setState(() {}); widget.onDataChanged?.call(); },
                        projectClasses: widget.projectClasses,
                        projectType: widget.projectType,
                        onAnnotate: widget.onAnnotate,
                        selectedPaths: _selectedPaths,
                        onSelectionChanged: _toggleSelection,
                      ),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 80)),
                ],
              ),
            ),
          ],
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
        floatingActionButton: _isSelectionMode
            ? null
            : FloatingActionButton.extended(
          heroTag: 'fab_images',
          onPressed: _showUploadOptions,
          backgroundColor: Colors.transparent,
          elevation: 0,
          highlightElevation: 0,
          extendedPadding: EdgeInsets.zero,
          focusElevation: 0,
          hoverElevation: 0,
          splashColor: Colors.transparent,
          label: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              gradient: const LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Color(0xFFAED581),
                  Color(0xFF9CCC65),
                  Color(0xFF9CCC65),
                  Color(0xFF8BC34A),
                  Color(0xFF8BC34A),
                  Color(0xFF7CB342),
                  Color(0xFF689F38),
                ],
              ),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
              constraints: const BoxConstraints(minHeight: 48),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _isUploading
                      ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                      : const Icon(Icons.add_a_photo_outlined, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    _isUploading ? "Uploading..." : "Upload",
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
        )
    );
  }
}