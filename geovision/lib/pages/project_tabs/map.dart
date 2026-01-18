import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map_heatmap/flutter_map_heatmap.dart';
import 'package:geocoding/geocoding.dart'; // Required for address resolution

import '../../components/class_selector_dropdown.dart';

// --- HELPER WIDGET: DISPLAYS ADDRESS OR LAT/LNG ---
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
  String _displayText = "Loading address...";

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

    // Default to Lat/Lng while loading or on error
    String latLngString = "${widget.latitude.toStringAsFixed(5)}, ${widget.longitude.toStringAsFixed(5)}";
    if (mounted) setState(() => _displayText = latLngString);

    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(widget.latitude, widget.longitude);

      if (placemarks.isNotEmpty && mounted) {
        Placemark place = placemarks[0];
        String part1 = place.locality ?? "";
        String part2 = place.administrativeArea ?? "";
        String part3 = place.country ?? "";

        String finalName = "";
        if (part1.isNotEmpty && part2.isNotEmpty) {
          finalName = "$part1, $part2";
        } else if (part1.isNotEmpty) {finalName = "$part1, $part3";}
        else if (part2.isNotEmpty) {finalName = "$part2, $part3";}
        else {finalName = part3;}

        if (finalName.trim().isEmpty || finalName.trim() == ",") finalName = "Unknown Location";

        setState(() => _displayText = finalName);
      }
    } catch (e) {
      // Keep showing Lat/Lng on error
    }
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _displayText,
      style: widget.style,
      overflow: TextOverflow.ellipsis,
      maxLines: 2,
    );
  }
}

// --- MAIN MAP PAGE ---
class MapPage extends StatefulWidget {
  final String projectName;
  final List<Map<String, dynamic>> mapData;
  final List<dynamic> projectClasses;
  final VoidCallback? onClassesUpdated;
  final String projectType;

  const MapPage({
    super.key,
    required this.projectName,
    required this.mapData,
    required this.projectClasses,
    required this.projectType,
    this.onClassesUpdated,
  });

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  // UI State
  List<Marker> _markers = [];
  List<WeightedLatLng> _heatmapData = [];
  bool _showHeatmap = false;
  final MapController _mapController = MapController();
  LatLng? _currentLocation;

