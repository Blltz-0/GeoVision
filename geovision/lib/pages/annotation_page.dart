import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../components/annotation/annotation_layer.dart';
import '../functions/data_service/metadata_handle.dart';
import '../components/annotation/layer_painter.dart';

enum DrawingTool { brush, bucket, shapefill, eraser }

class AnnotationPage extends StatefulWidget {
  final String imagePath;
  final String projectName;

  const AnnotationPage({
    super.key,
    required this.imagePath,
    required this.projectName,
  });

  @override
  State<AnnotationPage> createState() => _AnnotationPageState();
}

class _AnnotationPageState extends State<AnnotationPage> {
  bool _isTransforming = false;
  final GlobalKey _imageKey = GlobalKey();

  // --- IMAGE DIMENSIONS ---
  double? _imageAspectRatio;
  Size? _imageSize;

  // --- MATRIX STATE ---
  final ValueNotifier<Matrix4> _matrixNotifier = ValueNotifier(Matrix4.identity());
  Matrix4 _anchorMatrix = Matrix4.identity();
  Offset _anchorFocalPoint = Offset.zero;
  double _anchorScale = 1.0;
  double _anchorRotation = 0.0;

  // --- DRAWING STATE ---
  DrawingTool _currentTool = DrawingTool.brush;
  double _strokeWidth = 20.0;
  List<Offset> _currentStrokePoints = [];
  int _activePointerCount = 0;

  // --- LAYER STATE ---
  List<AnnotationLayer> _layers = [];
  int _activeLayerIndex = 0;

  // --- SAVING STATE ---
  Timer? _autoSaveTimer;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadImageDimensions().then((_) {
      _loadProject();
    });

