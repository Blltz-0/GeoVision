import 'dart:ui' as ui;
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

  DrawingStroke copyWith({
    List<Offset>? points,
    Color? color,
    double? width,
    bool? isEraser,
  }) {
    return DrawingStroke(
      points: points ?? this.points,
      color: color ?? this.color,
      width: width ?? this.width,
      isEraser: isEraser ?? this.isEraser,
    );
  }

  // --- SERIALIZATION ---
  Map<String, dynamic> toJson() {
    return {
      'p': points.map((e) => [e.dx, e.dy]).toList(),
      'c': color.toARGB32(),
      'w': width,
      'e': isEraser,
    };
  }

  factory DrawingStroke.fromJson(Map<String, dynamic> json) {
    return DrawingStroke(
      points: (json['p'] as List)
          .map((p) => Offset((p[0] as num).toDouble(), (p[1] as num).toDouble()))
          .toList(),
      color: Color(json['c']),
      width: (json['w'] as num).toDouble(),
      isEraser: json['e'] ?? false,
    );
  }
}

class AnnotationLayer {
  String id;
  String name;
  String? labelName;
  int? labelColor;
  List<DrawingStroke> strokes;
  List<DrawingStroke> redoStrokes = [];
  bool isVisible;
  ui.Image? thumbnail;

  AnnotationLayer({
    required this.id,
    required this.name,
    this.labelName,
    this.labelColor,
    List<DrawingStroke>? strokes,
    this.isVisible = true,
    this.thumbnail,
  }) : strokes = strokes ?? [];

  // --- SERIALIZATION ---
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'labelName': labelName,
      'labelColor': labelColor,
      'strokes': strokes.map((s) => s.toJson()).toList(),
      'isVisible': isVisible,
    };
  }

  factory AnnotationLayer.fromJson(Map<String, dynamic> json) {
    return AnnotationLayer(
      id: json['id'],
      name: json['name'],
      labelName: json['labelName'],
      labelColor: json['labelColor'],
      isVisible: json['isVisible'] ?? true,
      strokes: (json['strokes'] as List).map((s) => DrawingStroke.fromJson(s)).toList(),
    );
  }
}