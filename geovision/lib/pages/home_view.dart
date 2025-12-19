import 'dart:convert'; // ✅ Required for JSON
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:geovision/pages/project_container.dart';
import '../components/image_grid.dart';
import '../functions/metadata_handle.dart';

class HomeViewPage extends StatefulWidget {
  final String title; // This acts as the projectName

  const HomeViewPage({
    super.key,
    required this.title,
  });

  @override
  State<HomeViewPage> createState() => _HomeViewPageState();
}

class _HomeViewPageState extends State<HomeViewPage> {
  List<File> _imageFiles = [];
  bool _isLoading = true;

  // ✅ 1. ADD MISSING VARIABLES
  List<dynamic> _projectClasses = []; // Stores colors from JSON
  Map<String, String> _cachedLabelMap = {}; // Stores labels from CSV

  @override
  void initState() {
    super.initState();
    _initPage();
  }

  Future<void> _initPage() async {
    await MetadataService.syncProjectData(widget.title);

    // ✅ 2. LOAD COLORS FIRST
    await _loadClassColors();

    // 3. THEN LOAD IMAGES
    await _loadImages();
  }

  // ✅ 3. NEW FUNCTION TO READ CLASS COLORS
  Future<void> _loadClassColors() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final classFile = File('${appDir.path}/projects/${widget.title}/classes.json');

      if (await classFile.exists()) {
        String jsonString = await classFile.readAsString();
        setState(() {
          _projectClasses = jsonDecode(jsonString);
        });
      }
    } catch (e) {
      if (kDebugMode) print("Error loading classes: $e");
    }
  }

  Future<void> _loadImages() async {
    setState(() => _isLoading = true); // Show loading while working

    final appDir = await getApplicationDocumentsDirectory();
    final imagesDirPath = '${appDir.path}/projects/${widget.title}/images';
    final imagesDir = Directory(imagesDirPath);

    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }

    if (await imagesDir.exists()) {
      // ✅ 4. READ CSV TO MAP FILENAMES TO LABELS
      final csvData = await MetadataService.readCsvData(widget.title);
      Map<String, String> tempMap = {};

      for (var row in csvData) {
        String filename = row['path'].split(Platform.pathSeparator).last;
        tempMap[filename] = row['class'] ?? "Unclassified";
      }
      _cachedLabelMap = tempMap; // Save to state

      // 5. LIST ACTUAL FILES
      final files = imagesDir.listSync().map((item) => item as File).where((item) {
        final ext = item.path.split('.').last.toLowerCase();
        return ext == 'jpg' || ext == 'png' || ext == 'jpeg';
      }).toList();

      // Sort by newest
      files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));

      setState(() {
        _imageFiles = files;
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {

    // ✅ 5. PREPARE GRID DATA WITH LABELS
    // We map the file + the label we found in the CSV
    final List<Map<String, dynamic>> gridData = _imageFiles.map((file) {
      String filename = file.path.split(Platform.pathSeparator).last;
      return {
        "path": file.path,
        "label": _cachedLabelMap[filename], // <--- PASS THE LABEL FOR COLOR LOOKUP
      };
    }).toList();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.lightGreenAccent,
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: const Text(
          "Open Project",
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        child: Container(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Project Images',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
              ),
              const SizedBox(height: 20),

              _imageFiles.isEmpty
                  ? const Center(child: Text("No images found."))
                  : ImageGrid(
                columns: 3,
                itemCount: gridData.length,
                dataList: gridData,
                projectName: widget.title, // ✅ Fix: Use widget.title
                onBack: () {
                  _loadImages();
                  _loadClassColors();
                },
                // ✅ 6. PASS THE CLASS COLORS
                projectClasses: _projectClasses,
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: BottomAppBar(
        elevation: 2,
        color: Colors.white,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            GestureDetector(
              onTap: () {
                Navigator.pop(context);
              },
              child: Container(
                  height: 40,
                  width: 100,
                  decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: Colors.white,
                      border: Border.all(
                        color: Colors.black,
                        width: 1,
                      )),
                  alignment: Alignment.center,
                  child: const Text("Back")),
            ),
            GestureDetector(
              onTap: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ProjectContainerPage(projectName: widget.title),
                  ),
                );
              },
              child: Container(
                  height: 40,
                  width: 100,
                  decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: Colors.lightGreenAccent,
                      border: Border.all(
                        color: Colors.black,
                        width: 1,
                      )),
                  alignment: Alignment.center,
                  child: const Text(
                    "Select Project",
                    style: TextStyle(
                      color: Colors.black,
                    ),
                  )),
            ),
          ],
        ),
      ),
    );
  }
}