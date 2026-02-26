import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map_heatmap/flutter_map_heatmap.dart';
import 'package:geocoding/geocoding.dart';
import 'dart:ui';
import 'package:flutter/rendering.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:typed_data';

import '../../components/classes/class_selector_dropdown.dart';
import '../../functions/data_service/map_export_service.dart';

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
    if (!mounted) return;
    if (widget.latitude == 0.0 && widget.longitude == 0.0) {
      setState(() => _displayText = "No GPS Data");
      return;
    }

    // Show coordinates while loading
    String latLngString = "${widget.latitude.toStringAsFixed(5)}, ${widget.longitude.toStringAsFixed(5)}";
    setState(() => _displayText = "Resolving... ($latLngString)");

    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(widget.latitude, widget.longitude)
          .timeout(const Duration(seconds: 5));

      if (placemarks.isNotEmpty && mounted) {
        Placemark place = placemarks[0];
        String part1 = place.locality ?? ""; // City
        String part2 = place.administrativeArea ?? ""; // State/Province
        String part3 = place.country ?? "";

        // Intelligent formatting
        List<String> parts = [part1, part2, part3].where((s) => s.isNotEmpty).toList();
        String finalName = parts.take(2).join(", "); // Take first 2 available parts

        if (finalName.trim().isEmpty) finalName = latLngString;

        setState(() => _displayText = finalName);
      }
    } catch (e) {
      if (mounted) setState(() => _displayText = latLngString);
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
  final GlobalKey _mapExportKey = GlobalKey();
  List<Marker> _markers = [];
  List<WeightedLatLng> _heatmapData = [];
  bool _showHeatmap = false;
  final MapController _mapController = MapController();
  LatLng? _currentLocation;

  // Filter State
  DateTimeRange? _selectedDateRange;
  String _filterClass = "All";
  int _heatmapKey = 0; // Forces heatmap rebuild when data changes

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
    _filterMarkers();
  }

  @override
  void didUpdateWidget(MapPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only re-filter if the data reference actually changed
    if (widget.mapData != oldWidget.mapData) {
      _filterMarkers();
    }
  }

  void _filterMarkers() {
    List<Marker> filteredMarkers = [];
    List<WeightedLatLng> heatmapPoints = [];

    for (var point in widget.mapData) {
      // Safety Checks
      double lat = (point['lat'] as num?)?.toDouble() ?? 0.0;
      double lng = (point['lng'] as num?)?.toDouble() ?? 0.0;
      String pointClass = point['class'] ?? "Unclassified";
      String timeStr = point['time'] ?? "";

      // Skip invalid coordinates
      if (lat == 0.0 && lng == 0.0) continue;
      if (lat.abs() > 90 || lng.abs() > 180) continue;

      // 1. DATE FILTER
      if (_selectedDateRange != null && timeStr.isNotEmpty) {
        try {
          DateTime pointDate = DateTime.parse(timeStr).toLocal();

          // Normalize range to include full days
          DateTime start = DateTime(_selectedDateRange!.start.year, _selectedDateRange!.start.month, _selectedDateRange!.start.day);
          DateTime end = DateTime(_selectedDateRange!.end.year, _selectedDateRange!.end.month, _selectedDateRange!.end.day, 23, 59, 59);

          if (pointDate.isBefore(start) || pointDate.isAfter(end)) continue;
        } catch (_) {
          continue; // Skip if date is malformed
        }
      }

      // 2. CLASS FILTER
      if (_filterClass != "All" && pointClass != _filterClass) continue;

      // 3. CREATE MARKER
      // Get class color
      Color markerColor = Colors.red;
      if (widget.projectType == 'classification') {
        final classDef = widget.projectClasses.firstWhere(
                (c) => c['name'] == pointClass,
            orElse: () => {'color': Colors.red.value}
        );
        markerColor = Color(classDef['color']);
      }

      filteredMarkers.add(
        Marker(
          point: LatLng(lat, lng),
          width: 40,
          height: 40,
          child: GestureDetector(
            onTap: () => _showImageDialog(point),
            child: Icon(Icons.location_on, color: markerColor, size: 40),
          ),
        ),
      );

      // 4. CREATE HEATMAP POINT
      heatmapPoints.add(WeightedLatLng(LatLng(lat, lng), 1.0));
    }

    setState(() {
      _markers = filteredMarkers;
      _heatmapData = heatmapPoints;
      _heatmapKey++; // Force update
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
        _mapController.move(newLocation, 15.0);
      }
    } catch (e) {
      debugPrint("Location Error: $e");
    }
  }

  // --- IMAGE DETAIL DIALOG ---
  void _showImageDialog(Map<String, dynamic> pointData) {
    // This 'path' is already reconstructed to the full system path by the Service
    String path = pointData['path'] ?? "";
    String className = pointData['class'] ?? "Unclassified";
    double lat = (pointData['lat'] as num?)?.toDouble() ?? 0.0;
    double lng = (pointData['lng'] as num?)?.toDouble() ?? 0.0;

    // We get the filename just for the UI display
    String filename = p.basename(path);

    String dateString = "Unknown Date";
    if (pointData['time'] != null && pointData['time'].toString().isNotEmpty) {
      try {
        final dt = DateTime.parse(pointData['time']).toLocal();
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
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
                  child: Container(
                    height: 250,
                    width: double.infinity,
                    color: Colors.black12,
                    child: File(path).existsSync()
                        ? Image.file(
                      File(path),
                      fit: BoxFit.cover,
                      // Adding a cache error handler is good practice
                      errorBuilder: (context, error, stackTrace) => const Center(child: Icon(Icons.broken_image, size: 50)),
                    )
                        : const Center(child: Icon(Icons.broken_image, color: Colors.grey, size: 50)),
                  ),
                ),
                Positioned(
                  right: 5, top: 5,
                  child: CircleAvatar(
                    backgroundColor: Colors.black54,
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white, size: 20),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(filename, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const Divider(),
                  if (widget.projectType == "classification") ...[
                    _buildInfoRow(Icons.label, "Class", className),
                    const SizedBox(height: 8),
                  ],
                  _buildInfoRow(Icons.calendar_today, "Date", dateString),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.location_on, size: 18, color: Colors.grey),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Location:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
                            LocationDisplay(latitude: lat, longitude: lng, style: const TextStyle(fontSize: 14)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
            Text(value, style: const TextStyle(fontSize: 14)),
          ],
        ),
      ],
    );
  }

  // --- DATE PICKER LOGIC ---
  Future<void> _pickDateRange() async {
    // 1. CONVERT DATA: Extract unique "YYYY-MM-DD" strings from GeoJSON
    final Set<String> validDates = widget.mapData
        .map((point) => point['time']?.toString()) // Extract time strings
        .where((time) => time != null && time.isNotEmpty) // Remove nulls
        .map((time) {
      try {
        final dt = DateTime.parse(time!).toLocal();
        return "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}";
      } catch (_) {
        return null;
      }
    })
        .whereType<String>() // Remove failed parses
        .toSet();

    debugPrint("📅 Valid Dates Found: ${validDates.length}");

    bool isDaySelectable(DateTime day) {
      if (validDates.isEmpty) return true; // If no data, allow all

      final String key = "${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}";
      return validDates.contains(key);
    }

    // 3. SHOW PICKER
    final DateTimeRange? newRange = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _selectedDateRange,

      selectableDayPredicate: (DateTime day, DateTime? start, DateTime? end) {
        return isDaySelectable(day);
      },

      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Colors.blue,
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (newRange != null) {
      setState(() => _selectedDateRange = newRange);
      _filterMarkers();
    }
  }

  Widget _buildDateButton({required String label, required String text, required VoidCallback onTap}) {
    return Material(
      color: Colors.white,
      elevation: 2,
      borderRadius: BorderRadius.circular(25),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(25),
        child: Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          alignment: Alignment.centerLeft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(label.toUpperCase(), style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleFilteredMapExport() async {
    // 1. Check if there is data to export
    if (_markers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No points match current filters")),
      );
      return;
    }

    // 2. Extract coordinates
    // We explicitly cast to ensure the Service receives the expected format
    List<Map<String, double>> filteredCoords = _markers.map((m) => {
      'lat': m.point.latitude,
      'lng': m.point.longitude,
    }).toList();

    // 3. Show loading feedback
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
            SizedBox(width: 16),
            Text("Generating heatmap..."),
          ],
        ),
        duration: Duration(seconds: 2), // Auto-hide if it hangs
      ),
    );

    try {
      debugPrint("🚀 Starting Export for ${filteredCoords.length} points...");

      // 4. Call the service
      await MapExportService.shareFilteredMap(
        projectName: widget.projectName,
        points: filteredCoords,
      );

      debugPrint("✅ Export function completed successfully.");

    } catch (e, stackTrace) {
      // 5. CATCH & DISPLAY ERRORS
      debugPrint("❌ Export Error: $e");
      debugPrint("Stacktrace: $stackTrace");

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Export Failed: $e"),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _downloadMapStatus() async {
    try {
      // Find the RepaintBoundary in the widget tree
      RenderRepaintBoundary? boundary =
      _mapExportKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;

      if (boundary == null) return;

      // Capture the current pixels on screen
      var image = await boundary.toImage(pixelRatio: 3.0); // 3.0 for High Definition
      ByteData? byteData = await image.toByteData(format: ImageByteFormat.png);
      Uint8List pngBytes = byteData!.buffer.asUint8List();

      // Save to a temporary file
      final tempDir = await getTemporaryDirectory();
      final file = await File(
          '${tempDir.path}/map_snapshot_${DateTime.now().millisecondsSinceEpoch}.png'
      ).create();
      await file.writeAsBytes(pngBytes);

      // Share the screenshot
      await Share.shareXFiles(
          [XFile(file.path)],
          text: 'GeoVision Map Snapshot: ${widget.projectName}'
      );
    } catch (e) {
      debugPrint("❌ Screenshot Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to capture map view")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Count stats
    int count = _markers.length;
    String statusText = (count<1) ? "$count Image":"$count Images";

    return Scaffold(
      body: Stack(
        children: [
          RepaintBoundary(
            key: _mapExportKey,
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _currentLocation ?? const LatLng(16.6159, 120.3209),
                initialZoom: 13.0,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.geovision',
                ),
                if (_showHeatmap && _heatmapData.isNotEmpty)
                  HeatMapLayer(
                    key: ValueKey("heatmap_$_heatmapKey"), // Unique key forces rebuild on data change
                    heatMapDataSource: InMemoryHeatMapDataSource(data: _heatmapData),
                    heatMapOptions: HeatMapOptions(
                      radius: 35,
                      minOpacity: 0.2,
                      gradient: {
                        0.2: Colors.blue,
                        0.5: Colors.lime,
                        0.8: Colors.orange,
                        1.0: Colors.red
                      },
                    ),
                  ),
                if (!_showHeatmap)
                  MarkerLayer(markers: _markers),
              ],
            ),
          ),

          // --- TOP CONTROLS ---
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  children: [
                    // DATE FILTER BAR
                    Row(
                      children: [
                        Expanded(child: _buildDateButton(
                            label: "Start Date",

                            text: _selectedDateRange == null ? "Any" : "${_selectedDateRange!.start.month}/${_selectedDateRange!.start.day}/${_selectedDateRange!.start.year}",
                            onTap: _pickDateRange
                        )),
                        const SizedBox(width: 8),
                        Expanded(child: _buildDateButton(
                            label: "End Date",
                            text: _selectedDateRange == null ? "Any" : "${_selectedDateRange!.end.month}/${_selectedDateRange!.end.day}/${_selectedDateRange!.end.year}",
                            onTap: _pickDateRange
                        )),
                        if(_selectedDateRange != null)
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: CircleAvatar(
                              backgroundColor: Colors.red.shade100,
                              child: IconButton(
                                icon: const Icon(Icons.close, color: Colors.red),
                                onPressed: (){ setState(() => _selectedDateRange = null); _filterMarkers(); },
                              ),
                            ),
                          )
                      ],
                    ),

                    const SizedBox(height: 10),

                    // CLASS FILTER (If Classification)
                    if (widget.projectType == 'classification')
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                        ),
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        /*FloatingActionButton.small(
                          heroTag: 'fab_download_screen',
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black87,
                          shape: const StadiumBorder(),
                          onPressed: _downloadMapStatus,
                          child: Icon(Icons.camera_alt),
                        ),*/
                        const SizedBox(height: 12),
                        FloatingActionButton.small(
                          heroTag: 'fab_render_map',
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black87,
                          shape: const StadiumBorder(),
                          onPressed: _handleFilteredMapExport,
                          child: Icon(Icons.download_for_offline),
                        ),
                        const SizedBox(height: 12),

                      ],
                    )
                  ],
                ),
              ),
            ),
          ),

          // --- STATUS CHIP ---
          Positioned(
            bottom: 16 + MediaQuery.of(context).padding.bottom, // Adjusts for system nav bar
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                      Icons.image,
                      size: 16,
                      color: Colors.blueGrey
                  ),
                  const SizedBox(width: 8),
                  Text(
                    statusText,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // --- EMPTY STATE ---
          if (_markers.isEmpty && _heatmapData.isEmpty)
            Center(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(16)
                ),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.filter_alt_off, size: 48, color: Colors.grey),
                    SizedBox(height: 10),
                    Text("No images match filters", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                  ],
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_map_toggle',
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        shape: const StadiumBorder(),
        elevation: 4,
        icon: Icon(_showHeatmap ? Icons.pin_drop : Icons.blur_on,
            color: _showHeatmap ? Colors.red : Colors.orange),
        label: Text(_showHeatmap ? "Show Markers" : "Show Heatmap"),
        onPressed: () => setState(() => _showHeatmap = !_showHeatmap),
      ),
    );
  }
}