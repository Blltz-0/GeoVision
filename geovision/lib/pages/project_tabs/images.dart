import 'dart:convert'; // ✅ NEEDED FOR JSON
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geovision/components/class_selector_dropdown.dart';
import 'package:image_picker/image_picker.dart';
import 'package:native_exif/native_exif.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geovision/components/class_selector.dart';

import '../../components/image_grid.dart';
import '../../functions/metadata_handle.dart';

class ImagesPage extends StatefulWidget {
  final String projectName;

  const ImagesPage({
    super.key,
    required this.projectName,
  });

  @override
  State<ImagesPage> createState() => _ImagesPageState();
}

class _ImagesPageState extends State<ImagesPage> {
  List<File> _imageFiles = [];
  bool _isLoading = true;
  String _filterClass = "All";

  // ✅ 1. STORE RAW CLASS DATA (For Colors)
  List<dynamic> _projectClasses = [];

  // ✅ 2. STORE FILE->LABEL MAP (To know which image is what)
  Map<String, String> _cachedLabelMap = {};

  @override
  void initState() {
    super.initState();
    _initPage();
  }

  Future<void> _initPage() async {
    await MetadataService.syncProjectData(widget.projectName);

    // ✅ Load Colors and Images
    await _loadClassColors();
    await _loadImages();
  }

  // ✅ NEW: Read classes.json so we have the colors
  Future<void> _loadClassColors() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final classFile = File('${appDir.path}/projects/${widget.projectName}/classes.json');

      if (await classFile.exists()) {
        String jsonString = await classFile.readAsString();
        setState(() {
          _projectClasses = jsonDecode(jsonString); // Raw list of maps
        });
      }
    } catch (e) {
      if (kDebugMode) print("Error loading classes: $e");
    }
  }

  Future<void> _loadImages() async {
    setState(() => _isLoading = true);

    final appDir = await getApplicationDocumentsDirectory();
    final imagesDirPath = '${appDir.path}/projects/${widget.projectName}/images';
    final imagesDir = Directory(imagesDirPath);

    if (await imagesDir.exists()) {
      // 1. LOAD CSV DATA
      final csvData = await MetadataService.readCsvData(widget.projectName);

      // 2. Build Lookup Map
      Map<String, String> tempMap = {};
      for (var row in csvData) {
        String filename = row['path'].split(Platform.pathSeparator).last;
        tempMap[filename] = row['class'] ?? "Unclassified";
      }

      // ✅ Save this map to state so build() can use it later
      _cachedLabelMap = tempMap;

      // 3. Get Physical Files
      final allFiles = imagesDir.listSync();

      List<File> validImages = allFiles
          .map((item) => File(item.path))
          .where((item) {
        final ext = item.path.split('.').last.toLowerCase();
        return ext == 'jpg' || ext == 'png' || ext == 'jpeg';
      })
          .toList();

      // 4. APPLY FILTER
      if (_filterClass != "All") {
        validImages = validImages.where((file) {
          String filename = file.path.split(Platform.pathSeparator).last;
          // Use the map we just built
          String fileClass = _cachedLabelMap[filename] ?? "Unclassified";
          return fileClass == _filterClass;
        }).toList();
      }

      // 5. SORT
      validImages.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));

      setState(() {
        _imageFiles = validImages;
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _importImage() async {
    // ... (Your existing permission logic) ...
    if (Platform.isAndroid) {
      var status = await Permission.accessMediaLocation.status;
      if (!status.isGranted) status = await Permission.accessMediaLocation.request();
      if (await Permission.photos.request().isDenied) return;
    }

    final ImagePicker picker = ImagePicker();
    final XFile? pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile == null) return;

    setState(() => _isLoading = true);

    try {
      // ... (Your existing EXIF logic) ...
      final exif = await Exif.fromPath(pickedFile.path);
      final latLong = await exif.getLatLong();
      await exif.close();

      Position? position;
      if (latLong != null) {
        position = Position(
          latitude: latLong.latitude,
          longitude: latLong.longitude,
          timestamp: DateTime.now(),
          accuracy: 0, altitude: 0, heading: 0, speed: 0, speedAccuracy: 0, altitudeAccuracy: 0, headingAccuracy: 0,
        );
      }

      final appDir = await getApplicationDocumentsDirectory();
      final String fileId = 'img_import_${DateTime.now().millisecondsSinceEpoch}';
      final String newPath = '${appDir.path}/projects/${widget.projectName}/images/$fileId.jpg';

      await File(pickedFile.path).copy(newPath);

      await MetadataService.saveToCsv(
        projectName: widget.projectName,
        imagePath: newPath,
        position: position,
      );

      // Reload to update grid
      _loadImages();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Image imported successfully!")),
        );
      }

    } catch (e) {
      if (kDebugMode) print("Import Error: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // ✅ 3. PREPARE GRID DATA WITH LABELS
    // We map the physical file list to a Map containing path AND label
    final List<Map<String, dynamic>> gridData = _imageFiles.map((file) {
      String filename = file.path.split(Platform.pathSeparator).last;
      return {
        "path": file.path,
        "label": _cachedLabelMap[filename], // Pass the class string here!
      };
    }).toList();

    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        child: Container(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              Text(
                '${widget.projectName} Gallery',
                style: const TextStyle(fontSize: 20),
                textAlign: TextAlign.center,
              ),
              ClassSelectorDropdown(
                projectName: widget.projectName,
                selectedClass: _filterClass,
                onClassSelected: (String newClass) {
                  setState(() {
                    _filterClass = newClass;
                  });
                  _loadImages();
                },
              ),
              const SizedBox(height: 20),
              _imageFiles.isEmpty
                  ? const Center(child: Text("No images yet"))
                  : ImageGrid(
                columns: 3,
                itemCount: gridData.length,
                dataList: gridData,
                projectName: widget.projectName,
                onBack: () {
                  _loadImages();
                  _loadClassColors(); // Refresh colors too if they changed
                },
                // ✅ 4. PASS THE RAW CLASS LIST
                projectClasses: _projectClasses,
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _importImage,
        tooltip: 'Import Image',
        child: const Icon(Icons.add),
      ),
    );
  }
}