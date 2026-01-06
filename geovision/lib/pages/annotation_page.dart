import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui; // Needed for PictureRecorder & Image decoding
import 'package:flutter/material.dart';

// --- IMPORTS ---
import '../components/annotation_layer.dart';
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

  // --- IMAGE DIMENSIONS STATE ---
  double? _imageAspectRatio;
  Size? _imageSize; // To help with bounds checking

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

  @override
  void initState() {
    super.initState();
    _layers.add(AnnotationLayer(
      id: DateTime.now().toIso8601String(),
      name: "Layer 1",
    ));
    // 1. Load Image Dimensions immediately
    _loadImageDimensions();
  }

  Future<void> _loadImageDimensions() async {
    final file = File(widget.imagePath);
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
    _matrixNotifier.dispose();
    for (var layer in _layers) {
      layer.thumbnail?.dispose();
    }
    super.dispose();
  }

  void _resetView() {
    _matrixNotifier.value = Matrix4.identity();
  }

  // --- LAYER LOGIC ---
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

  void _updateLayerLabel(int layerIndex, String name, int color) {
    setState(() {
      _layers[layerIndex].labelName = name;
      _layers[layerIndex].labelColor = color;
    });
    _generateThumbnail(layerIndex);
  }

  // --- THUMBNAIL GENERATION ---
  Future<void> _generateThumbnail(int layerIndex) async {
    final layer = _layers[layerIndex];
    if (layer.strokes.isEmpty) {
      setState(() {
        layer.thumbnail?.dispose();
        layer.thumbnail = null;
      });
      return;
    }

    const double size = 100.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size, size));

    // Scale logic: We need to scale the vast image coordinates down to 100x100
    // If we know the image size, we can scale perfectly.
    if (_imageSize != null) {
      final double scaleX = size / _imageSize!.width;
      final double scaleY = size / _imageSize!.height;
      // Use the smaller scale to fit the whole image
      final double scale = scaleX < scaleY ? scaleX : scaleY;
      canvas.scale(scale, scale);
    } else {
      canvas.scale(0.1, 0.1); // Fallback
    }

    final painter = LayerPainter(strokes: layer.strokes);
    painter.paint(canvas, Size.infinite);

    final picture = recorder.endRecording();
    final img = await picture.toImage(size.toInt(), size.toInt());

    setState(() {
      layer.thumbnail?.dispose();
      layer.thumbnail = img;
    });
  }

  // --- TOOL LOGIC ---
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
  }

  // --- GESTURE LOGIC (UPDATED FOR BOUNDS) ---

  // Convert screen point to image-local point AND check bounds
  Offset? _getLocalValidPoint(Offset globalPoint) {
    final RenderBox? box = _imageKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;

    final Offset local = box.globalToLocal(globalPoint);

    // 2. BOUNDS CHECK: Ensure point is strictly inside the image rectangle
    if (local.dx < 0 || local.dy < 0 || local.dx > box.size.width || local.dy > box.size.height) {
      return null;
    }
    return local;
  }

  void _onScaleStart(ScaleStartDetails details) {
    _activePointerCount = details.pointerCount;

    if (_activePointerCount == 1) {
      if (!_layers[_activeLayerIndex].isVisible) return;

      final validPoint = _getLocalValidPoint(details.focalPoint);
      if (validPoint != null) {
        setState(() => _currentStrokePoints = [validPoint]);
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

      final validPoint = _getLocalValidPoint(details.focalPoint);
      if (validPoint != null) {
        setState(() => _currentStrokePoints.add(validPoint));
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
        width: _strokeWidth,
        isEraser: _currentTool == DrawingTool.eraser,
      );

      setState(() {
        _layers[_activeLayerIndex].strokes.add(newStroke);
        _currentStrokePoints = [];
      });

      await _generateThumbnail(_activeLayerIndex);
    }
    _activePointerCount = 0;
  }

  // --- UI ---
  @override
  Widget build(BuildContext context) {
    // Show loader until we know the image size
    if (_imageAspectRatio == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final activeLayerData = _layers[_activeLayerIndex];
    final hasLabel = activeLayerData.labelName != null;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text("Annotate", style: TextStyle(color: Colors.white)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _resetView),
          IconButton(icon: const Icon(Icons.undo), onPressed: () async {
            if (activeLayerData.strokes.isNotEmpty) {
              setState(() => activeLayerData.strokes.removeLast());
              await _generateThumbnail(_activeLayerIndex);
            }
          }),
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
                      // 3. CONSTRAINT: AspectRatio forces the Stack to exactly match the image
                      child: AspectRatio(
                        aspectRatio: _imageAspectRatio!,
                        child: Stack(
                          key: _imageKey,
                          fit: StackFit.expand, // Ensures children fill the aspect ratio box
                          children: [
                            // 1. Image (Fits exactly into the Aspect Ratio)
                            Image.file(File(widget.imagePath), fit: BoxFit.fill),

                            // 2. Layers (Positioned.fill ensures they match the image size exactly)
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
                                  width: _strokeWidth,
                                  isEraser: _currentTool == DrawingTool.eraser,
                                );
                                cursorPosition = _currentStrokePoints.last;
                              }

                              return Positioned.fill(
                                child: Opacity(
                                  opacity: 0.4,
                                  child: ClipRect( // 4. CLIP: Ensures no paint bleeds visually
                                    child: CustomPaint(
                                      painter: LayerPainter(
                                        strokes: layer.strokes,
                                        currentStroke: liveStroke,
                                        cursorPosition: cursorPosition,
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

          // Floating Label
          Positioned(
            top: 20, left: 0, right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: hasLabel ? Color(activeLayerData.labelColor!) : Colors.grey,
                      width: 1
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.circle, color: hasLabel ? Color(activeLayerData.labelColor!) : Colors.grey, size: 12),
                    const SizedBox(width: 8),
                    Text(
                      hasLabel ? activeLayerData.labelName! : "No Label Selected",
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

  // --- UPDATED LAYER MANAGER ---
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
                      // future: MetadataService.getLabels(widget.projectName),
                      future: Future.value([{'name': 'Test', 'color': 0xFFFF0000}, {'name': 'Blue', 'color': 0xFF0000FF}]),
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
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                  border: isActive
                                      ? Border.all(color: Colors.blueAccent, width: 2)
                                      : Border.all(color: Colors.grey.withOpacity(0.3)),
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
                                          ? RawImage(image: layer.thumbnail!, fit: BoxFit.contain)
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