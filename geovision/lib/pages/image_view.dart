import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'dart:convert';
import 'package:path_provider/path_provider.dart';

import '../components/classes/class_creator.dart';
import '../components/image_view/edit_metadata_dialog.dart';
import '../components/image_view/location_decoder.dart';
import '../functions/data_service/metadata_handle.dart';
import '../components/image_view/ellipsis_menu.dart';

class ImageView extends StatefulWidget {
  final List<String> allImagePaths;
  final int initialIndex;
  final String projectName;
  final String projectType;

  final Future<bool?> Function(String path)? onAnnotate;

  const ImageView({
    super.key,
    required this.allImagePaths,
    required this.initialIndex,
    required this.projectName,
    required this.projectType,
    this.onAnnotate,
  });

  @override
  State<ImageView> createState() => _ImageViewState();
}

class _ImageViewState extends State<ImageView> {
  late PageController _pageController;
  late int _currentIndex;
  late List<String> _currentImagePaths;

  // Stores metadata keyed by LOWERCASE filename for safe matching
  Map<String, Map<String, dynamic>> _metadataMap = {};
  Map<String, Color> _classColorMap = {};

  bool _hasChanges = false;
  bool _showAnnotations = true;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _currentImagePaths = List.from(widget.allImagePaths);
    _loadMetadata();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // --- 1. LOAD GEOJSON DATA ---
  Future<void> _loadMetadata() async {
    // NOTE: 'readCsvData' reads your GeoJSON file. The name is just a legacy label.
    final List<Map<String, dynamic>> dataList = await MetadataService.readCsvData(widget.projectName);
    final classDefs = await MetadataService.getClasses(widget.projectName);

    Map<String, Map<String, dynamic>> tempMap = {};
    Map<String, Color> tempColors = {};

    // Build Metadata Map (Key = Lowercase Filename)
    for (var item in dataList) {
      String rawPath = item['path']?.toString() ?? "";
      String filename = p.basename(rawPath).toLowerCase(); // FORCE LOWERCASE
      if (filename.isNotEmpty) {
        tempMap[filename] = item;
      }
    }

    // Build Color Map
    for (var cls in classDefs) {
      int colorInt = cls['color'] ?? 0xFF000000;
      tempColors[cls['name']] = Color(colorInt);
    }

    if (mounted) {
      setState(() {
        _metadataMap = tempMap;
        _classColorMap = tempColors;
      });
    }
  }

  // --- 2. ROBUST LOOKUP ---
  Map<String, dynamic> _getCurrentImageInfo(String fullPath) {
    // We match only the filename, case-insensitive
    final String targetName = p.basename(fullPath).toLowerCase();
    return _metadataMap[targetName] ?? {};
  }

