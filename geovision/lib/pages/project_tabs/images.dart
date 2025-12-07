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
  List<File> _imageFiles=[];
  bool _isLoading=true;
  String _filterClass = "All";

  @override
  void initState() {
    super.initState();
    _initPage(); // Load data on startup
  }

  Future<void> _initPage() async {
    // 1. Repair data first
    await MetadataService.syncProjectData(widget.projectName);

    // 2. Then load images
    _loadImages();
  }

  Future<void> _loadImages() async {
    setState(() => _isLoading = true);

    final appDir = await getApplicationDocumentsDirectory();
    final imagesDirPath = '${appDir.path}/projects/${widget.projectName}/images';
    final imagesDir = Directory(imagesDirPath);

    if (await imagesDir.exists()) {
      // 1. LOAD CSV DATA FIRST
      // We need this to know which class belongs to which image
      final csvData = await MetadataService.readCsvData(widget.projectName);

      // 2. Create a "Lookup Map" for speed
      // Key: Filename (e.g., "img_123.jpg"), Value: The Class Name (e.g., "Crack")
      Map<String, String> imageClasses = {};
      for (var row in csvData) {
        String filename = row['path'].split(Platform.pathSeparator).last;
        // Default to "Unclassified" if the class column is missing/empty
        imageClasses[filename] = row['class'] ?? "Unclassified";
      }

      // 3. Get Physical Files
      final allFiles = imagesDir.listSync();

      List<File> validImages = allFiles
          .map((item) => File(item.path))
          .where((item) {
        final ext = item.path.split('.').last.toLowerCase();
        return ext == 'jpg' || ext == 'png' || ext == 'jpeg';
      })
          .toList();

      // 4. APPLY THE FILTER
      if (_filterClass != "All") {
        validImages = validImages.where((file) {
          String filename = file.path.split(Platform.pathSeparator).last;

          // Look up the class in our map. Default to "Unclassified" if not found.
          String fileClass = imageClasses[filename] ?? "Unclassified";

          // Keep file ONLY if the class matches the filter
          return fileClass == _filterClass;
        }).toList();
      }

      // 5. SORT & UPDATE STATE
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
    if (Platform.isAndroid) {
      var status = await Permission.accessMediaLocation.status;
      if (!status.isGranted) {
        status = await Permission.accessMediaLocation.request();
      }

      // Also check standard storage/photos permission if needed
      if (await Permission.photos.request().isDenied) {
        // Handle denied access (optional)
        return;
      }
    }


    final ImagePicker picker = ImagePicker();

    // 1. Pick the Image
    final XFile? pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile == null) return; // User cancelled

    setState(() => _isLoading = true);

    try {
      // 2. Read Metadata (GPS & Date) from the original file
      final exif = await Exif.fromPath(pickedFile.path);
      final latLong = await exif.getLatLong();
      await exif.close();

      // 3. Create a Position object from the EXIF data
      // We fill unknown fields with 0 because we only care about Lat/Lng
      Position? position;
      if (latLong != null) {
        position = Position(
          latitude: latLong.latitude,
          longitude: latLong.longitude,
          timestamp: DateTime.now(),
          accuracy: 0,
          altitude: 0,
          heading: 0,
          speed: 0,
          speedAccuracy: 0,
          altitudeAccuracy: 0,
          headingAccuracy: 0,
        );
      }

      // 4. Prepare Paths
      final appDir = await getApplicationDocumentsDirectory();
      final String fileId = 'img_import_${DateTime.now().millisecondsSinceEpoch}';
      final String newPath = '${appDir.path}/projects/${widget.projectName}/images/$fileId.jpg';

      // 5. Copy File to Project Folder
      await File(pickedFile.path).copy(newPath);

      // 6. Save to CSV
      await MetadataService.saveToCsv(
        projectName: widget.projectName,
        imagePath: newPath,
        position: position, // Pass the extracted position
      );

      // 7. Refresh Grid
      _loadImages();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Image imported successfully!")),
        );
      }

    } catch (e) {
      if (kDebugMode) {
        print("Import Error: $e");
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to import: $e")),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }



  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> gridData = _imageFiles.map((file) {
      return {"path": file.path};
    }).toList();

    return Scaffold(
      body: _isLoading ? const Center(child: CircularProgressIndicator()) : SingleChildScrollView(
        child: Container(
          padding: EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height:20),
              Text('${widget.projectName} Gallery',style: TextStyle(fontSize: 20),textAlign: TextAlign.center,),
              ClassSelectorDropdown(
                // Pass the Project Name
                projectName: widget.projectName,

                // Pass your local state variable
                selectedClass: _filterClass,

                // Define what happens when a button is clicked
                onClassSelected: (String newClass) {
                  setState(() {
                    _filterClass = newClass;
                  });
                  _loadImages();
                },
              ),
              SizedBox(height:20),
              _imageFiles.isEmpty
                  ? const Center(child: Text("No images yet"))
                  : ImageGrid(
                columns: 3,
                itemCount: gridData.length,
                dataList: gridData,
                projectName: widget.projectName,
                onBack: (){
                  _loadImages();
                },
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(onPressed: _importImage, tooltip: 'Import Image', child: Icon(Icons.add)),
    );
  }
}