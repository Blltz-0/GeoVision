import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';

class LocationDisplay extends StatefulWidget {
  final double latitude;
  final double longitude;
  final TextStyle style;

  const LocationDisplay({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.style,
  });

  @override
  State<LocationDisplay> createState() => _LocationDisplayState();
}

class _LocationDisplayState extends State<LocationDisplay> {
  String _displayText = "Loading...";

  @override
  void initState() {
    super.initState();
    _resolveAddress();
  }

  @override
  void didUpdateWidget(LocationDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.latitude != oldWidget.latitude || widget.longitude != oldWidget.longitude) {
      _resolveAddress();
    }
  }

  Future<void> _resolveAddress() async {
    if (widget.latitude == 0.0 && widget.longitude == 0.0) {
      if (mounted) setState(() => _displayText = "No GPS Data");
      return;
    }

    String latLngString = "${widget.latitude.toStringAsFixed(5)}, ${widget.longitude.toStringAsFixed(5)}";
    if (mounted) setState(() => _displayText = latLngString);

    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
          widget.latitude,
          widget.longitude
      );

      if (placemarks.isNotEmpty && mounted) {
        Placemark place = placemarks[0];
        String part1 = place.locality ?? "";
        String part2 = place.administrativeArea ?? "";
        String part3 = place.country ?? "";

        String finalName = "";
        if (part1.isNotEmpty && part2.isNotEmpty) {
          finalName = "$part1, $part2";
        } else if (part1.isNotEmpty) {
          finalName = "$part1, $part3";
        } else if (part2.isNotEmpty) {
          finalName = "$part2, $part3";
        } else {
          finalName = part3;
        }

        if (finalName.trim().isEmpty || finalName.trim() == ",") {
          finalName = "Unknown Location";
        }

        setState(() => _displayText = finalName);
      }
    } catch (e) {
      debugPrint("⚠️ Geocoding Error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _displayText,
      style: widget.style,
      overflow: TextOverflow.ellipsis,
    );
  }
}