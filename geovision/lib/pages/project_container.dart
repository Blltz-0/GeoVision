import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:geovision/pages/manage_classes_page.dart';
import 'package:geovision/pages/project_tabs/project_settings.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:native_exif/native_exif.dart';
import 'package:geovision/pages/project_tabs/camera.dart';
import 'package:geovision/pages/project_tabs/images.dart';
import 'package:geovision/pages/project_tabs/map.dart';
import 'package:share_plus/share_plus.dart';
import '../functions/data_service/export_service.dart';
import '../functions/data_service/metadata_handle.dart';
import 'manage_labels_page.dart';
import 'annotation_page.dart';

class ProjectContainerPage extends StatefulWidget {
  final String projectName;

  const ProjectContainerPage({
    super.key,
    required this.projectName,
  });

  @override
  State<ProjectContainerPage> createState() => _ProjectContainerPageState();
}

class _ProjectContainerPageState extends State<ProjectContainerPage> {
  List<File> _projectImages = [];
  Map<String, String> _labelMap = {};
  List<Map<String, dynamic>> _csvData = [];
  List<Map<String, dynamic>> _projectClasses = [];
  bool _isLoadingImages = true;

  String _projectType = 'classification';

  int _currentIndex = 1;
  bool _isExporting = false;

  final List<bool> _visitedIndices = [false, true, false, false];

  @override
  void initState() {
    super.initState();
    // 1. UPDATE TIMESTAMP IMMEDIATELY ON LOAD
    _updateLastOpened();

    _loadProjectType();
    _loadClasses();

    _loadDataOnly(); //!!!!Better Option for Release Version!!!!!!!!!!!
    //_synchronizeData(); !!!!Only Used when Manually Adding Images to Project Folder!!!!!!!!!!!
  }

