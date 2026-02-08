import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:native_exif/native_exif.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:geovision/components/class_selector_dropdown.dart';
import '../../components/class_creator.dart';
import '../../components/image_grid.dart';
import '../../functions/camera/image_processor.dart';
import '../../functions/metadata_handle.dart';

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
        // This service call handles the GeoJSON removal internally
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

  // --- BULK ACTIONS ---

  Future<void> _tagSelectedImages() async {
    // 1. Get user input first
    String? targetClass = await _handleClassSelectionFlow();
    if (targetClass == null) return;

    // 2. Capture the list of files to process
    List<String> pathsToProcess = _selectedPaths.toList();

    // 3. Clear selection immediately so the user can keep working
    _clearSelection();

    // 4. Notify user that work has started
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Moving ${pathsToProcess.length} images to '$targetClass'..."),
          duration: const Duration(seconds: 2),
        ),
      );
    }

    // 5. Start the heavy lifting in a separate async method (fire-and-forget)
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

  // --- HISTORY MANAGEMENT ---

  Future<File> _getHistoryFile() async {
    final appDir = await getApplicationDocumentsDirectory();
    final historyFile = File('${appDir.path}/projects/${widget.projectName}/upload_history.json');
    if (!await historyFile.exists()) {
      await historyFile.create(recursive: true);
      await historyFile.writeAsString(jsonEncode({}));
    }
    return historyFile;
  }

  Future<Map<String, dynamic>> _loadUploadHistory() async {
    try {
      final file = await _getHistoryFile();
      final String content = await file.readAsString();
      final dynamic decoded = jsonDecode(content);

      if (decoded is List) return {};

      // Backward compatibility logic
      Map<String, dynamic> result = {};
      decoded.forEach((key, value) {
        if (value is String) {
          result[key] = {'originalName': value, 'size': -1};
        } else {
          result[key] = value;
        }
      });
      return result;
    } catch (e) {
      return {};
    }
  }

  Future<void> _saveUploadHistory(Map<String, dynamic> history) async {
    try {
      final file = await _getHistoryFile();
      await file.writeAsString(jsonEncode(history));
    } catch (e) {
      debugPrint("Error saving history: $e");
    }
  }

  // --- DROPDOWN ---
  Future<String?> _handleClassSelectionFlow() async {
    String currentSelection = "Unclassified";
    final LayerLink layerLink = LayerLink();

    while (true) {
      List<dynamic> classes = await MetadataService.getClasses(widget.projectName);
      if (!classes.any((c) => c['name'] == "Unclassified")) {
        classes.insert(0, {'name': 'Unclassified', 'color': Colors.grey.toARGB32()});
      }
      if (!mounted) return null;

      final String? result = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          OverlayEntry? dropdownOverlay;
          bool isDropdownOpen = false;

          void closeDropdown() {
            dropdownOverlay?.remove();
            dropdownOverlay = null;
            isDropdownOpen = false;
          }

          return StatefulBuilder(
            builder: (context, setStateDialog) {
              void toggleDropdown() {
                if (isDropdownOpen) {
                  closeDropdown();
                  setStateDialog(() {});
                  return;
                }
                dropdownOverlay = OverlayEntry(
                  builder: (context) {
                    return Stack(
                      children: [
                        Positioned.fill(
                          child: GestureDetector(
                            onTap: () {
                              closeDropdown();
                              setStateDialog(() {});
                            },
                            behavior: HitTestBehavior.translucent,
                            child: Container(color: Colors.transparent),
                          ),
                        ),
                        Positioned(
                          width: 200,
                          child: CompositedTransformFollower(
                            link: layerLink,
                            showWhenUnlinked: false,
                            offset: const Offset(0, 50),
                            child: Material(
                              elevation: 4,
                              borderRadius: BorderRadius.circular(8),
                              color: Colors.white,
                              child: Container(
                                constraints: const BoxConstraints(maxHeight: 250),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.grey.shade300),
                                ),
                                child: ListView(
                                  padding: EdgeInsets.zero,
                                  shrinkWrap: true,
                                  children: classes.where((c) => c['name'] != currentSelection).map((c) {
                                    return ListTile(
                                      dense: true,
                                      leading: CircleAvatar(backgroundColor: Color(c['color']), radius: 6),
                                      title: Text(c['name']),
                                      onTap: () {
                                        setStateDialog(() { currentSelection = c['name']; });
                                        closeDropdown();
                                      },
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                );
                Overlay.of(context).insert(dropdownOverlay!);
                isDropdownOpen = true;
                setStateDialog(() {});
              }
              final selectedClassData = classes.firstWhere((c) => c['name'] == currentSelection, orElse: () => {'color': Colors.grey.toARGB32()});
              Color selectedColor = Color(selectedClassData['color']);

              return PopScope(
                onPopInvokedWithResult: (_, _) => closeDropdown(),
                child: AlertDialog(
                  title: const Text("Assign Class"),
                  contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: CompositedTransformTarget(
                              link: layerLink,
                              child: InkWell(
                                onTap: toggleDropdown,
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  height: 48,
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(8)),
                                  child: Row(
                                    children: [
                                      CircleAvatar(backgroundColor: selectedColor, radius: 6),
                                      const SizedBox(width: 10),
                                      Expanded(child: Text(currentSelection, overflow: TextOverflow.ellipsis)),
                                      Icon(isDropdownOpen ? Icons.arrow_drop_up : Icons.arrow_drop_down, color: Colors.grey.shade700),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            height: 48, width: 48,
                            decoration: BoxDecoration(color: Colors.blue.withValues(alpha:0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue.withValues(alpha:0.3))),
                            child: IconButton(
                              icon: const Icon(Icons.add, color: Colors.blue),
                              onPressed: () {
                                closeDropdown();
                                Navigator.pop(dialogContext, "CREATE_NEW");
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                  actions: [
                    TextButton(onPressed: () { closeDropdown(); Navigator.pop(dialogContext, null); }, child: const Text("Cancel")),
                    FilledButton(onPressed: () { closeDropdown(); Navigator.pop(dialogContext, currentSelection); }, child: const Text("Select")),
                  ],
                ),
              );
            },
          );
        },
      );

      if (result == "CREATE_NEW") {
        if (!mounted) return null;
        await Navigator.push(context, MaterialPageRoute(builder: (context) => CreateClassPage(projectName: widget.projectName)));
        widget.onClassesUpdated?.call();
      } else {
        return result;
      }
    }
  }

  Future<void> _processBatchBackground(
      List<XFile> files, String targetClass, Map<String, dynamic> history) async {
    try {
      List<String> skippedFiles = [];
      final appDir = await getApplicationDocumentsDirectory();
      final projectDir = Directory('${appDir.path}/projects/${widget.projectName}/images');
      if (!await projectDir.exists()) await projectDir.create(recursive: true);

      // Get snapshot of disk + memory tracker
      final entities = await projectDir.list().toList();
      final Set<String> sessionNames = entities
          .whereType<File>()
          .map((e) => e.path.split(Platform.pathSeparator).last)
          .toSet();

      for (int i = 0; i < files.length; i++) {
        final file = files[i];
        int originalSize = await file.length();

        // Reserve Name
        String nextName = await MetadataService.generateNextFileName(
          projectDir,
          widget.projectName,
          targetClass,
          projectType: widget.projectType,
          existingNames: sessionNames,
        );
        sessionNames.add(nextName);

        try {
          String? newPath = await _processSingleImport(
              file,
              targetClass,
              forcedFileName: nextName
          );

          if (newPath == null) {
            skippedFiles.add(file.name);
            sessionNames.remove(nextName);
            continue;
          }

          history[nextName] = {
            'originalName': file.name,
            'size': originalSize
          };

          if (mounted) {
            setState(() {
              _currentUploadCount++;
              // We keep these in temp list to show them immediately
              _tempUploadedImages.add(File(newPath));
              widget.labelMap[nextName] = targetClass;
            });
          }
        } catch (e) {
          debugPrint("Upload error: $e");
        }
      }

      // 1. Save history to disk
      await _saveUploadHistory(history);

      if (mounted) {
        // 2. Hide loading state
        setState(() {
          _isUploading = false;
        });

        // 3. Trigger the parent refresh
        // This usually triggers the 'FutureBuilder' or 'init' logic in your main screen
        widget.onDataChanged?.call();

        // 4. Clear the temporary list after a short delay
        // This prevents the images from flickering out and back in
        // while the parent is reloading the actual file list
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            setState(() {
              _tempUploadedImages.clear();
            });
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Imported $_currentUploadCount images. Page refreshed.")),
        );

        if (skippedFiles.isNotEmpty) {
          _showSkippedFilesDialog(skippedFiles);
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<String?> _processSingleImport(
      XFile file,
      String targetClass,
      {required String forcedFileName}
      ) async {
    final appDir = await getApplicationDocumentsDirectory();
    final projectDir = Directory('${appDir.path}/projects/${widget.projectName}/images');
    final String newPath = '${projectDir.path}/$forcedFileName';

    try {
      // 1. EXTRACT METADATA
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
              accuracy: 0, altitude: 0, heading: 0, speed: 0,
              speedAccuracy: 0, altitudeAccuracy: 0, headingAccuracy: 0
          );
        }
      } catch (e) {
        debugPrint("Metadata extraction error: $e");
      }

      // 2. Copy and Process Image
      await File(file.path).copy(newPath);
      String? processedPath = await padToSquare(newPath);
      if (processedPath == null) return null;

      await FileImage(File(processedPath)).evict();

      // 3. EMBED METADATA
      await MetadataService.embedMetadata(
        filePath: processedPath,
        lat: importedPosition?.latitude ?? 0.0,
        lng: importedPosition?.longitude ?? 0.0,
        className: targetClass,
        time: DateTime.now(),
      );

      // 4. SAVE TO DATABASE (Now writes to GeoJSON)
      await MetadataService.saveToCsv(
        projectName: widget.projectName,
        imagePath: processedPath,
        position: importedPosition,
        className: targetClass,
        projectType: widget.projectType,
      );

      return processedPath;
    } catch (e) {
      debugPrint("Failed processing $forcedFileName: $e");
      return null;
    }
  }

  void _showSkippedFilesDialog(List<String> fileNames) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Files Skipped"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "The following images were too small (<200px) and were not uploaded:",
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 10),
            Container(
              height: 150,
              width: double.maxFinite,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(4),
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: fileNames.length,
                itemBuilder: (context, index) {
                  return ListTile(
                    dense: true,
                    title: Text(
                      fileNames[index],
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    leading: const Icon(Icons.warning, color: Colors.orange, size: 16),
                  );
                },
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
        ],
      ),
    );
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

  // --- IMPORT ACTIONS ---

  // 1. The Trigger (Menu)
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

  // 2. Pick from Gallery (Original Method)
  Future<void> _pickFromGallery() async {
    if (Platform.isAndroid) {
      // Check specific permissions based on Android version if needed
      // Usually photos or storage
      if (await Permission.photos.request().isDenied &&
          await Permission.storage.request().isDenied) {
        return;
      }
    }

    final ImagePicker picker = ImagePicker();
    final List<XFile> pickedFiles = await picker.pickMultiImage();

    if (pickedFiles.isNotEmpty) {
      await _processImportSequence(pickedFiles);
    }
  }

  // 3. Pick from Folder (New Method)
  Future<void> _pickFromFolder() async {
    // 1. Pick the directory
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();

    if (selectedDirectory == null) return;

    final dir = Directory(selectedDirectory);
    List<XFile> folderImages = [];

    try {
      // 2. listSync can fail if permissions aren't perfect.
      // It's safer to use an async list and catch errors per file.
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
      // If this fails, it's usually an Android Permission issue (Scoped Storage)
      return;
    }

    if (folderImages.isNotEmpty) {
      // 3. Hand off to the FIXED sequence logic
      await _processImportSequence(folderImages);
    }
  }

  // 4. Shared Processing Logic (Refactored from old _importImage)
  Future<void> _processImportSequence(List<XFile> pickedFiles) async {
    Map<String, dynamic> history = await _loadUploadHistory();
    List<XFile> filesToProcess = [];
    List<String> duplicateNames = [];

    for (var file in pickedFiles) {
      int fileSize = await file.length();
      // Use the actual filename from the path
      String fileNameOnly = file.path.split(Platform.pathSeparator).last;
      bool isDuplicate = false;

      for (var entry in history.values) {
        if (entry is Map) {
          // This will now match because both are 'original' sizes
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
      // Show dialog
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
              const Text("Upload them again as new copies?", style: TextStyle(fontSize: 12, color: Colors.grey)),
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
        // Add only the duplicates that were caught back into the list
        for (var name in duplicateNames) {
          final originalFile = pickedFiles.firstWhere((f) => f.path.endsWith(name));
          filesToProcess.add(originalFile);
        }
      }
    }

    if (filesToProcess.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No new images to upload.")),
      );
      return;
    }

    // RE-VERIFY mounting before showing class selector
    if (!mounted) return;

    String targetClass = "Unclassified";
    if (widget.projectType == 'classification') {
      String? selected = await _handleClassSelectionFlow();
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

  @override
  Widget build(BuildContext context) {
    if (widget.isLoading) return const Center(child: CircularProgressIndicator());

    List<File> allImages = [...widget.images, ..._tempUploadedImages];
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