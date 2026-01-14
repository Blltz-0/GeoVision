import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';

import '../components/class_creator.dart';
import '../functions/metadata_handle.dart';
import '../components/ellipsis_menu.dart';

// --- ROBUST LOCATION WIDGET (Unchanged) ---
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

// --- EDIT DIALOG (Unchanged) ---
class EditMetadataDialog extends StatefulWidget {
  final String filename;
  final double initialLat;
  final double initialLng;
  final DateTime initialDate;
  final Function(double lat, double lng, DateTime date) onSave;

  const EditMetadataDialog({
    super.key,
    required this.filename,
    required this.initialLat,
    required this.initialLng,
    required this.initialDate,
    required this.onSave,
  });

  @override
  State<EditMetadataDialog> createState() => _EditMetadataDialogState();
}

class _EditMetadataDialogState extends State<EditMetadataDialog> {
  late TextEditingController _latController;
  late TextEditingController _lngController;
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    _latController = TextEditingController(text: widget.initialLat.toString());
    _lngController = TextEditingController(text: widget.initialLng.toString());
    _selectedDate = widget.initialDate;
  }

  @override
  void dispose() {
    _latController.dispose();
    _lngController.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (date == null) return;

    if (!mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedDate),
    );
    if (time == null) return;

    setState(() {
      _selectedDate = DateTime(
          date.year, date.month, date.day, time.hour, time.minute
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Edit Metadata"),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("File: ${widget.filename}", style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 15),

            const Text("Date & Time", style: TextStyle(fontWeight: FontWeight.bold)),
            InkWell(
              onTap: _pickDateTime,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: Colors.grey.shade400))
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("${_selectedDate.year}-${_selectedDate.month}-${_selectedDate.day}   ${_selectedDate.hour}:${_selectedDate.minute.toString().padLeft(2, '0')}"),
                    const Icon(Icons.edit_calendar, size: 20, color: Colors.blue),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 15),

            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _latController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    decoration: const InputDecoration(labelText: "Latitude", border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _lngController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    decoration: const InputDecoration(labelText: "Longitude", border: OutlineInputBorder()),
                  ),
                ),
              ],
            )
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
        ElevatedButton(
            onPressed: () {
              final lat = double.tryParse(_latController.text) ?? widget.initialLat;
              final lng = double.tryParse(_lngController.text) ?? widget.initialLng;
              widget.onSave(lat, lng, _selectedDate);
              Navigator.pop(context);
            },
            child: const Text("Save")
        ),
      ],
    );
  }
}

// --- MAIN IMAGE VIEW ---
class ImageView extends StatefulWidget {
  final List<String> allImagePaths;
  final int initialIndex;
  final String projectName;
  final String projectType;

  // 1. ADD CALLBACK HERE
  final Function(String path)? onAnnotate;

  const ImageView({
    super.key,
    required this.allImagePaths,
    required this.initialIndex,
    required this.projectName,
    required this.projectType,
    this.onAnnotate, // 2. Receive it
  });

  @override
  State<ImageView> createState() => _ImageViewState();
}

class _ImageViewState extends State<ImageView> {
  late PageController _pageController;
  late int _currentIndex;
  late List<String> _currentImagePaths;
  bool _hasChanges = false;
  List<Map<String, dynamic>> _metadataCache = [];
  Map<String, Color> _classColorMap = {};

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _currentImagePaths = List.from(widget.allImagePaths);
    _loadMetadata();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  String _getFilename(String path) {
    return path.split(Platform.pathSeparator).last;
  }

  Future<void> _loadMetadata() async {
    final data = await MetadataService.readCsvData(widget.projectName);
    final classDefs = await MetadataService.getClasses(widget.projectName);

    if (mounted) {
      setState(() {
        _metadataCache = data;
        _classColorMap = {};
        for (var cls in classDefs) {
          int colorInt = cls['color'] ?? 0xFF000000;
          _classColorMap[cls['name']] = Color(colorInt);
        }
      });
    }
  }

  Map<String, dynamic> _getCurrentImageInfo(String imagePath) {
    if (_metadataCache.isEmpty) return {};
    final String targetName = _getFilename(imagePath);
    return _metadataCache.firstWhere(
          (element) {
        String csvPath = element['path']?.toString() ?? "";
        return _getFilename(csvPath) == targetName;
      },
      orElse: () => {},
    );
  }

