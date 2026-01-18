import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'dart:convert';
import 'package:path_provider/path_provider.dart'; // [ADDED] Required for directory access

import '../components/class_creator.dart';
import '../components/edit_metadata_dialog.dart';
import '../components/location_decoder.dart';
import '../functions/metadata_handle.dart';
import '../components/ellipsis_menu.dart';

// --- MAIN IMAGE VIEW ---
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
  bool _hasChanges = false;
  List<Map<String, dynamic>> _metadataCache = [];
  Map<String, Color> _classColorMap = {};

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

  String _getFilename(String path) {
    return path.split(Platform.pathSeparator).last;
  }

  // --- [NEW] Helper to remove from upload_history.json ---
  Future<void> _removeImageFromHistory(String filename) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final historyFile = File('${appDir.path}/projects/${widget.projectName}/upload_history.json');

      if (await historyFile.exists()) {
        final String content = await historyFile.readAsString();
        final dynamic decoded = jsonDecode(content);

        if (decoded is Map) {
          Map<String, dynamic> historyMap = Map<String, dynamic>.from(decoded);

          // Remove the entry using the filename as the key
          if (historyMap.containsKey(filename)) {
            historyMap.remove(filename);
            await historyFile.writeAsString(jsonEncode(historyMap));
            debugPrint("Removed $filename from upload history.");
          }
        }
      }
    } catch (e) {
      debugPrint("Error removing from history: $e");
    }
  }
  // -------------------------------------------------------

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

  bool _hasAnnotation(String imagePath) {
    if (widget.projectType != 'segmentation') return false;
    try {
      final imageFile = File(imagePath);
      final String fileNameNoExt = p.basenameWithoutExtension(imagePath);
      final Directory imageDir = imageFile.parent;
      final Directory projectDir = imageDir.parent;
      final String annotationPath = p.join(projectDir.path, 'annotation', '${fileNameNoExt}_data.json');

      final file = File(annotationPath);
      if (!file.existsSync()) return false;

      final String content = file.readAsStringSync();
      final List<dynamic> jsonLayers = jsonDecode(content);

      return jsonLayers.any((layer) {
        final strokes = layer['strokes'] as List?;
        return strokes != null && strokes.isNotEmpty;
      });

    } catch (e) {
      return false;
    }
  }

  List<File> _getAnnotationLayers(String imagePath) {
    if (!widget.projectType.contains('segmentation')) return [];

    try {
      final imageFile = File(imagePath);
      final String fileNameNoExt = p.basenameWithoutExtension(imagePath);
      final Directory imageDir = imageFile.parent;
      final Directory projectDir = imageDir.parent;

      final String annotationPath = p.join(projectDir.path, 'annotation');
      final Directory annotationDir = Directory(annotationPath);

      if (!annotationDir.existsSync()) return [];

      final List<FileSystemEntity> files = annotationDir.listSync();

      List<File> layerImages = [];

      for (var entity in files) {
        if (entity is File) {
          final String name = p.basename(entity.path);
          if (name.startsWith("${fileNameNoExt}_") && name.endsWith('.png')) {
            layerImages.add(entity);
          }
        }
      }

      layerImages.sort((a, b) {
        try {
          String nameA = p.basenameWithoutExtension(a.path);
          String nameB = p.basenameWithoutExtension(b.path);

          int indexA = int.parse(nameA.split('_').last);
          int indexB = int.parse(nameB.split('_').last);

          return indexA.compareTo(indexB);
        } catch (e) {
          return 0;
        }
      });

      return layerImages;
    } catch (e) {
      debugPrint("Error fetching layers: $e");
      return [];
    }
  }

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
        return FutureBuilder<List<Map<String, dynamic>>>(
          future: MetadataService.readCsvData(widget.projectName),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const AlertDialog(content: SizedBox(height: 100, child: Center(child: CircularProgressIndicator())));
            }

            Map<String, dynamic> imageInfo = {};
            if (snapshot.hasData) {
              imageInfo = snapshot.data!.firstWhere(
                    (element) => _getFilename(element['path'].toString()) == targetFilename,
                orElse: () => {},
              );
            }

            double lat = imageInfo['lat'] is double
                ? imageInfo['lat']
                : (double.tryParse(imageInfo['lat'].toString()) ?? 0.0);

            double lng = imageInfo['lng'] is double
                ? imageInfo['lng']
                : (double.tryParse(imageInfo['lng'].toString()) ?? 0.0);

            DateTime dt = DateTime.now();
            if (imageInfo['time'] != null) {
              try { dt = DateTime.parse(imageInfo['time']); } catch (_) {}
            }

            return AlertDialog(
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Image Info'),
                  IconButton(
                    icon: const Icon(Icons.edit, color: Colors.blue),
                    tooltip: "Edit Metadata",
                    onPressed: () {
                      Navigator.pop(context);
                      showDialog(
                          context: context,
                          builder: (ctx) => EditMetadataDialog(
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

                              if (mounted) {
                                setState(() {
                                  _hasChanges = true;
                                  _loadMetadata();
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text("Image & CSV Updated"))
                                );
                              }
                            },
                          )
                      );
                    },
                  )
                ],
              ),
              content: SizedBox(
                height: 180,
                width: double.maxFinite,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Text("File: $targetFilename", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const Divider(),
                    Row(children: [
                      const Icon(Icons.calendar_today, size: 16, color: Colors.blue),
                      const SizedBox(width: 8),
                      Text("${dt.year}-${dt.month}-${dt.day}  ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}"),
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
      },
    );
  }

  void _showTaggingSheet() async {
    final currentPath = _currentImagePaths[_currentIndex];
    final classes = await MetadataService.getClasses(widget.projectName);

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
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
                  leading: CircleAvatar(backgroundColor: Color(cls['color']), radius: 12),
                  title: Text(cls['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                  onTap: () async {
                    String? newPath = await MetadataService.tagImage(
                      widget.projectName,
                      currentPath,
                      cls['name'],
                    );

                    if (!mounted) return;
                    Navigator.pop(context);

                    if (newPath != null) {
                      await FileImage(File(currentPath)).evict();
                      await FileImage(File(newPath)).evict();

                      await ResizeImage(FileImage(File(currentPath)), width: 300).evict();
                      await ResizeImage(FileImage(File(newPath)), width: 300).evict();

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
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
              icon: const Icon(Icons.add),
              label: const Text("Create New Class"),
              onPressed: () async {
                Navigator.pop(context);
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => CreateClassPage(projectName: widget.projectName)),
                );
                if (mounted) _showTaggingSheet();
              },
            )
          ],
        ),
      ),
    ).whenComplete(() {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    });
  }

  @override
  Widget build(BuildContext context) {
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
            "${_currentIndex + 1} of ${_currentImagePaths.length}",
            style: const TextStyle(color: Colors.white),
          ),
          actions: [
            // --- UPDATED DELETE ACTION WITH CONFIRMATION ---
            EllipsisMenu(
              onInfo: () => showImageInformation(context, _currentImagePaths[_currentIndex]),
              onDelete: () async {
                final String currentPath = _currentImagePaths[_currentIndex];
                final String filename = currentPath.split(Platform.pathSeparator).last;

                // 1. Show Confirmation Dialog
                final bool? shouldDelete = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text("Delete Image?"),
                    content: Text(
                        "Are you sure you want to permanently delete '$filename'?\n\nThis action cannot be undone."),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text("Cancel"),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text("Delete"),
                      ),
                    ],
                  ),
                );

                // 2. If confirmed, proceed with deletion
                if (shouldDelete == true && context.mounted) {
                  final navigator = Navigator.of(context);
                  final messenger = ScaffoldMessenger.of(context);

                  // Delete File & CSV Entry
                  await MetadataService.deleteImage(
                    projectName: widget.projectName,
                    imagePath: currentPath,
                  );

                  // Remove from Upload History
                  await _removeImageFromHistory(filename);

                  navigator.pop(true);
                  messenger.showSnackBar(const SnackBar(
                    content: Text("Image Deleted"),
                    backgroundColor: Colors.redAccent,
                    duration: Duration(seconds: 1),
                  ));
                }
              },
            ),
          ],
        ),
        body: PageView.builder(
          controller: _pageController,
          itemCount: _currentImagePaths.length,
          onPageChanged: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          itemBuilder: (context, index) {
            final imagePath = _currentImagePaths[index];
            final info = _getCurrentImageInfo(imagePath);
            final bool isAnnotated = _hasAnnotation(imagePath);

            final List<File> overlayLayers = _showAnnotations && isAnnotated
                ? _getAnnotationLayers(imagePath)
                : [];

            String className = info['class'] ?? "Unclassified";
            Color tagColor = _classColorMap[className] ?? Colors.grey;

            double lat = info['lat'] is double
                ? info['lat']
                : (double.tryParse(info['lat'].toString()) ?? 0.0);

            double lng = info['lng'] is double
                ? info['lng']
                : (double.tryParse(info['lng'].toString()) ?? 0.0);

            String dateString = "--";
            if (info['time'] != null) {
              try {
                final dt = DateTime.parse(info['time']);
                dateString = "${dt.year}-${dt.month}-${dt.day} ${dt.hour}:${dt.minute}";
              } catch (_) {}
            }

            return Column(
              children: [
                // Top Info Bar
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
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (widget.projectType != 'segmentation')
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
                            ),
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
                            child: LocationDisplay(
                              latitude: lat,
                              longitude: lng,
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Main Image Area
                Expanded(
                  child: Stack(
                    children: [
                      InteractiveViewer(
                        panEnabled: true,
                        boundaryMargin: const EdgeInsets.all(20),
                        minScale: 1,
                        maxScale: 4.0,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Hero(
                              tag: imagePath,
                              child: Image.file(
                                File(imagePath),
                                fit: BoxFit.contain,
                              ),
                            ),
                            // Only render layers if showAnnotations is true
                            if (_showAnnotations)
                              ...overlayLayers.map((file) => Opacity(
                                opacity: 0.4,
                                child: Image.file(
                                  file,
                                  key: ValueKey("${file.path}_${file.lastModifiedSync().millisecondsSinceEpoch}"),
                                  fit: BoxFit.contain,
                                  errorBuilder: (c,e,s) => const SizedBox(),
                                ),
                              )),
                          ],
                        ),
                      ),

                      // Only show this button if the image actually has annotations
                      if (isAnnotated)
                        Positioned(
                          top: 10,
                          right: 10,
                          child: Material(
                            color: Colors.transparent, // Required for InkWell ripple
                            child: InkWell(
                              borderRadius: BorderRadius.circular(30),
                              onTap: () {
                                setState(() {
                                  _showAnnotations = !_showAnnotations;
                                });
                                ScaffoldMessenger.of(context).clearSnackBars();
                                ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(_showAnnotations ? "Showing Annotations" : "Hiding Annotations"),
                                      duration: const Duration(milliseconds: 600),
                                      behavior: SnackBarBehavior.floating,
                                    )
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.6),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: _showAnnotations ? Colors.lightGreenAccent : Colors.white54,
                                      width: 1.5
                                  ),
                                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                                ),
                                child: Icon(
                                  _showAnnotations ? Icons.brush : Icons.brush,
                                  size: 20,
                                  color: _showAnnotations ? Colors.lightGreenAccent : Colors.white54,
                                ),
                              ),
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
    if (widget.projectType == 'segmentation') {
      return FloatingActionButton.extended(
        heroTag: "annotate_fab",
        onPressed: () async {
          if (widget.onAnnotate != null) {
            bool? result = await widget.onAnnotate!(_currentImagePaths[_currentIndex]);

            if (result == true && mounted) {
              final currentImgPath = _currentImagePaths[_currentIndex];
              final layers = _getAnnotationLayers(currentImgPath);

              for (var file in layers) {
                await FileImage(file).evict();
              }

              PaintingBinding.instance.imageCache.clear();
              PaintingBinding.instance.imageCache.clearLiveImages();

              setState(() {
                _hasChanges = true;
                _showAnnotations = true;
              });
            }
          }
        },
        icon: const Icon(Icons.brush),
        label: const Text("Annotate"),
        backgroundColor: Colors.lightGreenAccent,
      );
    } else if (widget.projectType == 'classification') {
      return FloatingActionButton.extended(
        heroTag: "tag_fab",
        onPressed: _showTaggingSheet,
        icon: const Icon(Icons.label),
        label: const Text("Tag Image"),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
      );
    }
    return null;
  }
}