    _autoSaveTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _saveProject(quiet: true);
    });
  }

  Future<void> _loadImageDimensions() async {
    final file = File(widget.imagePath);
    if (!await file.exists()) return;

    final bytes = await file.readAsBytes();
    final decodedImage = await decodeImageFromList(bytes);

    if (mounted) {
      setState(() {
        _imageSize = Size(decodedImage.width.toDouble(), decodedImage.height.toDouble());
        _imageAspectRatio = _imageSize!.width / _imageSize!.height;
      });
    }
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _matrixNotifier.dispose();
    for (var layer in _layers) {
      layer.thumbnail?.dispose();
    }
    super.dispose();
  }

  // --- HELPERS ---

  Offset _toImageCoordinates(Offset localPosition) {
    if (_imageSize == null || _imageKey.currentContext == null) return localPosition;
    final RenderBox? box = _imageKey.currentContext!.findRenderObject() as RenderBox?;
    if (box == null) return localPosition;

    final double scaleX = _imageSize!.width / box.size.width;
    final double scaleY = _imageSize!.height / box.size.height;

    return Offset(localPosition.dx * scaleX, localPosition.dy * scaleY);
  }

  double _getScaledStrokeWidth() {
    if (_imageSize == null || _imageKey.currentContext == null) return _strokeWidth;
    final RenderBox? box = _imageKey.currentContext!.findRenderObject() as RenderBox?;
    if (box == null) return _strokeWidth;
    return _strokeWidth * (_imageSize!.width / box.size.width);
  }

  void _showFeedback(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
        duration: const Duration(milliseconds: 600),
        behavior: SnackBarBehavior.floating,
        width: 200,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.grey,
      ),
    );
  }

  Color _getActiveLayerColor() {
    if (_layers.isEmpty) return Colors.white;
    final layer = _layers[_activeLayerIndex];
    return layer.labelColor != null ? Color(layer.labelColor!) : Colors.white;
  }

  void _executeBucketFill(Offset tapPoint) {
    if (_imageSize == null) return;

    Path? finalPath;
    List<Offset> fillPoints = [];

    // 1. Find which shape was tapped
    for (var stroke in _layers[_activeLayerIndex].strokes.reversed) {
      if (stroke.points.length < 3 || stroke.isEraser) continue;

      final shape = Path()..addPolygon(stroke.points, true);
      if (shape.contains(tapPoint)) {
        finalPath = shape;
        // CRITICAL: Copy the points from the shape we are filling!
        fillPoints = List.from(stroke.points);
        break;
      }
    }

    // 2. If we found a shape, save it using its actual points
    if (finalPath != null) {
      setState(() {
        _layers[_activeLayerIndex].strokes.add(DrawingStroke(
          points: fillPoints, // Now contains the shape outline, not screen corners
          color: _getActiveLayerColor(),
          width: 1.0,
          filled: true,
          path: finalPath,
        ));
        _layers[_activeLayerIndex].redoStrokes.clear();
      });
      _generateThumbnail(_activeLayerIndex);
    } else {
      _showFeedback("Tap inside a shape to fill");
    }
  }


  // --- FILE MANAGEMENT ---
  Future<Directory> _getAnnotationDirectory() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docsDir.path, 'projects', widget.projectName, 'annotation'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> _saveProject({bool quiet = false}) async {
    if (_isSaving || _imageSize == null) return;
    _isSaving = true;
    if (!quiet && mounted) _showFeedback("Saving...");

    try {
      final dir = await _getAnnotationDirectory();
      final String baseImageName = p.basenameWithoutExtension(widget.imagePath);

      if (await dir.exists()) {
        final List<FileSystemEntity> existingFiles = dir.listSync();
        for (var entity in existingFiles) {
          if (entity is File && p.basename(entity.path).startsWith("${baseImageName}_") && p.basename(entity.path).endsWith(".png")) {
            await entity.delete();
          }
        }
      }

      for (int i = 0; i < _layers.length; i++) {
        final layer = _layers[i];
        if (layer.strokes.isEmpty) continue;

        final safeLabel = (layer.labelName ?? "Layer").replaceAll(RegExp(r'[^\w\s]+'), '');
        final fileName = "${baseImageName}_${safeLabel}_$i.png";
        final File file = File(p.join(dir.path, fileName));

        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, _imageSize!.width, _imageSize!.height));
        final painter = LayerPainter(
          strokes: layer.strokes,
          imageSize: _imageSize,
        );
        painter.paint(canvas, _imageSize!);

        final img = await recorder.endRecording().toImage(
            _imageSize!.width.toInt(),
            _imageSize!.height.toInt()
        );
        final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
        if (byteData != null) await file.writeAsBytes(byteData.buffer.asUint8List());
      }

      final jsonFile = File(p.join(dir.path, '${baseImageName}_data.json'));
      await jsonFile.writeAsString(jsonEncode(_layers.map((l) => l.toJson()).toList()));
    } catch (e) {
      debugPrint("Error saving: $e");
    } finally {
      _isSaving = false;
    }
  }

  Future<void> _loadProject() async {
    try {
      final dir = await _getAnnotationDirectory();
      final String baseImageName = p.basenameWithoutExtension(widget.imagePath);
      final jsonFile = File(p.join(dir.path, '${baseImageName}_data.json'));

      if (await jsonFile.exists()) {
        final List<dynamic> jsonList = jsonDecode(await jsonFile.readAsString());
        if (mounted) {
          setState(() {
            _layers = jsonList.map((j) => AnnotationLayer.fromJson(j)).toList();
            _activeLayerIndex = _layers.isNotEmpty ? 0 : 0;
            if (_layers.isEmpty) _addNewLayer();
          });
        }
        for (int i = 0; i < _layers.length; i++) await _generateThumbnail(i);
      } else {
        if (mounted && _layers.isEmpty) setState(() => _addNewLayer());
      }
    } catch (e) {
      if (mounted && _layers.isEmpty) setState(() => _addNewLayer());
    }
  }

  // --- LAYER LOGIC ---
  void _addNewLayer() {
    setState(() {
      int maxNum = 0;
      for (var layer in _layers) {
        final match = RegExp(r'Layer (\d+)').firstMatch(layer.name);
        if (match != null) {
          final num = int.parse(match.group(1)!);
          if (num > maxNum) maxNum = num;
        }
      }
      _layers.add(AnnotationLayer(id: DateTime.now().toIso8601String(), name: "Layer ${maxNum + 1}"));
      _activeLayerIndex = _layers.length - 1;
    });
  }

  void _deleteLayer(int index) {
    setState(() {
      _layers[index].thumbnail?.dispose();
      _layers.removeAt(index);
      for (int i = 0; i < _layers.length; i++) {
        if (RegExp(r'^Layer \d+$').hasMatch(_layers[i].name)) {
          _layers[i].name = "Layer ${i + 1}";
        }
      }
      if (_layers.isEmpty) {
        _addNewLayer();
      } else {
        _activeLayerIndex = _activeLayerIndex.clamp(0, _layers.length - 1);
      }
    });
    _showFeedback("Layer Deleted");
  }

  void _clearLayer(int index) async {
    if (_layers[index].isLocked) return;
    setState(() {
      _layers[index].strokes.clear();
      _layers[index].redoStrokes.clear();
    });
    await _generateThumbnail(index);
    _showFeedback("Layer Cleared");
  }

  void _updateLayerLabel(int layerIndex, String name, int colorInt) {
    if (_layers[layerIndex].isLocked) return;
    setState(() {
      final layer = _layers[layerIndex];
      layer.labelName = name;
      layer.labelColor = colorInt;
      final newColor = Color(colorInt);
      layer.strokes = layer.strokes.map((s) => s.isEraser ? s : s.copyWith(color: newColor)).toList();
    });
    _generateThumbnail(layerIndex);
  }

  Future<void> _generateThumbnail(int layerIndex) async {
    final layer = _layers[layerIndex];
    if (layer.strokes.isEmpty) {
      setState(() => layer.thumbnail = null);
      return;
    }

    const double thumbSize = 100.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, thumbSize, thumbSize));

    if (_imageSize != null) {
      // Determine the scale factor (e.g., 100 / 640)
      double scale = thumbSize / _imageSize!.width;
      canvas.scale(scale);
    }

    // Draw the strokes using the existing painter
    final painter = LayerPainter(strokes: layer.strokes);
    painter.paint(canvas, Size(_imageSize?.width ?? thumbSize, _imageSize?.height ?? thumbSize));

    final picture = recorder.endRecording();
    final img = await picture.toImage(thumbSize.toInt(), thumbSize.toInt());

    if (mounted) {
      setState(() {
        layer.thumbnail?.dispose(); // Clean up old memory
        layer.thumbnail = img;
      });
    }
  }

  // --- INPUT HANDLING ---
  Offset? _getLocalValidPoint(Offset globalPoint) {
    final box = _imageKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;
    final local = box.globalToLocal(globalPoint);
    if (local.dx < 0 || local.dy < 0 || local.dx > box.size.width || local.dy > box.size.height) return null;
    return local;
  }

  void _onScaleStart(ScaleStartDetails details) {
    _activePointerCount = details.pointerCount;

    if (_activePointerCount >= 2) {
      // Flag that we are now moving/zooming
      _isTransforming = true;

      _anchorMatrix = _matrixNotifier.value;
      _anchorFocalPoint = details.localFocalPoint;
    } else if (_activePointerCount == 1) {
      // ONLY start a drawing stroke if we aren't currently in a multi-finger interaction
      if (_isTransforming || _layers[_activeLayerIndex].isLocked) return;

      final validPoint = _getLocalValidPoint(details.focalPoint);
      if (validPoint != null) {
        final imgPoint = _toImageCoordinates(validPoint);
        if (_currentTool == DrawingTool.bucket) {
          _executeBucketFill(imgPoint);
        } else {
          setState(() => _currentStrokePoints = [imgPoint]);
        }
      }
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    // If we ever hit 2 fingers, force the transform flag to true
    if (details.pointerCount >= 2) _isTransforming = true;

    if (_isTransforming) {
      // Navigation Logic: Works with 2 fingers OR 1 finger (if it was part of a 2-finger gesture)
      final Matrix4 m = Matrix4.identity()
        ..translate(details.localFocalPoint.dx, details.localFocalPoint.dy)
        ..rotateZ(details.rotation)
        ..scale(details.scale)
        ..translate(-_anchorFocalPoint.dx, -_anchorFocalPoint.dy);

      _matrixNotifier.value = m * _anchorMatrix;
    } else if (details.pointerCount == 1 && _currentStrokePoints.isNotEmpty) {
      // Standard drawing logic: only runs if we never triggered _isTransforming
      final validPoint = _getLocalValidPoint(details.focalPoint);
      if (validPoint != null) {
        setState(() => _currentStrokePoints.add(_toImageCoordinates(validPoint)));
      }
    }
  }

  void _onScaleEnd(ScaleEndDetails details) async {
    // If we were drawing (not transforming), save the stroke
    if (!_isTransforming && _currentStrokePoints.isNotEmpty) {
      setState(() {
        _layers[_activeLayerIndex].strokes.add(DrawingStroke(
          points: List.from(_currentStrokePoints),
          color: _getActiveLayerColor(),
          width: _getScaledStrokeWidth(),
          isEraser: _currentTool == DrawingTool.eraser,
          filled: _currentTool == DrawingTool.shapefill,
        ));
        _layers[_activeLayerIndex].redoStrokes.clear();
        _currentStrokePoints = [];
      });
      await _generateThumbnail(_activeLayerIndex);
    }
    _currentStrokePoints = [];
    _isTransforming = false;
    _activePointerCount = 0;
  }

  void _undo() async {
    final layer = _layers[_activeLayerIndex];
    if (layer.strokes.isEmpty) return;
    setState(() {
      layer.redoStrokes.add(layer.strokes.removeLast());
    });
    await _generateThumbnail(_activeLayerIndex);
  }

  void _redo() async {
    final layer = _layers[_activeLayerIndex];
    if (layer.redoStrokes.isEmpty) return;
    setState(() {
      layer.strokes.add(layer.redoStrokes.removeLast());
    });
    await _generateThumbnail(_activeLayerIndex);
  }

  // --- MODALS ---
  void _showSizeSlider() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return StatefulBuilder(builder: (context, setModalState) {
          return Container(
            height: 150,
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Text("Size: ${_strokeWidth.toStringAsFixed(1)}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                Slider(
                  value: _strokeWidth,
                  min: 1.0, max: 100.0,
                  activeColor: _currentTool == DrawingTool.eraser ? Colors.red : _getActiveLayerColor(),
                  onChanged: (val) {
                    setState(() => _strokeWidth = val);
                    setModalState(() {});
                  },
                ),
                Container(
                  width: _strokeWidth.clamp(4, 40).toDouble(),
                  height: _strokeWidth.clamp(4, 40).toDouble(),
                  decoration: BoxDecoration(
                    color: _currentTool == DrawingTool.eraser ? Colors.red : _getActiveLayerColor(),
                    shape: BoxShape.circle,
                  ),
                )
              ],
            ),
          );
        });
      },
    );
  }

  void _showLayerManager() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return FractionallySizedBox(
              heightFactor: 0.5,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Layers", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                        Row(
                          children: [
                            TextButton.icon(
                              onPressed: () => _confirmResetAllAnnotations(setModalState),
                              icon: const Icon(Icons.delete_forever, size: 20, color: Colors.redAccent),
                              label: const Text("Reset", style: TextStyle(color: Colors.redAccent)),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_circle, color: Colors.blueAccent, size: 28),
                              onPressed: () {
                                _addNewLayer();
                                setModalState(() {});
                                setState(() {});
                              },
                            ),
                          ],
                        )
                      ],
                    ),
                  ),
                  const Divider(color: Colors.grey, height: 1),
                  Expanded(
                    child: FutureBuilder<List<Map<String, dynamic>>>(
                      future: MetadataService.getLabels(widget.projectName),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                        final availableLabels = snapshot.data ?? [];
                        return ListView.builder(
                          itemCount: _layers.length,
                          itemBuilder: (context, index) {
                            final layer = _layers[index];
                            final isActive = index == _activeLayerIndex;
                            return GestureDetector(
                              onTap: () {
                                setState(() => _activeLayerIndex = index);
                                setModalState(() {});
                              },
                              child: Container(
                                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: isActive ? Colors.blueAccent : Colors.grey.withOpacity(0.3)),
                                ),
                                child: Row(
                                  children: [
                                    IconButton(
                                      icon: Icon(layer.isVisible ? Icons.visibility : Icons.visibility_off, color: Colors.white, size: 20),
                                      onPressed: () {
                                        setState(() => layer.isVisible = !layer.isVisible);
                                        setModalState(() {});
                                      },
                                    ),
                                    Container(
                                      width: 40, height: 40,
                                      decoration: BoxDecoration(border: Border.all(color: Colors.white30)),
                                      child: layer.thumbnail != null ? RawImage(image: layer.thumbnail!) : null,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(layer.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                          DropdownButtonHideUnderline(
                                            child: DropdownButton<String>(
                                              isDense: true,
                                              hint: const Text("Select Label", style: TextStyle(color: Colors.grey, fontSize: 11)),
                                              value: layer.labelName,
                                              dropdownColor: const Color(0xFF333333),
                                              items: availableLabels.map((l) => DropdownMenuItem<String>(
                                                value: l['name'],
                                                child: Text(l['name'], style: const TextStyle(color: Colors.white, fontSize: 12)),
                                              )).toList(),
                                              onChanged: (val) {
                                                if (val != null) {
                                                  final lbl = availableLabels.firstWhere((element) => element['name'] == val);
                                                  _updateLayerLabel(index, val, lbl['color']);
                                                  setModalState(() {});
                                                }
                                              },
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      icon: Icon(layer.isLocked ? Icons.lock : Icons.lock_open, color: layer.isLocked ? Colors.orange : Colors.grey, size: 18),
                                      onPressed: () {
                                        setState(() => layer.isLocked = !layer.isLocked);
                                        setModalState(() {});
                                      },
                                    ),
                                    PopupMenuButton<String>(
                                      onSelected: (v) {
                                        if (v == 'clear') _clearLayer(index);
                                        if (v == 'delete') _deleteLayer(index);
                                        setModalState(() {});
                                      },
                                      itemBuilder: (context) => [
                                        const PopupMenuItem(value: 'clear', child: Text("Clear")),
                                        const PopupMenuItem(value: 'delete', child: Text("Delete", style: TextStyle(color: Colors.red))),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _confirmResetAllAnnotations(StateSetter setModalState) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF333333),
        title: const Text("Reset All?", style: TextStyle(color: Colors.white)),
        content: const Text("This will delete ALL layers and drawings.", style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel", style: TextStyle(color: Colors.white))),
          TextButton(
            onPressed: () {
              setState(() {
                for (var l in _layers) l.thumbnail?.dispose();
                _layers.clear();
                _addNewLayer();
                _activeLayerIndex = 0;
              });
              setModalState(() {});
              Navigator.pop(context);
            },
            child: const Text("Reset", style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  // --- BUILD ---
  @override
  Widget build(BuildContext context) {
    if (_imageAspectRatio == null) return const Scaffold(backgroundColor: Colors.black, body: Center(child: CircularProgressIndicator()));

    final activeLayer = _layers[_activeLayerIndex];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _saveProject();
        if (context.mounted) Navigator.of(context).pop(true);
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          iconTheme: const IconThemeData(color: Colors.white),
          title: const Text("Annotate", style: TextStyle(color: Colors.white)),
          actions: [
            IconButton(icon: const Icon(Icons.refresh), onPressed: () => _matrixNotifier.value = Matrix4.identity()),
            IconButton(icon: const Icon(Icons.undo), onPressed: activeLayer.strokes.isNotEmpty ? _undo : null),
            IconButton(icon: const Icon(Icons.redo), onPressed: activeLayer.redoStrokes.isNotEmpty ? _redo : null),
          ],
        ),
        body: Stack(
          children: [
            GestureDetector(
              onScaleStart: _onScaleStart,
              onScaleUpdate: _onScaleUpdate,
              onScaleEnd: _onScaleEnd,
              child: ValueListenableBuilder<Matrix4>(
                valueListenable: _matrixNotifier,
                builder: (context, matrix, _) => Transform(
                  transform: matrix,
                  alignment: Alignment.center,
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: _imageAspectRatio!,
                      child: Stack(
                        key: _imageKey,
                        fit: StackFit.expand,
                        children: [
                          Image.file(File(widget.imagePath), fit: BoxFit.fill),
                          ..._layers.asMap().entries.map((e) {
                            if (!e.value.isVisible) return const SizedBox.shrink();
                            return Positioned.fill(
                              child: Opacity(
                                opacity: 0.4,
                                child: CustomPaint(
                                  painter: LayerPainter(
                                    strokes: e.value.strokes,
                                    currentStroke: (e.key == _activeLayerIndex && _currentStrokePoints.isNotEmpty)
                                        ? DrawingStroke(
                                      points: _currentStrokePoints,
                                      color: _getActiveLayerColor(),
                                      width: _getScaledStrokeWidth(),
                                      isEraser: _currentTool == DrawingTool.eraser,
                                      filled: _currentTool == DrawingTool.shapefill,
                                    ) : null,
                                    imageSize: _imageSize,
                                  ),
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 20, left: 0, right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.circle, color: _getActiveLayerColor(), size: 12),
                    const SizedBox(width: 8),
                    Text(activeLayer.labelName ?? "No Label", style: const TextStyle(color: Colors.white)),
                  ]),
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: BottomAppBar(
          color: Colors.black,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              DropdownButtonHideUnderline(
                child: DropdownButton<DrawingTool>(
                  dropdownColor: const Color(0xFF1E1E1E),
                  value: _currentTool,
                  icon: const Icon(Icons.arrow_drop_up, color: Colors.white),
                  items: [
                    _buildToolDropdownItem(DrawingTool.brush, "Brush", Icons.brush),
                    _buildToolDropdownItem(DrawingTool.bucket, "Bucket", Icons.format_color_fill),
                    _buildToolDropdownItem(DrawingTool.shapefill, "Shape Fill", Icons.format_paint),
                    _buildToolDropdownItem(DrawingTool.eraser, "Eraser", Icons.cleaning_services),
                  ],
                  onChanged: (v) => setState(() => _currentTool = v!),
                ),
              ),
              IconButton(onPressed: _showSizeSlider, icon: Icon(Icons.circle, size: _strokeWidth.clamp(10, 24))),
              GestureDetector(onTap: _showLayerManager, child: _buildLayerBadge()),
            ],
          ),
        ),
      ),
    );
  }

  DropdownMenuItem<DrawingTool> _buildToolDropdownItem(DrawingTool t, String n, IconData i) {
    return DropdownMenuItem(
      value: t,
      child: Row(children: [
        Icon(i, color: _currentTool == t ? Colors.blueAccent : Colors.white70, size: 20),
        const SizedBox(width: 10),
        Text(n, style: const TextStyle(color: Colors.white, fontSize: 14)),
      ]),
    );
  }

  Widget _buildLayerBadge() {
    return Stack(alignment: Alignment.topRight, children: [
      const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.layers, color: Colors.white, size: 28)),
      CircleAvatar(radius: 8, backgroundColor: Colors.redAccent, child: Text("${_activeLayerIndex + 1}", style: const TextStyle(fontSize: 10, color: Colors.white))),
    ]);
  }
}