  void showImageInformation(BuildContext context, String imagePath) {
    final String targetFilename = _getFilename(imagePath);

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return FutureBuilder<List<Map<String, dynamic>>>(
          future: MetadataService.readCsvData(widget.projectName),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const AlertDialog(content: SizedBox(height: 100, child: Center(child: CircularProgressIndicator())));
            }

            Map<String, dynamic> imageInfo = {};
            if (snapshot.hasData) {
              imageInfo = snapshot.data!.firstWhere(
                    (element) => _getFilename(element['path'].toString()) == targetFilename,
                orElse: () => {},
              );
            }

            double lat = imageInfo['lat'] is double
                ? imageInfo['lat']
                : (double.tryParse(imageInfo['lat'].toString()) ?? 0.0);

            double lng = imageInfo['lng'] is double
                ? imageInfo['lng']
                : (double.tryParse(imageInfo['lng'].toString()) ?? 0.0);

            DateTime dt = DateTime.now();
            if (imageInfo['time'] != null) {
              try { dt = DateTime.parse(imageInfo['time']); } catch (_) {}
            }

            return AlertDialog(
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Image Info'),
                  IconButton(
                    icon: const Icon(Icons.edit, color: Colors.blue),
                    tooltip: "Edit Metadata",
                    onPressed: () {
                      Navigator.pop(context);
                      showDialog(
                          context: context,
                          builder: (ctx) => EditMetadataDialog(
                            filename: targetFilename,
                            initialLat: lat,
                            initialLng: lng,
                            initialDate: dt,
                            onSave: (newLat, newLng, newDate) async {
                              await MetadataService.updateImageMetadata(
                                  projectName: widget.projectName,
                                  imagePath: imagePath,
                                  lat: newLat,
                                  lng: newLng,
                                  time: newDate
                              );

                              if (mounted) {
                                setState(() {
                                  _hasChanges = true;
                                  _loadMetadata();
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text("Image & CSV Updated"))
                                );
                              }
                            },
                          )
                      );
                    },
                  )
                ],
              ),
              content: SizedBox(
                height: 180,
                width: double.maxFinite,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Text("File: $targetFilename", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const Divider(),
                    Row(children: [
                      const Icon(Icons.calendar_today, size: 16, color: Colors.blue),
                      const SizedBox(width: 8),
                      Text("${dt.year}-${dt.month}-${dt.day}  ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}"),
                    ]),
                    Row(children: [
                      const Icon(Icons.location_on, size: 16, color: Colors.red),
                      const SizedBox(width: 8),
                      Text("Lat: $lat"),
                    ]),
                    Row(children: [
                      const Icon(Icons.location_on, size: 16, color: Colors.red),
                      const SizedBox(width: 8),
                      Text("Lng: $lng"),
                    ]),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  child: const Text('Close'),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showTaggingSheet() async {
    final currentPath = _currentImagePaths[_currentIndex];
    final classes = await MetadataService.getClasses(widget.projectName);

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              "Assign Class",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 15),
            if (classes.isEmpty)
              const Padding(
                padding: EdgeInsets.all(15),
                child: Text(
                  "No classes defined yet.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: classes.map((cls) => ListTile(
                  leading: CircleAvatar(backgroundColor: Color(cls['color']), radius: 12),
                  title: Text(cls['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                  onTap: () async {
                    String? newPath = await MetadataService.tagImage(
                      widget.projectName,
                      currentPath,
                      cls['name'],
                    );

                    if (!mounted) return;
                    Navigator.pop(context);

                    if (newPath != null) {
                      await FileImage(File(currentPath)).evict();
                      await FileImage(File(newPath)).evict();

                      await ResizeImage(FileImage(File(currentPath)), width: 300).evict();
                      await ResizeImage(FileImage(File(newPath)), width: 300).evict();

                      setState(() {
                        _currentImagePaths[_currentIndex] = newPath;
                        _hasChanges = true;
                        _loadMetadata();
                      });

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text("Renamed & Tagged as '${cls['name']}'")),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Error renaming file.")),
                      );
                    }
                  },
                )).toList(),
              ),
            ),
            const Divider(),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
              icon: const Icon(Icons.add),
              label: const Text("Create New Class"),
              onPressed: () async {
                Navigator.pop(context);
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => CreateClassPage(projectName: widget.projectName)),
                );
                if (mounted) _showTaggingSheet();
              },
            )
          ],
        ),
      ),
    ).whenComplete(() {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.pop(context, _hasChanges);
      },
      child: Scaffold(
        backgroundColor: Colors.black.withValues(alpha: 0.9),
        appBar: AppBar(
          backgroundColor: Colors.black,
          iconTheme: const IconThemeData(color: Colors.white),
          elevation: 0,
          title: Text(
            "${_currentIndex + 1} of ${_currentImagePaths.length}",
            style: const TextStyle(color: Colors.white),
          ),
          actions: [
            EllipsisMenu(
              onInfo: () => showImageInformation(context, _currentImagePaths[_currentIndex]),
              onDelete: () async {
                final navigator = Navigator.of(context);
                final messenger = ScaffoldMessenger.of(context);
                final String currentPath = _currentImagePaths[_currentIndex];

                await MetadataService.deleteImage(
                  projectName: widget.projectName,
                  imagePath: currentPath,
                );

                navigator.pop(true);
                messenger.showSnackBar(const SnackBar(
                  content: Text("Image Deleted"),
                  backgroundColor: Colors.redAccent,
                  duration: Duration(seconds: 1),
                ));
              },
              // onTag removed here
            ),
          ],
        ),
        body: PageView.builder(
          controller: _pageController,
          itemCount: _currentImagePaths.length,
          onPageChanged: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          itemBuilder: (context, index) {
            final imagePath = _currentImagePaths[index];
            final info = _getCurrentImageInfo(imagePath);

            String className = info['class'] ?? "Unclassified";
            Color tagColor = _classColorMap[className] ?? Colors.grey;

            double lat = info['lat'] is double
                ? info['lat']
                : (double.tryParse(info['lat'].toString()) ?? 0.0);

            double lng = info['lng'] is double
                ? info['lng']
                : (double.tryParse(info['lng'].toString()) ?? 0.0);

            String dateString = "--";

            if (info['time'] != null) {
              try {
                final dt = DateTime.parse(info['time']);
                dateString = "${dt.year}-${dt.month}-${dt.day} ${dt.hour}:${dt.minute}";
              } catch (_) {}
            }

            return Column(
              children: [
                Container(
                  height: 100,
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  color: Colors.black54,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _getFilename(imagePath),
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: tagColor.withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              className,
                              style: const TextStyle(color: Colors.white, fontSize: 12),
                            ),
                          )
                        ],
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          const Icon(Icons.calendar_today, color: Colors.white70, size: 14),
                          const SizedBox(width: 5),
                          Text(dateString, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                          const SizedBox(width: 15),
                          const Icon(Icons.location_on, color: Colors.redAccent, size: 14),
                          const SizedBox(width: 5),
                          Expanded(
                            child: LocationDisplay(
                              latitude: lat,
                              longitude: lng,
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: InteractiveViewer(
                    panEnabled: true,
                    boundaryMargin: const EdgeInsets.all(20),
                    minScale: 1,
                    maxScale: 4.0,
                    child: Hero(
                      tag: imagePath,
                      child: Image.file(
                        File(imagePath),
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        // --- MODIFIED FAB LOGIC HERE ---
        floatingActionButton: _buildFab(),
      ),
    );
  }

  // Helper widget to keep build method clean
  Widget? _buildFab() {
    if (widget.projectType == 'segmentation') {
      return FloatingActionButton.extended(
        heroTag: "annotate_fab",
        onPressed: () {
          if (widget.onAnnotate != null) {
            widget.onAnnotate!(_currentImagePaths[_currentIndex]);
          }
        },
        icon: const Icon(Icons.brush),
        label: const Text("Annotate"),
        backgroundColor: Colors.lightGreenAccent,
      );
    } else if (widget.projectType == 'classification') {
      return FloatingActionButton.extended(
        heroTag: "tag_fab",
        onPressed: _showTaggingSheet,
        icon: const Icon(Icons.label),
        label: const Text("Tag Image"),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
      );
    }
    return null;
  }
}