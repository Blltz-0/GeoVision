import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geovision/components/class_selector.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import '../../components/class_selector_dropdown.dart';
import '../../functions/metadata_handle.dart';
import 'package:flutter_map_heatmap/flutter_map_heatmap.dart';
import 'dart:math';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'dart:convert'; // For base64 encoding (optional, or just use Uint8List)
import '../../functions/dart_kde.dart';

class MapPage extends StatefulWidget {
  final String projectName;

  const MapPage({
    super.key,
    required this.projectName,
  });

  @override
  State<MapPage> createState() => _MapPageState();
}

enum MapMode {
  markers,       // Red Pins
  localHeatmap,  // Flutter Blob (Offline)
  pythonKDE      // Python Smooth (Online)
}

class _MapPageState extends State<MapPage> {
  List<Map<String, dynamic>> _allRawData = [];
  List<Marker> _markers = [];
  List<WeightedLatLng> _heatmapData = [];
  bool _showHeatmap = false;
  final MapController _mapController = MapController();
  LatLng? _currentLocation;
  DateTimeRange? _selectedDateRange;
  String _filterClass = "All";

  MapMode _currentMode = MapMode.markers;

  @override
  void initState() {
    super.initState();
    _loadData();
    _getCurrentLocation();
  }

  Future<void> _loadData() async {
    final data = await MetadataService.readCsvData(widget.projectName);
    setState(() {
      _allRawData = data;
    });
    // Run the filter (initially, it shows everything)
    _filterMarkers();
  }

  void _filterMarkers() {
    List<Marker> filteredMarkers = [];
    List<WeightedLatLng> heatmapPoints = [];
    List<Marker> tempMarkers = [];

    for (var point in _allRawData) {
      // Parse data
      double lat = point['lat'];
      double lng = point['lng'];
      String imagePath = point['path'];

      // Parse Date
      DateTime? pointDate;
      try {
        pointDate = DateTime.parse(point['time']);
      } catch (e) {
        // If date is broken, skip
        continue;
      }

      // ---------------------------------------------------
      // THE FILTER CHECK
      // ---------------------------------------------------
      if (_selectedDateRange != null) {
        // "Start" is at 00:00:00 of that day
        // "End" needs to be at 23:59:59 of that day to include images taken that night
        DateTime start = _selectedDateRange!.start;
        DateTime end = _selectedDateRange!.end.add(const Duration(days: 1)).subtract(const Duration(seconds: 1));

        // If the photo is BEFORE start or AFTER end, skip it
        if (pointDate.isBefore(start) || pointDate.isAfter(end)) {
          continue;
        }
      }
      // ---------------------------------------------------

      if (lat == 0.0 && lng == 0.0) continue;

      String pointClass = point['class'] ?? "Unclassified";

      if (_filterClass != "All" && pointClass != _filterClass) {
        continue; // Skip if it doesn't match
      }

      filteredMarkers.add(
        Marker(
          point: LatLng(lat, lng),
          width: 40,
          height: 40,
          child: GestureDetector(
            onTap: () => _showImageDialog(imagePath),
            child: const Icon(Icons.location_on, color: Colors.red, size: 40),
          ),
        ),
      );
      heatmapPoints.add(WeightedLatLng(LatLng(lat, lng), 1));
    }

    // Update the map
    setState(() {
      _markers = filteredMarkers;
      _heatmapData = heatmapPoints;
    });
  }

  Future<void> _pickDateRange() async {
    DateTimeRange? newRange = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _selectedDateRange,
      builder: (context, child) {
        // Optional: Custom theme for the calendar
        return Theme(
          data: ThemeData.light().copyWith(
            primaryColor: Colors.blue,
            colorScheme: const ColorScheme.light(primary: Colors.blue),
          ),
          child: child!,
        );
      },
    );

