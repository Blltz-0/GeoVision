import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../components/annotation_layer.dart';
import '../functions/metadata_handle.dart';
import '../components/layer_painter.dart';

enum DrawingTool { brush, eraser }

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

  // --- HELPERS: COORDINATE CONVERSION (THE FIX) ---

  // Converts a screen touch (e.g. 200, 200) to an image coordinate (e.g. 2000, 2000)
  Offset _toImageCoordinates(Offset localPosition) {
    if (_imageSize == null || _imageKey.currentContext == null) return localPosition;

    final RenderBox? box = _imageKey.currentContext!.findRenderObject() as RenderBox?;
    if (box == null) return localPosition;

    final double scaleX = _imageSize!.width / box.size.width;
    final double scaleY = _imageSize!.height / box.size.height;

    return Offset(
      localPosition.dx * scaleX,
      localPosition.dy * scaleY,
    );
  }

  // Scale brush size so it matches image resolution
  double _getScaledStrokeWidth() {
    if (_imageSize == null || _imageKey.currentContext == null) return _strokeWidth;
    final RenderBox? box = _imageKey.currentContext!.findRenderObject() as RenderBox?;
    if (box == null) return _strokeWidth;

    final double scale = _imageSize!.width / box.size.width;
    return _strokeWidth * scale;
  }

  // --- FEEDBACK POPUP ---
  void _showFeedback(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        duration: const Duration(milliseconds: 600),
        behavior: SnackBarBehavior.floating,
        width: 200,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.grey,
      ),
    );
  }

  // --- FILE MANAGEMENT ---
  Future<Directory> _getAnnotationDirectory() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final Directory annotationDir = Directory(
        p.join(docsDir.path, 'projects', widget.projectName, 'annotation')
    );

    if (!await annotationDir.exists()) {
      await annotationDir.create(recursive: true);
    }
    return annotationDir;
  }

  Future<void> _saveProject({bool quiet = false}) async {
    if (_isSaving || _imageSize == null) return;
    _isSaving = true;
    if (!quiet && mounted) _showFeedback("Saving...");

    try {
      final dir = await _getAnnotationDirectory();
      final String baseImageName = p.basenameWithoutExtension(widget.imagePath);

      // 1. Save PNGs
      for (int i = 0; i < _layers.length; i++) {
        final layer = _layers[i];
        if (layer.strokes.isEmpty) continue;

        final safeLabel = (layer.labelName ?? "Layer").replaceAll(RegExp(r'[^\w\s]+'), '');
        final fileName = "${baseImageName}_${safeLabel}_$i.png";
        final File file = File(p.join(dir.path, fileName));

        final recorder = ui.PictureRecorder();
        // Canvas is full image size
        final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, _imageSize!.width, _imageSize!.height));

        // Painter draws in image coordinates (no scaling needed for save, so passed scale is implicitly 1.0)
        final painter = LayerPainter(strokes: layer.strokes);
        painter.paint(canvas, _imageSize!);

        final picture = recorder.endRecording();
        final img = await picture.toImage(_imageSize!.width.toInt(), _imageSize!.height.toInt());
        final byteData = await img.toByteData(format: ui.ImageByteFormat.png);

        if (byteData != null) {
          await file.writeAsBytes(byteData.buffer.asUint8List());
        }
      }

      // 2. Save JSON
      final jsonFile = File(p.join(dir.path, '${baseImageName}_data.json'));
      final List<Map<String, dynamic>> jsonLayers = _layers.map((l) => l.toJson()).toList();
      await jsonFile.writeAsString(jsonEncode(jsonLayers));

    } catch (e) {
      debugPrint("Error saving project: $e");
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
        final content = await jsonFile.readAsString();
        final List<dynamic> jsonList = jsonDecode(content);

        if (mounted) {
          setState(() {
            _layers = jsonList.map((j) => AnnotationLayer.fromJson(j)).toList();
            if (_layers.isNotEmpty) {
              _activeLayerIndex = 0;
            } else {
              _addNewLayer();
            }
          });
        }
        for (int i = 0; i < _layers.length; i++) {
          await _generateThumbnail(i);
        }
      } else {
        if (mounted && _layers.isEmpty) {
          setState(() {
            _addNewLayer();
          });
        }
      }
    } catch (e) {
      debugPrint("Error loading project: $e");
      if (mounted && _layers.isEmpty) {
        setState(() => _addNewLayer());
      }
    }
  }

  // --- LAYER LOGIC ---

  void _resetView() {
    _matrixNotifier.value = Matrix4.identity();
    _showFeedback("Reset Image Position");
  }

  void _addNewLayer() {
    setState(() {
      int newNum = _layers.length + 1;
      _layers.add(AnnotationLayer(id: DateTime.now().toIso8601String(), name: "Layer $newNum"));
      _activeLayerIndex = _layers.length - 1;
    });
  }

  void _setActiveLayer(int index) => setState(() => _activeLayerIndex = index);

  void _toggleLayerVisibility(int index) {
    setState(() {
      _layers[index].isVisible = !_layers[index].isVisible;
    });
  }

  void _confirmDeleteLayer(int index, StateSetter setModalState) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF333333),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text("Delete Layer?", style: TextStyle(color: Colors.white)),
        content: const Text(
          "This will permanently delete this layer and all its drawings. This action cannot be undone.",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text("Cancel", style: TextStyle(color: Colors.white)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _deleteLayer(index);
              setModalState(() {});
            },
            child: const Text("Delete", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _deleteLayer(int index) {
    setState(() {
      _layers[index].thumbnail?.dispose();
      _layers.removeAt(index);

      if (_layers.isEmpty) {
        _addNewLayer();
        return;
      }

      if (_activeLayerIndex >= index) {
        if (_activeLayerIndex == index) {
          _activeLayerIndex = (_activeLayerIndex - 1).clamp(0, _layers.length - 1);
        } else {
          _activeLayerIndex -= 1;
        }
      }
    });
    _showFeedback("Layer Deleted");
  }

  void _clearLayer(int index) async {
    setState(() {
      _layers[index].strokes.clear();
      _layers[index].redoStrokes.clear();
    });
    await _generateThumbnail(index);
    _showFeedback("Layer Cleared");
  }

  void _updateLayerLabel(int layerIndex, String name, int colorInt) {
    setState(() {
      final layer = _layers[layerIndex];
      final newColor = Color(colorInt);

      layer.labelName = name;
      layer.labelColor = colorInt;

      // Update color but preserve eraser
      layer.strokes = layer.strokes.map((stroke) {
        if (stroke.isEraser) return stroke;
        return stroke.copyWith(color: newColor);
      }).toList();

      layer.redoStrokes = layer.redoStrokes.map((stroke) {
        if (stroke.isEraser) return stroke;
        return stroke.copyWith(color: newColor);
      }).toList();
    });
    _generateThumbnail(layerIndex);
  }

  Future<void> _generateThumbnail(int layerIndex) async {
    final layer = _layers[layerIndex];
    if (layer.strokes.isEmpty) {
      setState(() {
        layer.thumbnail?.dispose();
        layer.thumbnail = null;
      });
      return;
    }

    const double thumbSize = 100.0;
    const double padding = 5.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, thumbSize, thumbSize));

    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;
    double maxStrokeWidth = 0.0;

    for (var stroke in layer.strokes) {
      if (stroke.width > maxStrokeWidth) maxStrokeWidth = stroke.width;
      for (var point in stroke.points) {
        if (point.dx < minX) minX = point.dx;
        if (point.dy < minY) minY = point.dy;
        if (point.dx > maxX) maxX = point.dx;
        if (point.dy > maxY) maxY = point.dy;
      }
    }

    if (minX == double.infinity) {
      minX = 0; minY = 0; maxX = 100; maxY = 100;
    }

    Rect contentBounds = Rect.fromLTRB(minX, minY, maxX, maxY);
    contentBounds = contentBounds.inflate((maxStrokeWidth / 2) + padding);

    final double scaleX = thumbSize / contentBounds.width;
    final double scaleY = thumbSize / contentBounds.height;
    final double scale = scaleX < scaleY ? scaleX : scaleY;

    final double scaledContentWidth = contentBounds.width * scale;
    final double scaledContentHeight = contentBounds.height * scale;
    final double offsetX = (thumbSize - scaledContentWidth) / 2;
    final double offsetY = (thumbSize - scaledContentHeight) / 2;

    canvas.translate(offsetX, offsetY);
    canvas.scale(scale, scale);
    canvas.translate(-contentBounds.left, -contentBounds.top);

    // Note: We do NOT pass imageSize here, because we manually calculated the scale above
    // to fit the strokes into 100x100.
    final painter = LayerPainter(strokes: layer.strokes);
    painter.paint(canvas, Size.infinite);

    final picture = recorder.endRecording();
    final img = await picture.toImage(thumbSize.toInt(), thumbSize.toInt());

    setState(() {
      layer.thumbnail?.dispose();
      layer.thumbnail = img;
    });
  }

  Color _getActiveLayerColor() {
    final layer = _layers[_activeLayerIndex];
    Color baseColor = Colors.white;
    if (layer.labelColor != null) {
      baseColor = Color(layer.labelColor!);
    }
    return baseColor;
  }

  void _toggleTool() {
    setState(() {
      _currentTool = (_currentTool == DrawingTool.brush) ? DrawingTool.eraser : DrawingTool.brush;
    });
    _showFeedback(_currentTool == DrawingTool.brush ? "Brush" : "Eraser");
  }

  Offset? _getLocalValidPoint(Offset globalPoint) {
    final RenderBox? box = _imageKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;
    final Offset local = box.globalToLocal(globalPoint);
    if (local.dx < 0 || local.dy < 0 || local.dx > box.size.width || local.dy > box.size.height) {
      return null;
    }
    return local;
  }

  // --- UPDATED SCALE LOGIC (CONVERTS TO IMAGE COORDS) ---
  void _onScaleStart(ScaleStartDetails details) {
    _activePointerCount = details.pointerCount;
    if (_activePointerCount == 1) {
      if (!_layers[_activeLayerIndex].isVisible) return;

      final validLocalPoint = _getLocalValidPoint(details.focalPoint);
      if (validLocalPoint != null) {
        // Convert screen point to image point immediately
        final imagePoint = _toImageCoordinates(validLocalPoint);
        setState(() => _currentStrokePoints = [imagePoint]);
      }
    } else {
      _anchorMatrix = _matrixNotifier.value.clone();
      _anchorFocalPoint = details.localFocalPoint;
      _anchorScale = 1.0;
      _anchorRotation = 0.0;
      _currentStrokePoints = [];
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_activePointerCount != details.pointerCount) {
      _activePointerCount = details.pointerCount;
      if (_activePointerCount >= 2) {
        _currentStrokePoints = [];
        _anchorMatrix = _matrixNotifier.value.clone();
        _anchorFocalPoint = details.localFocalPoint;
        _anchorScale = details.scale;
        _anchorRotation = details.rotation;
      }
      return;
    }

    if (_activePointerCount == 1) {
      if (!_layers[_activeLayerIndex].isVisible) return;

      final validLocalPoint = _getLocalValidPoint(details.focalPoint);
      if (validLocalPoint != null) {
        // Convert to Image Coords
        final imagePoint = _toImageCoordinates(validLocalPoint);
        setState(() => _currentStrokePoints.add(imagePoint));
      }
    } else {
      final double scaleDelta = details.scale / _anchorScale;
      final double rotationDelta = details.rotation - _anchorRotation;
      final Offset currentFocal = details.localFocalPoint;
      final Matrix4 translateToOrigin = Matrix4.translationValues(-_anchorFocalPoint.dx, -_anchorFocalPoint.dy, 0);
      final Matrix4 rotate = Matrix4.rotationZ(rotationDelta);
      final Matrix4 scale = Matrix4.diagonal3Values(scaleDelta, scaleDelta, 1);
      final Matrix4 translateToNewFocal = Matrix4.translationValues(currentFocal.dx, currentFocal.dy, 0);

      _matrixNotifier.value = translateToNewFocal
          .multiplied(rotate)
          .multiplied(scale)
          .multiplied(translateToOrigin)
          .multiplied(_anchorMatrix);
    }
  }

  void _onScaleEnd(ScaleEndDetails details) async {
    if (_currentStrokePoints.isNotEmpty && _activePointerCount == 1) {
      if (!_layers[_activeLayerIndex].isVisible) return;

      final newStroke = DrawingStroke(
        points: List.from(_currentStrokePoints),
        color: _getActiveLayerColor(),

        // Use Scaled Width
        width: _getScaledStrokeWidth(),

        isEraser: _currentTool == DrawingTool.eraser,
      );
      setState(() {
        _layers[_activeLayerIndex].strokes.add(newStroke);
        _layers[_activeLayerIndex].redoStrokes.clear();
        _currentStrokePoints = [];
      });
      await _generateThumbnail(_activeLayerIndex);
    }
    _activePointerCount = 0;
  }

  void _undo() async {
    final layer = _layers[_activeLayerIndex];
    if (layer.strokes.isEmpty) return;
    setState(() {
      final stroke = layer.strokes.removeLast();
      layer.redoStrokes.add(stroke);
    });
    _showFeedback("Undo");
    await _generateThumbnail(_activeLayerIndex);
  }

  void _redo() async {
    final layer = _layers[_activeLayerIndex];
    if (layer.redoStrokes.isEmpty) return;
    setState(() {
      final stroke = layer.redoStrokes.removeLast();
      layer.strokes.add(stroke);
    });
    _showFeedback("Redo");
    await _generateThumbnail(_activeLayerIndex);
  }

  @override
  Widget build(BuildContext context) {
    if (_imageAspectRatio == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final activeLayerData = _layers.isNotEmpty ? _layers[_activeLayerIndex] : null;
    final hasLabel = activeLayerData?.labelName != null;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _saveProject();
        if (context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          iconTheme: const IconThemeData(color: Colors.white),
          title: const Text("Annotate", style: TextStyle(color: Colors.white)),
          actions: [
            IconButton(icon: const Icon(Icons.refresh), onPressed: _resetView),
            IconButton(
              icon: const Icon(Icons.undo),
              onPressed: (activeLayerData != null && activeLayerData.strokes.isNotEmpty) ? _undo : null,
              color: (activeLayerData != null && activeLayerData.strokes.isNotEmpty) ? Colors.white : Colors.white38,
            ),
            IconButton(
              icon: const Icon(Icons.redo),
              onPressed: (activeLayerData != null && activeLayerData.redoStrokes.isNotEmpty) ? _redo : null,
              color: (activeLayerData != null && activeLayerData.redoStrokes.isNotEmpty) ? Colors.white : Colors.white38,
            ),
          ],
        ),
        body: Stack(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onScaleStart: _onScaleStart,
              onScaleUpdate: _onScaleUpdate,
              onScaleEnd: _onScaleEnd,
              child: SizedBox(
                width: double.infinity,
                height: double.infinity,
                child: ValueListenableBuilder<Matrix4>(
                  valueListenable: _matrixNotifier,
                  builder: (context, matrix, child) {
                    return Transform(
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
                              ..._layers.asMap().entries.map((entry) {
                                final index = entry.key;
                                final layer = entry.value;

                                if (!layer.isVisible) return const SizedBox.shrink();

                                final isActiveLayer = (index == _activeLayerIndex);
                                DrawingStroke? liveStroke;
                                Offset? cursorPosition;

                                if (isActiveLayer && _currentStrokePoints.isNotEmpty) {
                                  liveStroke = DrawingStroke(
                                    points: _currentStrokePoints,
                                    color: _getActiveLayerColor(),
                                    width: _getScaledStrokeWidth(), // Use scaled width for live stroke too
                                    isEraser: _currentTool == DrawingTool.eraser,
                                  );
                                  // Cursor is still in Image Coordinates, painter will scale it
                                  cursorPosition = _currentStrokePoints.last;
                                }

                                return Positioned.fill(
                                  child: Opacity(
                                    opacity: 0.4,
                                    child: ClipRect(
                                      child: CustomPaint(
                                        painter: LayerPainter(
                                          strokes: layer.strokes,
                                          currentStroke: liveStroke,
                                          cursorPosition: cursorPosition,
                                          imageSize: _imageSize, // Pass original image size!
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            Positioned(
              top: 20, left: 0, right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha:0.7),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: hasLabel ? Color(activeLayerData!.labelColor!) : Colors.grey,
                        width: 1
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.circle, color: hasLabel ? Color(activeLayerData!.labelColor!) : Colors.grey, size: 12),
                      const SizedBox(width: 8),
                      Text(
                        hasLabel ? activeLayerData!.labelName! : "No Label Selected",
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
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
              IconButton(
                onPressed: _toggleTool,
                icon: Icon(
                  _currentTool == DrawingTool.brush ? Icons.brush : Icons.cleaning_services,
                  color: _currentTool == DrawingTool.brush ? Colors.blueAccent : Colors.redAccent,
                ),
              ),
              IconButton(
                onPressed: _showSizeSlider,
                icon: Icon(Icons.circle, size: _strokeWidth.clamp(10, 24).toDouble(), color: Colors.white),
              ),
              GestureDetector(
                onTap: _showLayerManager,
                child: Stack(
                  alignment: Alignment.topRight,
                  children: [
                    const Padding(padding: EdgeInsets.all(8.0), child: Icon(Icons.layers, color: Colors.white, size: 28)),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                      child: Text("${_activeLayerIndex + 1}", style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                    )
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- MODAL & SLIDER ---
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
                  width: _strokeWidth, height: _strokeWidth,
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

  // --- LAYER MANAGER ---
  void _showLayerManager() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return FractionallySizedBox(
              heightFactor: 0.5,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Layers", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        IconButton(
                          icon: const Icon(Icons.add, color: Colors.blueAccent),
                          onPressed: () {
                            _addNewLayer();
                            setModalState(() {});
                            setState(() {});
                          },
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
                                _setActiveLayer(index);
                                setModalState(() {});
                                setState(() {});
                              },
                              child: Container(
                                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                padding: const EdgeInsets.only(left: 8, top: 8, bottom: 8),
                                decoration: BoxDecoration(
                                  color: Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                  border: isActive
                                      ? Border.all(color: Colors.blueAccent, width: 2)
                                      : Border.all(color: Colors.grey.withValues(alpha:0.3)),
                                ),
                                child: Row(
                                  children: [
                                    IconButton(
                                      icon: Icon(
                                        layer.isVisible ? Icons.visibility : Icons.visibility_off,
                                        color: layer.isVisible ? Colors.white : Colors.grey,
                                      ),
                                      onPressed: () {
                                        _toggleLayerVisibility(index);
                                        setModalState(() {});
                                        setState(() {});
                                      },
                                    ),
                                    Container(
                                      width: 50, height: 50,
                                      decoration: BoxDecoration(
                                          color: Colors.transparent,
                                          border: Border.all(color: Colors.white)
                                      ),
                                      child: layer.thumbnail != null
                                          ? RawImage(image: layer.thumbnail!)
                                          : null,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(layer.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                          const SizedBox(height: 4),
                                          DropdownButtonHideUnderline(
                                            child: DropdownButton<String>(
                                              isDense: true,
                                              dropdownColor: const Color(0xFF333333),
                                              hint: const Text("Select Label", style: TextStyle(color: Colors.grey, fontSize: 12)),
                                              value: layer.labelName,
                                              icon: const Icon(Icons.arrow_drop_down, color: Colors.grey),
                                              items: availableLabels.map((labelMap) {
                                                return DropdownMenuItem<String>(
                                                  value: labelMap['name'],
                                                  child: Row(
                                                    children: [
                                                      Icon(Icons.circle, color: Color(labelMap['color']), size: 12),
                                                      const SizedBox(width: 8),
                                                      Text(labelMap['name'], style: const TextStyle(color: Colors.white, fontSize: 14)),
                                                    ],
                                                  ),
                                                );
                                              }).toList(),
                                              onChanged: (val) {
                                                if (val != null) {
                                                  final selectedLabel = availableLabels.firstWhere((l) => l['name'] == val);
                                                  _updateLayerLabel(index, val, selectedLabel['color']);
                                                  setModalState(() {});
                                                }
                                              },
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (isActive) const Icon(Icons.check, color: Colors.blueAccent),

                                    PopupMenuButton<String>(
                                      icon: const Icon(Icons.more_vert, color: Colors.white),
                                      color: const Color(0xFF333333),
                                      onSelected: (value) {
                                        if (value == 'clear') {
                                          _clearLayer(index);
                                        } else if (value == 'delete') {
                                          _confirmDeleteLayer(index, setModalState);
                                        }
                                        setModalState(() {});
                                        setState(() {});
                                      },
                                      itemBuilder: (BuildContext context) => [
                                        const PopupMenuItem(
                                          value: 'clear',
                                          child: Row(
                                            children: [
                                              Icon(Icons.cleaning_services, color: Colors.white, size: 20),
                                              SizedBox(width: 10),
                                              Text('Clear Paint', style: TextStyle(color: Colors.white)),
                                            ],
                                          ),
                                        ),
                                        const PopupMenuItem(
                                          value: 'delete',
                                          child: Row(
                                            children: [
                                              Icon(Icons.delete, color: Colors.redAccent, size: 20),
                                              SizedBox(width: 10),
                                              Text('Delete Layer', style: TextStyle(color: Colors.redAccent)),
                                            ],
                                          ),
                                        ),
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
}