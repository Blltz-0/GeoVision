import 'dart:io';
import 'package:flutter/material.dart';

class AnnotationPage extends StatefulWidget {
  final String imagePath;

  const AnnotationPage({
    super.key,
    required this.imagePath,
  });

  @override
  State<AnnotationPage> createState() => _AnnotationPageState();
}

class _AnnotationPageState extends State<AnnotationPage> {
  // The transformation matrix that holds scale, rotation, and translation
  final ValueNotifier<Matrix4> _matrixNotifier = ValueNotifier(Matrix4.identity());

  // --- ANCHOR STATE ---
  // We record these values when the 2-finger gesture starts (or re-starts)
  Matrix4 _anchorMatrix = Matrix4.identity();
  Offset _anchorFocalPoint = Offset.zero;
  double _anchorScale = 1.0;
  double _anchorRotation = 0.0;

  // Track pointer count to detect 1->2 finger transitions
  int _activePointerCount = 0;

  @override
  void dispose() {
    _matrixNotifier.dispose();
    super.dispose();
  }

  void _resetView() {
    _matrixNotifier.value = Matrix4.identity();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text("Annotate", style: TextStyle(color: Colors.white)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: "Reset View",
            onPressed: _resetView,
          ),
          IconButton(
            icon: const Icon(Icons.undo),
            tooltip: "Save (Placeholder)",
            onPressed: () {
            },
          ),
          IconButton(
            icon: const Icon(Icons.redo),
            tooltip: "Save (Placeholder)",
            onPressed: () {
            },
          )
        ],
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,

        onScaleStart: (details) {
          // Reset state when a new gesture chain begins
          _activePointerCount = details.pointerCount;
          _anchorMatrix = _matrixNotifier.value.clone();
          _anchorFocalPoint = details.localFocalPoint;
          _anchorScale = 1.0;
          _anchorRotation = 0.0;
        },

        onScaleUpdate: (details) {
          // 1. RE-ANCHOR if the number of fingers changes.
          //    (e.g. user puts down a 2nd finger, or lifts one)
          if (_activePointerCount != details.pointerCount) {
            _activePointerCount = details.pointerCount;
            _anchorMatrix = _matrixNotifier.value.clone();
            _anchorFocalPoint = details.localFocalPoint;

            // We must latch the current gesture values to calculate deltas later
            _anchorScale = details.scale;
            _anchorRotation = details.rotation;
          }

          // 2. STRICTLY IGNORE if less than 2 fingers
          if (_activePointerCount < 2) {
            return;
          }

          // 3. Calculate the Deltas
          //    How much has the gesture changed since we "anchored" the state?
          final double scaleDelta = details.scale / _anchorScale;
          final double rotationDelta = details.rotation - _anchorRotation;

          // The current center point of the two fingers
          final Offset currentFocal = details.localFocalPoint;

          // 4. THE MATH (Pivot-Anchor Logic)
          //    We want to transform the image such that the point that WAS at
          //    _anchorFocalPoint is now at currentFocal, rotated & scaled.

          // A. Move the anchor point to (0,0)
          final Matrix4 translateToOrigin = Matrix4.translationValues(
              -_anchorFocalPoint.dx,
              -_anchorFocalPoint.dy,
              0
          );

          // B. Rotate and Scale around (0,0)
          final Matrix4 rotate = Matrix4.rotationZ(rotationDelta);
          final Matrix4 scale = Matrix4.diagonal3Values(scaleDelta, scaleDelta, 1);

          // C. Move (0,0) to the NEW focal point
          final Matrix4 translateToNewFocal = Matrix4.translationValues(
              currentFocal.dx,
              currentFocal.dy,
              0
          );

          // Combine: T_new * (Rotate * Scale) * T_origin
          // Note: Matrix multiplication happens Right-to-Left conceptually
          final Matrix4 transform = translateToNewFocal
              .multiplied(rotate)
              .multiplied(scale)
              .multiplied(translateToOrigin);

          // Apply this transformation to the original saved matrix
          final Matrix4 finalMatrix = transform.multiplied(_anchorMatrix);

          _matrixNotifier.value = finalMatrix;
        },

        child: ClipRect(
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
                    child: Image.file(
                      File(widget.imagePath),
                      fit: BoxFit.contain,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
      bottomNavigationBar: BottomAppBar(
        color: Colors.black,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
                onPressed: () => { },
                icon: const Icon(Icons.brush_rounded, color: Colors.white)
            ),
            IconButton(
                onPressed: () => { },
                icon: const Icon(Icons.circle, color: Colors.white)
            ),
            IconButton(
                onPressed: () => { },
                icon: const Icon(Icons.layers, color: Colors.white)
            ),
          ],
        )
      )
    );
  }
}