  // --- 3. HELPER FUNCTIONS ---
  Future<void> _removeImageFromHistory(String filename) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final historyFile = File('${appDir.path}/projects/${widget.projectName}/upload_history.json');
      if (await historyFile.exists()) {
        final Map<String, dynamic> historyMap = jsonDecode(await historyFile.readAsString());
        if (historyMap.containsKey(filename)) {
          historyMap.remove(filename);
          await historyFile.writeAsString(jsonEncode(historyMap));
        }
      }
    } catch (e) {
      debugPrint("Error removing history: $e");
    }
  }

  bool _hasAnnotation(String imagePath) {
    if (widget.projectType != 'segmentation') return false;
    try {
      final String fileNameNoExt = p.basenameWithoutExtension(imagePath);
      final parentDir = File(imagePath).parent.parent;
      final String annotationPath = p.join(parentDir.path, 'annotation', '${fileNameNoExt}_data.json');
      final file = File(annotationPath);

      if (!file.existsSync()) return false;
      final List<dynamic> jsonLayers = jsonDecode(file.readAsStringSync());
      return jsonLayers.any((layer) => (layer['strokes'] as List?)?.isNotEmpty ?? false);
    } catch (_) {
      return false;
    }
  }

  List<File> _getAnnotationLayers(String imagePath) {
    if (!widget.projectType.contains('segmentation')) return [];
    try {
      final String fileNameNoExt = p.basenameWithoutExtension(imagePath);
      final parentDir = File(imagePath).parent.parent;
      final String annotationPath = p.join(parentDir.path, 'annotation');
      final Directory annotationDir = Directory(annotationPath);

      if (!annotationDir.existsSync()) return [];

      final List<FileSystemEntity> files = annotationDir.listSync().where((e) {
        return e is File && p.basename(e.path).startsWith("${fileNameNoExt}_") && e.path.endsWith('.png');
      }).toList();

      files.sort((a, b) {
        try {
          String nameA = p.basenameWithoutExtension(a.path);
          String nameB = p.basenameWithoutExtension(b.path);
          return int.parse(nameA.split('_').last).compareTo(int.parse(nameB.split('_').last));
        } catch (_) { return 0; }
      });

      return List<File>.from(files);
    } catch (_) {
      return [];
    }
  }

  // --- 4. DIALOGS ---
  void showImageInformation(BuildContext context, String imagePath) {
    final info = _getCurrentImageInfo(imagePath);
    final String targetFilename = p.basename(imagePath);

    double lat = double.tryParse(info['lat']?.toString() ?? "0") ?? 0.0;
    double lng = double.tryParse(info['lng']?.toString() ?? "0") ?? 0.0;

    DateTime dt = DateTime.now();
    if (info['time'] != null && info['time'].toString().isNotEmpty) {
      try { dt = DateTime.parse(info['time']); } catch (_) {}
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Image Info'),
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.blue),
              onPressed: () {
                Navigator.pop(ctx);
                showDialog(
                    context: context,
                    builder: (ctx2) => EditMetadataDialog(
                      filename: targetFilename,
                      initialLat: lat,
                      initialLng: lng,
                      initialDate: dt,
                      onSave: (newLat, newLng, newDate) async {
                        await MetadataService.updateImageMetadata(
                            projectName: widget.projectName,
                            imagePath: imagePath,
                            lat: newLat,
                            lng: newLng,
                            time: newDate
                        );
                        await _loadMetadata();
                        if (mounted) setState(() => _hasChanges = true);
                      },
                    )
                );
              },
            )
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(targetFilename, style: const TextStyle(fontWeight: FontWeight.bold)),
            const Divider(),
            ListTile(
              dense: true,
              leading: const Icon(Icons.calendar_today, color: Colors.blue),
              title: Text("${dt.year}-${dt.month}-${dt.day} ${dt.hour}:${dt.minute}"),
            ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.location_on, color: Colors.red),
              title: Text("Lat: $lat\nLng: $lng"),
            ),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Close"))],
      ),
    );
  }

  void _showTaggingSheet() async {
    final currentPath = _currentImagePaths[_currentIndex];
    final classes = await MetadataService.getClasses(widget.projectName);

    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        expand: false,
        builder: (_, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(20),
          children: [
            const Text("Assign Class", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
            const SizedBox(height: 15),
            ...classes.map((cls) => ListTile(
              leading: CircleAvatar(backgroundColor: Color(cls['color']), radius: 10),
              title: Text(cls['name']),
              onTap: () async {
                String? newPath = await MetadataService.tagImage(widget.projectName, currentPath, cls['name']);
                if (newPath != null && mounted) {
                  Navigator.pop(context);
                  await FileImage(File(currentPath)).evict();
                  await FileImage(File(newPath)).evict();
                  setState(() {
                    _currentImagePaths[_currentIndex] = newPath;
                    _hasChanges = true;
                  });
                  await _loadMetadata();
                }
              },
            )),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.add, color: Colors.blue),
              title: const Text("Create New Class"),
              onTap: () async {
                Navigator.pop(context);
                await Navigator.push(context, MaterialPageRoute(builder: (_) => CreateClassPage(projectName: widget.projectName)));
                if (mounted) _showTaggingSheet();
              },
            )
          ],
        ),
      ),
    );
  }

  // --- 5. UI BUILD ---
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        Navigator.pop(context, _hasChanges);
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          iconTheme: const IconThemeData(color: Colors.white),
          title: Text("${_currentIndex + 1} of ${_currentImagePaths.length}", style: const TextStyle(color: Colors.white)),
          actions: [
            EllipsisMenu(
              onInfo: () => showImageInformation(context, _currentImagePaths[_currentIndex]),
              onDelete: () async {
                final String currentPath = _currentImagePaths[_currentIndex];
                final String filename = p.basename(currentPath);
                bool confirm = await showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text("Delete?"),
                      content: const Text("Cannot be undone."),
                      actions: [
                        TextButton(onPressed: ()=>Navigator.pop(ctx,false), child: const Text("Cancel")),
                        TextButton(onPressed: ()=>Navigator.pop(ctx,true), child: const Text("Delete", style: TextStyle(color: Colors.red))),
                      ],
                    )
                ) ?? false;

                if (confirm && mounted) {
                  await MetadataService.deleteImage(projectName: widget.projectName, imagePath: currentPath);
                  await _removeImageFromHistory(filename);
                  Navigator.pop(context, true);
                }
              },
            )
          ],
        ),
        body: PageView.builder(
          controller: _pageController,
          itemCount: _currentImagePaths.length,
          onPageChanged: (index) => setState(() => _currentIndex = index),
          itemBuilder: (context, index) {
            final imagePath = _currentImagePaths[index];
            final info = _getCurrentImageInfo(imagePath);
            final bool isAnnotated = _hasAnnotation(imagePath);

            final String className = info['class'] ?? "Unclassified";
            final Color tagColor = _classColorMap[className] ?? Colors.grey;

            // Safe Parsing for GeoJSON
            final double lat = double.tryParse(info['lat']?.toString() ?? "0") ?? 0.0;
            final double lng = double.tryParse(info['lng']?.toString() ?? "0") ?? 0.0;

            String dateString = "--";
            if (info['time'] != null && info['time'].toString().isNotEmpty) {
              try {
                final dt = DateTime.parse(info['time']);
                dateString = "${dt.year}-${dt.month}-${dt.day} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}";
              } catch (_) {}
            }

            final List<File> overlayLayers = (_showAnnotations && isAnnotated) ? _getAnnotationLayers(imagePath) : [];

            return Column(
              children: [
                // METADATA BAR
                Container(
                  color: Colors.black54,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(p.basename(imagePath), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                          if (widget.projectType != 'segmentation')
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(color: tagColor.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(4)),
                              child: Text(className, style: const TextStyle(color: Colors.white, fontSize: 12)),
                            )
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.calendar_today, size: 14, color: Colors.white70),
                          const SizedBox(width: 4),
                          Text(dateString, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                          const SizedBox(width: 16),
                          const Icon(Icons.location_on, size: 14, color: Colors.redAccent),
                          const SizedBox(width: 4),
                          Expanded(
                            child: LocationDisplay(
                              latitude: lat,
                              longitude: lng,
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          ),
                        ],
                      )
                    ],
                  ),
                ),
                // IMAGE
                Expanded(
                  child: Stack(
                    children: [
                      InteractiveViewer(
                        minScale: 1.0, maxScale: 5.0,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.file(File(imagePath), fit: BoxFit.contain),
                            ...overlayLayers.map((f) => Image.file(f, fit: BoxFit.contain, opacity: const AlwaysStoppedAnimation(0.5))),
                          ],
                        ),
                      ),
                      if (isAnnotated)
                        Positioned(
                          top: 10, right: 10,
                          child: InkWell(
                            onTap: () => setState(() => _showAnnotations = !_showAnnotations),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle, border: Border.all(color: _showAnnotations ? Colors.greenAccent : Colors.white)),
                              child: Icon(Icons.brush, color: _showAnnotations ? Colors.greenAccent : Colors.white, size: 20),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
        floatingActionButton: _buildFab(),
      ),
    );
  }

  Widget? _buildFab() {
    final decoration = BoxDecoration(
      borderRadius: BorderRadius.circular(30),
      gradient: const LinearGradient(colors: [Color(0xFFAED581), Color(0xFF689F38)]),
    );

    if (widget.projectType == 'segmentation') {
      return FloatingActionButton.extended(
        backgroundColor: Colors.transparent, elevation: 0,
        onPressed: () async {
          if (widget.onAnnotate != null) {
            bool? res = await widget.onAnnotate!(_currentImagePaths[_currentIndex]);
            if (res == true && mounted) {
              PaintingBinding.instance.imageCache.clear();
              setState(() { _hasChanges = true; _showAnnotations = true; });
            }
          }
        },
        label: Ink(decoration: decoration, child: Container(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12), child: Row(children: const [Icon(Icons.brush, color: Colors.white), SizedBox(width: 8), Text("Annotate", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))]))),
      );
    } else {
      return FloatingActionButton.extended(
        backgroundColor: Colors.transparent, elevation: 0,
        onPressed: _showTaggingSheet,
        label: Ink(decoration: decoration, child: Container(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12), child: Row(children: const [Icon(Icons.label, color: Colors.white), SizedBox(width: 8), Text("Tag Image", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))]))),
      );
    }
  }
}