  Future<void> _updateLastOpened() async {
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final projectPath = '${docDir.path}/projects/${widget.projectName}';
      final projectDir = Directory(projectPath);
      final file = File('$projectPath/last_opened.txt');

      if (await projectDir.exists()) {
        // Force create file if missing
        if (!await file.exists()) {
          await file.create(recursive: true);
        }
        // Write current time
        await file.writeAsString(DateTime.now().toIso8601String(), flush: true);
        debugPrint("✅ Updated last_opened for ${widget.projectName}");
      }
    } catch (e) {
      debugPrint("❌ Error updating last_opened: $e");
    }
  }

  Future<void> _loadProjectType() async {
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final typeFile = File('${docDir.path}/projects/${widget.projectName}/project_type.txt');

      if (await typeFile.exists()) {
        final content = await typeFile.readAsString();
        setState(() {
          _projectType = content.trim();
        });
      } else {
        setState(() {
          _projectType = 'classification';
        });
      }
    } catch (e) {
      debugPrint("Error loading project type: $e");
    }
  }

  void _onTabTapped(int index) {
    setState(() {
      _currentIndex = index;
      _visitedIndices[index] = true;
    });
  }

  Future<void> _loadDataOnly() async {
    if (!mounted) return;
    setState(() => _isLoadingImages = true);

    try {
      final docDir = await getApplicationDocumentsDirectory();
      final projectPath = '${docDir.path}/projects/${widget.projectName}';
      final imagesDir = Directory('$projectPath/images');

      if (!await imagesDir.exists()) {
        await imagesDir.create(recursive: true);
      }

      final List<FileSystemEntity> entities = await imagesDir.list().toList();
      final List<File> filesOnDisk = entities
          .whereType<File>()
          .where((f) {
        final ext = f.path.split('.').last.toLowerCase();
        return ext == 'jpg' || ext == 'png' || ext == 'jpeg';
      })
          .toList();

      filesOnDisk.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));

      // 2. Load GeoJSON Data (Service now handles .geojson internally)
      List<Map<String, dynamic>> rawGeoData = await MetadataService.readCsvData(widget.projectName);

      Map<String, Map<String, dynamic>> geoMap = {};
      for (var row in rawGeoData) {
        String rawPath = row['path'] ?? '';
        String filename = rawPath.split(Platform.pathSeparator).last;
        if (filename.isNotEmpty) {
          geoMap[filename] = row;
        }
      }

      Map<String, String> newLabelMap = {};
      for (File file in filesOnDisk) {
        String filename = file.path.split(Platform.pathSeparator).last;
        if (geoMap.containsKey(filename)) {
          newLabelMap[filename] = geoMap[filename]!['class'] ?? 'Unclassified';
        } else {
          newLabelMap[filename] = 'Unclassified';
        }
      }

      if (mounted) {
        setState(() {
          _projectImages = filesOnDisk;
          _csvData = rawGeoData;
          _labelMap = newLabelMap;
          _isLoadingImages = false;
        });
      }
    } catch (e) {
      debugPrint("❌ Load Error: $e");
      if (mounted) setState(() => _isLoadingImages = false);
    }
  }

  Future<void> _synchronizeData() async {
    if (!mounted) return;

    try {
      final docDir = await getApplicationDocumentsDirectory();
      final projectPath = '${docDir.path}/projects/${widget.projectName}';
      final imagesDir = Directory('$projectPath/images');

      if (!await imagesDir.exists()) {
        await imagesDir.create(recursive: true);
      }

      final List<FileSystemEntity> entities = await imagesDir.list().toList();
      final List<File> filesOnDisk = entities
          .whereType<File>()
          .where((f) {
        final ext = f.path.split('.').last.toLowerCase();
        return ext == 'jpg' || ext == 'png' || ext == 'jpeg';
      })
          .toList();

      filesOnDisk.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));

      // Read current GeoJSON
      List<Map<String, dynamic>> rawGeoData = await MetadataService.readCsvData(widget.projectName);

      Map<String, Map<String, dynamic>> geoMap = {};
      for (var row in rawGeoData) {
        String rawPath = row['path'] ?? '';
        String filename = rawPath.split(Platform.pathSeparator).last;
        if (filename.isNotEmpty) {
          geoMap[filename] = row;
        }
      }

      List<Map<String, dynamic>> cleanDataList = [];
      Map<String, String> newLabelMap = {};

      for (File file in filesOnDisk) {
        String filename = p.basename(file.path);
        String currentAbsolutePath = file.path;

        if (geoMap.containsKey(filename)) {
          var existingRow = geoMap[filename]!;
          existingRow['path'] = currentAbsolutePath;
          cleanDataList.add(existingRow);
          String cls = existingRow['class'] ?? '';
          newLabelMap[filename] = cls.isEmpty && _projectType == 'classification'
              ? 'Unclassified'
              : cls;
        } else {
          double lat = 0.0;
          double lng = 0.0;
          try {
            final exif = await Exif.fromPath(currentAbsolutePath);
            final latLong = await exif.getLatLong();
            await exif.close();
            if (latLong != null) {
              lat = latLong.latitude;
              lng = latLong.longitude;
            }
          } catch (_) {}

          String defaultClass = _projectType == 'segmentation' ? '' : 'Unclassified';

          Map<String, dynamic> newRow = {
            'path': filename,
            'class': defaultClass,
            'lat': lat,
            'lng': lng,
            'time': file.lastModifiedSync().toIso8601String(),
          };
          cleanDataList.add(newRow);
          newLabelMap[filename] = defaultClass;
        }
      }

      // Updated call to GeoJSON saver
      await _saveGeoJsonToDisk(cleanDataList);

      if (mounted) {
        setState(() {
          _projectImages = filesOnDisk;
          _csvData = cleanDataList;
          _labelMap = newLabelMap;
          _isLoadingImages = false;
        });
      }

    } catch (e) {
      debugPrint("❌ Sync Error: $e");
      if (mounted) setState(() => _isLoadingImages = false);
    }
  }

  Future<void> _saveGeoJsonToDisk(List<Map<String, dynamic>> data) async {
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final File geoFile = File('${docDir.path}/projects/${widget.projectName}/project_data.geojson');

      // Construct FeatureCollection
      final List<Map<String, dynamic>> features = data.map((row) {
        return {
          "type": "Feature",
          "geometry": {
            "type": "Point",
            "coordinates": [
              (row['lng'] as num).toDouble(),
              (row['lat'] as num).toDouble()
            ]
          },
          "properties": {
            "name": p.basename(row['path']),
            "class": row['class'],
            "time": row['time'],
          }
        };
      }).toList();

      final geoJson = {
        "type": "FeatureCollection",
        "features": features,
      };

      await geoFile.writeAsString(jsonEncode(geoJson));
    } catch (e) {
      debugPrint("❌ Failed to save GeoJSON: $e");
    }
  }

  Future<void> _loadClasses() async {
    final classes = await MetadataService.getClasses(widget.projectName);
    if (mounted) {
      setState(() => _projectClasses = classes);
    }
  }

  Future<void> _handleExport() async {

    final token = ExportCancellationToken();

    // 2. Show Progress Dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text("Exporting Project"),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 20),
              Text("Building COCO Dataset & Zipping..."),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                token.cancel();
                Navigator.pop(context);
              },
              child: const Text("Cancel", style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
    );

    try {
      setState(() => _isExporting = true);

      // 3. Generate ZIP in temporary storage
      final String? tempZipPath = await ExportService.exportProject(widget.projectName, token: token);

      if (mounted) Navigator.pop(context); // Close the progress dialog

      if (tempZipPath != null && mounted) {
        final File tempFile = File(tempZipPath);
        final Uint8List fileBytes = await tempFile.readAsBytes();

        // 1. User saves the file
        String? outputFile = await FilePicker.platform.saveFile(
          dialogTitle: 'Select where to save your export:',
          fileName: '${widget.projectName}_COCO_Export.zip',
          type: FileType.custom,
          allowedExtensions: ['zip'],
          bytes: fileBytes,
        );

        if (outputFile != null) {
          // 2. Pass the TEMP path to the toast, not the outputFile path
          // The tempZipPath is a real file path the app definitely has access to.
          _showExportSuccessToast(outputFile, tempZipPath);
        }
      }
    } catch (e) {
      if (mounted) {
        if (Navigator.canPop(context)) Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Export Failed: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  void _showExportSuccessToast(String displayPath, String sharePath) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 10),
        backgroundColor: Colors.lightGreen[900],
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("✅ Project Saved", style: TextStyle(fontWeight: FontWeight.bold)),
            Text(
              "Location: $displayPath",
              style: const TextStyle(fontSize: 10, color: Colors.white70),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        action: SnackBarAction(
          label: "SHARE",
          textColor: Colors.white,
          onPressed: () {
            // FIX: Use sharePath (the temp file) instead of displayPath
            Share.shareXFiles([XFile(sharePath)], text: 'GeoVision Export: ${widget.projectName}');
          },
        ),
      ),
    );
  }

  void _openManageClasses() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ManageClassesPage(projectName: widget.projectName),
      ),
    );
    if (mounted) {
      await _loadClasses();
      await _synchronizeData();
      setState(() {});
    }
  }

  void _openManageLabels() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ManageLabelsPage(projectName: widget.projectName),
      ),
    );
    if (mounted) setState(() {});
  }

  void _renameProject() {
    final controller = TextEditingController(text: widget.projectName);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Rename Project"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: "Project Name", hintText: "Enter new name"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isNotEmpty) {
                bool success = await _renameFolder(widget.projectName, newName);
                if (!context.mounted) return;
                if (success) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Renamed to $newName")));
                  Navigator.pop(context, true);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Error: Name already exists or failed."), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text("Rename"),
          ),
        ],
      ),
    );
  }

  Future<bool> _renameFolder(String oldName, String newName) async {
    if (oldName == newName) return true;
    try {
      final directory = await getApplicationDocumentsDirectory();
      final String projectRoot = '${directory.path}/projects/$oldName';
      final String imagesPath = '$projectRoot/images';

      final oldDir = Directory(projectRoot);
      final imagesDir = Directory(imagesPath);
      final newDir = Directory('${directory.path}/projects/$newName');

      if (!await oldDir.exists()) return false;

      if (await imagesDir.exists()) {
        List<FileSystemEntity> entities = await imagesDir.list().toList();
        for (var entity in entities) {
          if (entity is! File) continue;
          String currentName = entity.path.split(Platform.pathSeparator).last;
          if (currentName.startsWith("${newName}_")) continue;

          String newFileName = "";
          if (currentName.toLowerCase().startsWith("${oldName.toLowerCase()}_")) {
            String suffix = currentName.substring(oldName.length + 1);
            newFileName = "${newName}_$suffix";
          } else if (currentName.contains('_')) {
            List<String> parts = currentName.split('_');
            String suffix = parts.length >= 2 ? parts.sublist(1).join('_') : "Unclassified_$currentName";
            newFileName = "${newName}_$suffix";
          } else {
            newFileName = "${newName}_Unclassified_$currentName";
          }
          try {
            await entity.rename('${imagesDir.path}/$newFileName');
          } catch (e) {
            debugPrint("Error renaming file: $e");
          }
        }
      }

      await oldDir.rename(newDir.path);
      // Rebuild specifically handles GeoJSON now
      await MetadataService.rebuildProjectData(newName, projectType: _projectType);
      return true;
    } catch (e) {
      debugPrint("❌ CRITICAL ERROR: $e");
      return false;
    }
  }

  Future<bool> _deleteFolder() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final String path = '${directory.path}/projects/${widget.projectName}';
      final targetDir = Directory(path);
      if (await targetDir.exists()) {
        await targetDir.delete(recursive: true);
        return true;
      }
      return false;
    } catch (e) {
      debugPrint("Delete failed: $e");
      return false;
    }
  }

  void _confirmDelete() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Project"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Are you sure you want to delete '${widget.projectName}'?"),
            const SizedBox(height: 10),
            const Text(
              "This action cannot be undone.",
              style: TextStyle(color: Colors.red, fontSize: 13, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              decoration: InputDecoration(hintText: widget.projectName, border: const OutlineInputBorder()),
            ),
            Text("Type the Project Name to Confirm", style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              if (controller.text.trim() == widget.projectName) {
                bool success = await _deleteFolder();
                if (!context.mounted) return;
                if (success) {
                  Navigator.pop(context);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Project deleted.")));
                } else {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Error deleting folder.")));
                }
              }
            },
            child: const Text("Delete"),
          ),
        ],
      ),
    );
  }

  Future<bool?> _openAnnotationPage(String imagePath) async {
    // We await the result from AnnotationPage (which returns true if saved)
    final bool? result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AnnotationPage(
          imagePath: imagePath,
          projectName: widget.projectName,
        ),
      ),
    );

    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
              gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    ?Colors.lightGreen[300],
                    ?Colors.lightGreen[400],
                    ?Colors.lightGreen[400],
                    ?Colors.lightGreen[500],
                    ?Colors.lightGreen[500],
                    ?Colors.lightGreen[600],
                    ?Colors.lightGreen[700],
                  ])
          ),
        ),
        automaticallyImplyLeading: false,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Text(widget.projectName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        actions: [
          _isExporting
              ? const Padding(padding: EdgeInsets.all(12.0), child: CircularProgressIndicator())
              : IconButton(
              icon: const Icon(Icons.ios_share),
              onPressed: _handleExport
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _visitedIndices[0]
              ? CameraPage(
            projectName: widget.projectName,
            projectClasses: _projectClasses,
            isActive: _currentIndex == 0,
            projectType: _projectType,
            onClassesUpdated: () async {
              await _loadClasses();
              setState(() {});
            },
            onPhotoTaken: _synchronizeData,
          )
              : const SizedBox(),

          _visitedIndices[1]
              ? ImagesPage(
            projectName: widget.projectName,
            images: _projectImages,
            labelMap: _labelMap,
            projectClasses: _projectClasses,
            isLoading: _isLoadingImages,
            projectType: _projectType,
            onAnnotate: _openAnnotationPage,
            onDataChanged: _synchronizeData,
            onClassesUpdated: () async {
              await _loadClasses();
              setState(() {});
            },
          )
              : const SizedBox(),

          _visitedIndices[2]
              ? MapPage(
            projectName: widget.projectName,
            mapData: _csvData,
            projectClasses: _projectClasses,
            projectType: _projectType,
            onClassesUpdated: () async {
              await _loadClasses();
              setState(() {});
            },
          )
              : const SizedBox(),

          _visitedIndices[3]
              ? ProjectSettings(
            projectName: widget.projectName,
            projectType: _projectType,
            onManageClasses: _openManageClasses,
            onManageLabels: _openManageLabels,
            onRenameProject: _renameProject,
            onDeleteProject: _confirmDelete,
          )
              : const SizedBox(),
        ],
      ),
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Color(0xFFAED581), // lightGreen[300]
                Color(0xFF9CCC65), // lightGreen[400]
                Color(0xFF9CCC65),
                Color(0xFF8BC34A), // lightGreen[500]
                Color(0xFF8BC34A),
                Color(0xFF7CB342), // lightGreen[600]
                Color(0xFF689F38), // lightGreen[700]
              ],
            ),
          ),
          child: SafeArea(
            child: BottomNavigationBar(
              type: BottomNavigationBarType.fixed,
              backgroundColor: Colors.transparent,
              elevation: 0,
              selectedItemColor: Colors.lightGreenAccent,
              unselectedItemColor: Colors.white,
              currentIndex: _currentIndex,
              onTap: _onTabTapped,
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.camera_alt),
                  label: 'Camera',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.photo_library),
                  label: 'Gallery',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.map),
                  label: 'Map',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.settings),
                  label: 'Settings',
                ),
              ],
            ),
          ),
    )
    );
  }
}