  // Filter State
  DateTimeRange? _selectedDateRange;
  String _filterClass = "All";
  int _heatmapKey = 0;

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
    _filterMarkers();
  }

  @override
  void didUpdateWidget(MapPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.mapData != oldWidget.mapData) {
      _filterMarkers();
    }
  }

  void _filterMarkers() {
    List<Marker> filteredMarkers = [];
    List<WeightedLatLng> heatmapPoints = [];

    for (var point in widget.mapData) {
      double lat = point['lat'] ?? 0.0;
      double lng = point['lng'] ?? 0.0;
      // String imagePath = point['path'] ?? ""; // Not needed here anymore, passed in object
      String pointClass = point['class'] ?? "Unclassified";
      String timeStr = point['time'] ?? "";

      if (lat == 0.0 && lng == 0.0) continue;

      // 1. DATE FILTER
      if (_selectedDateRange != null && timeStr.isNotEmpty) {
        try {
          DateTime pointDate = DateTime.parse(timeStr);
          DateTime start = _selectedDateRange!.start;
          DateTime end = _selectedDateRange!.end.add(const Duration(days: 1)).subtract(const Duration(seconds: 1));

          if (pointDate.isBefore(start) || pointDate.isAfter(end)) {
            continue;
          }
        } catch (e) {
          // ignore error
        }
      }

      // 2. CLASS FILTER (Only apply if not All)
      if (_filterClass != "All" && pointClass != _filterClass) {
        continue;
      }

      // 3. CREATE MARKER
      filteredMarkers.add(
        Marker(
          point: LatLng(lat, lng),
          width: 40,
          height: 40,
          child: GestureDetector(
            // UPDATED: Pass the entire point object to the dialog
            onTap: () => _showImageDialog(point),
            child: const Icon(Icons.location_on, color: Colors.red, size: 40),
          ),
        ),
      );

      // 4. CREATE HEATMAP POINT
      heatmapPoints.add(WeightedLatLng(LatLng(lat, lng), 1));
    }

    setState(() {
      _markers = filteredMarkers;
      _heatmapData = heatmapPoints;
      _heatmapKey++;
    });
  }

  Future<void> _getCurrentLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return;
    }

    try {
      final position = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
      final LatLng newLocation = LatLng(position.latitude, position.longitude);

      if (mounted) {
        setState(() => _currentLocation = newLocation);
        _mapController.move(newLocation, 16.0);
      }
    } catch (e) {
      debugPrint("Location Error: $e");
    }
  }

  // --- UPDATED DIALOG: SHOWS DETAILS ---
  void _showImageDialog(Map<String, dynamic> pointData) {
    String path = pointData['path'] ?? "";
    String className = pointData['class'] ?? "Unclassified";
    double lat = pointData['lat'] ?? 0.0;
    double lng = pointData['lng'] ?? 0.0;
    String filename = path.split(Platform.pathSeparator).last;

    // Parse Date
    String dateString = "Unknown Date";
    if (pointData['time'] != null) {
      try {
        final dt = DateTime.parse(pointData['time']);
        dateString = "${dt.year}-${dt.month}-${dt.day} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}";
      } catch (_) {}
    }

    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. IMAGE AREA
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
              child: Container(
                height: 250,
                color: Colors.black12,
                child: File(path).existsSync()
                    ? Image.file(File(path), fit: BoxFit.cover)
                    : const Center(child: Icon(Icons.broken_image, color: Colors.grey)),
              ),
            ),

            // 2. INFO AREA
            Padding(
              padding: const EdgeInsets.all(15.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(filename, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 10),

                  // Class Row
                  if (widget.projectType == "classification")
                    Row(
                      children: [
                      const Icon(Icons.label, size: 16, color: Colors.blue),
                      const SizedBox(width: 8),
                      Text("Class: $className", style: const TextStyle(fontSize: 14)),
                      ],
                    ),
                  const SizedBox(height: 5),

                  // Date Row
                  Row(
                    children: [
                      const Icon(Icons.calendar_today, size: 16, color: Colors.blue),
                      const SizedBox(width: 8),
                      Text(dateString, style: const TextStyle(fontSize: 14)),
                    ],
                  ),
                  const SizedBox(height: 5),

                  // Location Row (Using the Helper Widget)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.location_on, size: 16, color: Colors.red),
                      const SizedBox(width: 8),
                      Expanded(
                        child: LocationDisplay(
                            latitude: lat,
                            longitude: lng,
                            style: const TextStyle(fontSize: 14)
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // 3. CLOSE BUTTON
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Close"),
            ),
            const SizedBox(height: 5),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDateRange() async {
    DateTimeRange? newRange = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _selectedDateRange,
    );
    if (newRange != null) {
      setState(() => _selectedDateRange = newRange);
      _filterMarkers();
    }
  }

  Widget _buildDateButton({required String label, required String text, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 15),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
              Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            ]
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentLocation ?? const LatLng(16.6159, 120.3209),
              initialZoom: 14.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.geovision',
              ),
              if (_showHeatmap && _heatmapData.isNotEmpty)
                HeatMapLayer(
                  key: ValueKey(_heatmapKey),
                  heatMapDataSource: InMemoryHeatMapDataSource(data: _heatmapData),
                  heatMapOptions: HeatMapOptions(
                    radius: 50,
                    minOpacity: 0.1,
                    gradient: {0.2: Colors.blue, 0.5: Colors.green, 1.0: Colors.red},
                  ),
                )
              else if (!_showHeatmap)
                MarkerLayer(markers: _markers),
            ],
          ),

          // --- OVERLAYS ---
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(15.0),
                child: Row(
                  children: [
                    Expanded(child: _buildDateButton(
                        label: "From",
                        text: _selectedDateRange == null ? "Start" : "${_selectedDateRange!.start.month}/${_selectedDateRange!.start.day}",
                        onTap: _pickDateRange
                    )),
                    const SizedBox(width: 10),
                    Expanded(child: _buildDateButton(
                        label: "To",
                        text: _selectedDateRange == null ? "End" : "${_selectedDateRange!.end.month}/${_selectedDateRange!.end.day}",
                        onTap: _pickDateRange
                    )),
                    if(_selectedDateRange != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 10),
                        child: GestureDetector(
                          onTap: (){ setState(() => _selectedDateRange = null); _filterMarkers(); },
                          child: Container(
                            height: 45, width: 45, decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                            child: const Icon(Icons.close, color: Colors.white),
                          ),
                        ),
                      )
                  ],
                ),
              ),
            ),
          ),

          // --- CLASS SELECTOR DROPDOWN (ONLY FOR CLASSIFICATION) ---
          if (widget.projectType == 'classification')
            Positioned(
              top: 80, left: 0, right: 0,
              child: ClassSelectorDropdown(
                projectName: widget.projectName,
                selectedClass: _filterClass,
                classes: widget.projectClasses,
                onClassAdded: widget.onClassesUpdated,
                onClassSelected: (String newClass) {
                  setState(() => _filterClass = newClass);
                  _filterMarkers();
                },
              ),
            ),

          // --- EMPTY STATE INDICATOR ---
          if (_markers.isEmpty && _heatmapData.isEmpty)
            Positioned(
              bottom: 100,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20)
                  ),
                  child: const Text(
                    "No images found for this date/class",
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
            )
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_map',
        shape: const StadiumBorder(),
        backgroundColor: Colors.white,
        label: Text(_showHeatmap ? "Show Markers" : "Show Heatmap"),
        icon: Icon(_showHeatmap ? Icons.location_on : Icons.blur_on, color: _showHeatmap ? Colors.red : Colors.orange),
        onPressed: () {
          setState(() => _showHeatmap = !_showHeatmap);
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              duration: const Duration(milliseconds: 700),
              content: Text(_showHeatmap ? "Showing Heatmap" : "Showing Markers"),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        },
      ),
    );
  }
}