    if (newRange != null) {
      setState(() {
        _selectedDateRange = newRange;
      });
      _filterMarkers();
    }
  }

  String _formatDate(DateTime dt) {
    return "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}";
  }

  Future<void> _getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (kDebugMode) print("Location services are disabled.");
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (kDebugMode) print("Location permissions are denied.");
        return;
      }
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      final LatLng newLocation = LatLng(position.latitude, position.longitude);

      setState(() {
        _currentLocation = newLocation;
        // User marker logic removed
      });

      // Still move the camera to where the user is
      _mapController.move(newLocation, 16.0);

    } catch (e) {
      if (kDebugMode) print("Error getting location: $e");
    }
  }

  Future<void> _loadMarkers() async {
    final data = await MetadataService.readCsvData(widget.projectName);
    List<Marker> loadedMarkers = [];

    for (var point in data) {
      double lat = point['lat'];
      double lng = point['lng'];
      String imagePath = point['path'];

      if (lat == 0.0 && lng == 0.0) continue;

      loadedMarkers.add(
        Marker(
          point: LatLng(lat, lng),
          width: 40,
          height: 40,
          child: GestureDetector(
            onTap: () => _showImageDialog(imagePath),
            child: const Icon(
              Icons.location_on,
              color: Colors.red,
              size: 40,
            ),
          ),
        ),
      );
    }

    setState(() {
      _markers = loadedMarkers;
    });
  }

  void _showImageDialog(String path) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.file(File(path), height: 200, fit: BoxFit.cover),
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Close")
            )
          ],
        ),
      ),
    );
  }

  void _showMapModeModal() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Select Visualization", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),

              // OPTION 1: MARKERS
              ListTile(
                leading: const Icon(Icons.location_on, color: Colors.red),
                title: const Text("Project Markers"),
                subtitle: const Text("Exact locations"),
                trailing: _currentMode == MapMode.markers ? const Icon(Icons.check, color: Colors.blue) : null,
                onTap: () {
                  setState(() => _currentMode = MapMode.markers);
                  Navigator.pop(context);
                },
              ),

              // OPTION 2: LOCAL HEATMAP
              ListTile(
                leading: const Icon(Icons.blur_on, color: Colors.orange),
                title: const Text("Local Density"),
                subtitle: const Text("Offline, Interactive"),
                trailing: _currentMode == MapMode.localHeatmap ? const Icon(Icons.check, color: Colors.blue) : null,
                onTap: () {
                  setState(() => _currentMode = MapMode.localHeatmap);
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            // IMPORTANT: Attach the controller here so _getCurrentLocation can move the map
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
              // ---------------------------------------------
              // LAYER A: LOCAL HEATMAP (Offline)
              // ---------------------------------------------
              if (_showHeatmap)
                HeatMapLayer(
                  heatMapDataSource: InMemoryHeatMapDataSource(data: _heatmapData),
                  heatMapOptions: HeatMapOptions(
                    radius: 50,
                    minOpacity: 0.1,
                    gradient: {0.2: Colors.blue, 0.5: Colors.green, 1.0: Colors.red},
                  ),
                ),
              // ---------------------------------------------
              // LAYER C: MARKERS (Pins)
              // ---------------------------------------------
              if (!_showHeatmap)
                MarkerLayer(markers: _markers),
            ],
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea( // Ensures it doesn't hide behind the Notch/Status bar
              child: Padding(
                padding: const EdgeInsets.all(15.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // BAR 1: "FROM" DATE
                    Expanded(
                      child: _buildDateButton(
                        label: "From",
                        // If no date selected, show "Start", else show date
                        text: _selectedDateRange == null
                            ? "Start Date"
                            : _formatDate(_selectedDateRange!.start),
                        onTap: _pickDateRange,
                      ),
                    ),

                    const SizedBox(width: 10), // Spacing between bars

                    // BAR 2: "TO" DATE
                    Expanded(
                      child: _buildDateButton(
                        label: "To",
                        // If no date selected, show "End", else show date
                        text: _selectedDateRange == null
                            ? "End Date"
                            : _formatDate(_selectedDateRange!.end),
                        onTap: _pickDateRange,
                      ),
                    ),

                    // CLEAR BUTTON (Only shows if filter is active)
                    if (_selectedDateRange != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 10),
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedDateRange = null;
                            });
                            _filterMarkers();
                          },
                          child: Container(
                            height: 45, width: 45,
                            decoration: BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))
                                ]
                            ),
                            child: const Icon(Icons.close, color: Colors.white),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 80, // Move it down below the date bars (adjust as needed)
            left: 0,
            right: 0,
            child: ClassSelectorDropdown(
              // Pass the Project Name
              projectName: widget.projectName,

              // Pass your local state variable
              selectedClass: _filterClass,

              // Define what happens when a button is clicked
              onClassSelected: (String newClass) {
                setState(() {
                  _filterClass = newClass;
                });
                // Important: Re-run your marker filter logic!
                _filterMarkers();
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        shape: const CircleBorder(),
        backgroundColor: Colors.white,
        child: !_showHeatmap ? const Icon(Icons.blur_on, color: Colors.orange) : const Icon(Icons.location_on, color: Colors.red),
        onPressed: () {
          setState(() {
            _showHeatmap = !_showHeatmap;
          });
          final snackBar = SnackBar(
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.all(10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            content: _showHeatmap ? const Text('Showing Heatmap'): const Text('Showing Markers'),
            duration: const Duration(milliseconds: 300), // Optional: Set duration
            );

          // Show the SnackBar using ScaffoldMessenger
          ScaffoldMessenger.of(context).showSnackBar(snackBar);
        },
      ),
    );
  }



  // 3. REUSABLE WIDGET FOR THE ROUNDED BARS
  Widget _buildDateButton({
    required String label,
    required String text,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          color: Colors.white, // White background
          borderRadius: BorderRadius.circular(30), // Fully rounded corners
          boxShadow: [
            // Adds a subtle drop shadow so it pops off the map
            BoxShadow(
              color: Colors.black.withValues(alpha:0.2),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
          border: Border.all(color: Colors.grey.withValues(alpha:0.3)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 15),
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
