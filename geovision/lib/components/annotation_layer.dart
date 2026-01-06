import 'dart:ui' as ui; // Needed for ui.Image
import 'package:flutter/material.dart';

class DrawingStroke {
  final List<Offset> points;
  final Color color;
  final double width;
  final bool isEraser;

  DrawingStroke({
    required this.points,
    required this.color,
    required this.width,
    this.isEraser = false,
  });
}

class AnnotationLayer {
  String id;
  String name;
  String? labelName;
  int? labelColor;
  List<DrawingStroke> strokes;
  bool isVisible;
  ui.Image? thumbnail; // <--- NEW: Holds the cached mini-image of the layer

  AnnotationLayer({
    required this.id,
    required this.name,
    this.labelName,
    this.labelColor,
    List<DrawingStroke>? strokes,
    this.isVisible = true,
    this.thumbnail,
  }) : strokes = strokes ?? [];
}