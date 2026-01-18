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
import '../../functions/metadata_handle.dart';
import '../../functions/camera/image_processor.dart';

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
        content: Text("Are you sure you want to delete $count image(s)? This cannot be undone."),
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

    // 1. Load Upload History (to remove duplicates)
    Map<String, dynamic> history = await _loadUploadHistory();
    bool historyChanged = false;

    List<String> pathsToDelete = _selectedPaths.toList();

    for (String path in pathsToDelete) {
      try {
        // --- KEY CHANGE: Use MetadataService.deleteImage ---
        // This ensures the CSV entry is removed exactly like in ImageView
        await MetadataService.deleteImage(
          projectName: widget.projectName,
          imagePath: path,
          projectType: widget.projectType,
        );

        final filename = path.split(Platform.pathSeparator).last;

        // Update Local UI State
        widget.labelMap.remove(filename);
        _tempUploadedImages.removeWhere((f) => f.path == path);

        // Update Upload History (Remove the key)
        if (history.containsKey(filename)) {
          history.remove(filename);
          historyChanged = true;
        }

      } catch (e) {
        debugPrint("Error deleting $path: $e");
      }
    }

    // 2. Save History changes back to disk
    if (historyChanged) {
      await _saveUploadHistory(history);
    }

    // 3. Update Parent Widget List
    widget.images.removeWhere((f) => pathsToDelete.contains(f.path));

    _clearSelection();
    widget.onDataChanged?.call();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$count images deleted")));
    }
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
    Map<String, dynamic> history = await _loadUploadHistory();
    bool historyChanged = false;
    int successCount = 0;

    for (String path in paths) {
      if (!mounted) return;

      try {
        String oldFilename = path.split(Platform.pathSeparator).last;

        // 1. Move the file
        String? newPath = await MetadataService.tagImage(
          widget.projectName,
          path,
          targetClass,
          projectType: widget.projectType,
        );

        if (newPath != null) {
          // --- ADDED FIX: EVICT CACHE ---
          // Evict the old path so it doesn't linger
          await FileImage(File(path)).evict();
          // Evict the new path to ensure we aren't showing a stale cached version
          // from a previously deleted file of the same name
          await FileImage(File(newPath)).evict();

          // Also evict the resized version if you are using cacheWidth anywhere else
          await ResizeImage(FileImage(File(path)), width: 300).evict();
          await ResizeImage(FileImage(File(newPath)), width: 300).evict();
          // ------------------------------

          String newFilename = newPath.split(Platform.pathSeparator).last;

          // 2. Update History
          if (oldFilename != newFilename && history.containsKey(oldFilename)) {
            final entryData = history[oldFilename];
            history.remove(oldFilename);
            history[newFilename] = entryData;
            historyChanged = true;
          }

          // 3. Update State & REPLACE the File object
          setState(() {
            // ... existing logic ...
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

    if (historyChanged) {
      await _saveUploadHistory(history);
    }

    widget.onDataChanged?.call();

    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Finished moving $successCount images to $targetClass")),
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
        classes.insert(0, {'name': 'Unclassified', 'color': Colors.grey.value});
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
              final selectedClassData = classes.firstWhere((c) => c['name'] == currentSelection, orElse: () => {'color': Colors.grey.value});
              Color selectedColor = Color(selectedClassData['color']);

              return PopScope(
                onPopInvokedWithResult: (_, __) => closeDropdown(),
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
                            decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue.withOpacity(0.3))),
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

  // --- IMPORT LOGIC ---

  Future<void> _importImage() async {
    if (_isUploading) return;
    if (Platform.isAndroid) {
      if (await Permission.photos.request().isDenied) return;
    }

    final ImagePicker picker = ImagePicker();
    final List<XFile> pickedFiles = await picker.pickMultiImage();
    if (pickedFiles.isEmpty) return;

    // Load History
    Map<String, dynamic> history = await _loadUploadHistory();
    List<XFile> filesToProcess = [];
    List<String> duplicateNames = [];

    // --- SMART DUPLICATE CHECK ---
    for (var file in pickedFiles) {
      int fileSize = await file.length();
      bool isDuplicate = false;

      for (var entry in history.values) {
        if (entry is Map) {
          if (entry['originalName'] == file.name && entry['size'] == fileSize) {
            isDuplicate = true;
            break;
          }
        } else if (entry is String) {
          if (entry == file.name) {
            isDuplicate = true;
            break;
          }
        }
      }

      if (isDuplicate) {
        duplicateNames.add(file.name);
      } else {
        filesToProcess.add(file);
      }
    }

    if (duplicateNames.isNotEmpty && mounted) {
      bool? uploadDuplicates = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text("Duplicate Files Detected"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("${duplicateNames.length} image(s) match existing files (Same Name & Size)."),
                const SizedBox(height: 10),
                Container(
                  constraints: const BoxConstraints(maxHeight: 150),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(5)),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: duplicateNames.length,
                    itemBuilder: (context, index) => Text(duplicateNames[index], style: const TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(height: 15),
                const Text("Upload them anyway?", style: TextStyle(color: Colors.black54)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Skip Duplicates"),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Upload Anyway"),
            ),
          ],
        ),
      );

      if (uploadDuplicates == true) {
        final duplicatesToUpload = pickedFiles.where((f) => duplicateNames.contains(f.name));
        filesToProcess.addAll(duplicatesToUpload);
      }
    }

    if (filesToProcess.isEmpty) return;

    String targetClass = "Unclassified";
    if (widget.projectType == 'classification') {
      String? selected = await _handleClassSelectionFlow();
      if (selected == null) return;
      targetClass = selected;
    } else {
      if (_filterClass != "All") targetClass = _filterClass;
    }

    setState(() {
      _isUploading = true;
      _totalUploads = filesToProcess.length;
      _currentUploadCount = 0;
      _tempUploadedImages.clear();
    });

    _processBatchBackground(filesToProcess, targetClass, history);
  }

  Future<void> _processBatchBackground(
      List<XFile> files, String targetClass, Map<String, dynamic> history) async {
    try {
      for (final file in files) {
        try {
          int size = await file.length();
          String newPath = await _processSingleImport(file, targetClass);
          String newFilename = newPath.split(Platform.pathSeparator).last;

          history[newFilename] = {
            'originalName': file.name,
            'size': size
          };

          if (mounted) {
            setState(() {
              _currentUploadCount++;
              _tempUploadedImages.add(File(newPath));
              widget.labelMap[newFilename] = targetClass;
            });
          }
        } catch (e) {
          debugPrint("Failed to import ${file.name}: $e");
        }
      }

      await _saveUploadHistory(history);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Imported $_currentUploadCount images")),
        );
        widget.onDataChanged?.call();
        setState(() { _isUploading = false; _tempUploadedImages.clear(); });
      }
    } catch (e) {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<String> _processSingleImport(XFile file, String targetClass) async {
    final appDir = await getApplicationDocumentsDirectory();
    final projectDir = Directory('${appDir.path}/projects/${widget.projectName}/images');
    if (!await projectDir.exists()) await projectDir.create(recursive: true);
    final String fileName = await MetadataService.generateNextFileName(
        projectDir, widget.projectName, targetClass, projectType: widget.projectType
    );
    final String newPath = '${projectDir.path}/$fileName';
    await File(file.path).copy(newPath);

    await FileImage(File(newPath)).evict();
    await ResizeImage(FileImage(File(newPath)), width: 300).evict();

    Position? importedPosition;
    try {
      final exif = await Exif.fromPath(file.path);
      final latLong = await exif.getLatLong();
      await exif.close();
      if(latLong != null) {
        importedPosition = Position(
            latitude: latLong.latitude, longitude: latLong.longitude, timestamp: DateTime.now(),
            accuracy: 0, altitude: 0, heading: 0, speed: 0, speedAccuracy: 0, altitudeAccuracy: 0, headingAccuracy: 0
        );
      }
    } catch (_) {}

    await MetadataService.embedMetadata(
      filePath: newPath, lat: importedPosition?.latitude ?? 0.0, lng: importedPosition?.longitude ?? 0.0, className: targetClass,
    );
    await MetadataService.saveToCsv(
      projectName: widget.projectName, imagePath: newPath, position: importedPosition, className: targetClass, projectType: widget.projectType,
    );
    return newPath;
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
                if (isExpanded) _collapsedClasses.add(className);
                else _collapsedClasses.remove(className);
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
          await Permission.storage.request().isDenied) return;
    }

    final ImagePicker picker = ImagePicker();
    final List<XFile> pickedFiles = await picker.pickMultiImage();

    if (pickedFiles.isNotEmpty) {
      await _processImportSequence(pickedFiles);
    }
  }

  // 3. Pick from Folder (New Method)
  Future<void> _pickFromFolder() async {
    // Check storage permission for reading folder contents
    if (await Permission.storage.request().isDenied &&
        await Permission.manageExternalStorage.request().isDenied) {
      // Fallback or show alert if needed
    }

    // Pick Directory
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();

    if (selectedDirectory != null) {
      final dir = Directory(selectedDirectory);
      List<XFile> folderImages = [];

      try {
        // List files and filter for images
        final List<FileSystemEntity> entities = dir.listSync(recursive: false);

        for (var entity in entities) {
          if (entity is File) {
            final String ext = entity.path.split('.').last.toLowerCase();
            if (['jpg', 'jpeg', 'png', 'heic', 'webp'].contains(ext)) {
              // Convert File to XFile for compatibility
              folderImages.add(XFile(entity.path));
            }
          }
        }
      } catch (e) {
        debugPrint("Error reading folder: $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Error reading folder: $e"))
          );
        }
        return;
      }

      if (folderImages.isNotEmpty) {
        // Confirm count before proceeding if it's a huge folder
        bool confirm = true;
        if (folderImages.length > 50 && mounted) {
          confirm = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text("Large Import"),
                content: Text("Found ${folderImages.length} images. Proceed?"),
                actions: [
                  TextButton(onPressed: ()=>Navigator.pop(ctx, false), child: const Text("Cancel")),
                  FilledButton(onPressed: ()=>Navigator.pop(ctx, true), child: const Text("Import")),
                ],
              )
          ) ?? false;
        }

        if (confirm) {
          await _processImportSequence(folderImages);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("No valid images found in selected folder."))
          );
        }
      }
    }
  }

  // 4. Shared Processing Logic (Refactored from old _importImage)
  Future<void> _processImportSequence(List<XFile> pickedFiles) async {
    // Load History
    Map<String, dynamic> history = await _loadUploadHistory();
    List<XFile> filesToProcess = [];
    List<String> duplicateNames = [];

    // --- SMART DUPLICATE CHECK ---
    for (var file in pickedFiles) {
      int fileSize = await file.length();
      bool isDuplicate = false;

      for (var entry in history.values) {
        if (entry is Map) {
          if (entry['originalName'] == file.name && entry['size'] == fileSize) {
            isDuplicate = true;
            break;
          }
        } else if (entry is String) {
          // Backward compatibility check
          if (entry == file.name) {
            isDuplicate = true;
            break;
          }
        }
      }

      if (isDuplicate) {
        duplicateNames.add(file.name);
      } else {
        filesToProcess.add(file);
      }
    }

    // Handle Duplicates Dialog
    if (duplicateNames.isNotEmpty && mounted) {
      bool? uploadDuplicates = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text("Duplicate Files Detected"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("${duplicateNames.length} image(s) match existing files (Same Name & Size)."),
                const SizedBox(height: 10),
                Container(
                  constraints: const BoxConstraints(maxHeight: 150),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(5)),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: duplicateNames.length,
                    itemBuilder: (context, index) => Text(duplicateNames[index], style: const TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(height: 15),
                const Text("Upload them anyway?", style: TextStyle(color: Colors.black54)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Skip Duplicates"),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Upload Anyway"),
            ),
          ],
        ),
      );

      if (uploadDuplicates == true) {
        final duplicatesToUpload = pickedFiles.where((f) => duplicateNames.contains(f.name));
        filesToProcess.addAll(duplicatesToUpload);
      }
    }

    if (filesToProcess.isEmpty) return;

    // Handle Class Selection
    String targetClass = "Unclassified";
    if (widget.projectType == 'classification') {
      String? selected = await _handleClassSelectionFlow();
      if (selected == null) return;
      targetClass = selected;
    } else {
      if (_filterClass != "All") targetClass = _filterClass;
    }

    setState(() {
      _isUploading = true;
      _totalUploads = filesToProcess.length;
      _currentUploadCount = 0;
      _tempUploadedImages.clear();
    });

    // Start background processing
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
                color: Colors.blue.withOpacity(0.1),
                border: Border(bottom: BorderSide(color: Colors.blue.withOpacity(0.2))),
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
      floatingActionButton: _isSelectionMode
          ? null
          : FloatingActionButton.extended(
        heroTag: 'fab_images',
        label: Text(_isUploading ? "Uploading..." : "Upload"),
        icon: _isUploading
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white))
            : const Icon(Icons.add_a_photo_outlined),
        onPressed: _showUploadOptions,
      ),
    );
  }
}