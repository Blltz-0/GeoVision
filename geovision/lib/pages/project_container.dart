import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geovision/pages/manage_classes_page.dart';
import 'package:path_provider/path_provider.dart';
import 'package:native_exif/native_exif.dart';

// Your existing imports
import 'package:geovision/pages/project_tabs/camera.dart';
import 'package:geovision/pages/project_tabs/images.dart';
import 'package:geovision/pages/project_tabs/map.dart';
import '../components/class_creator.dart';
import '../functions/export_service.dart';
import '../functions/metadata_handle.dart';

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
  // --- HOISTED STATE ---
  List<File> _projectImages = [];
  Map<String, String> _labelMap = {};
  List<Map<String, dynamic>> _csvData = [];
  List<Map<String, dynamic>> _projectClasses = [];
  bool _isLoadingImages = true;

  // --- UI STATE ---
  int _currentIndex = 1;
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _loadClasses();
    _synchronizeData();
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

      // 1. GET FILES FROM DISK
      final List<FileSystemEntity> entities = await imagesDir.list().toList();
      final List<File> filesOnDisk = entities
          .whereType<File>()
          .where((f) {
        final ext = f.path.split('.').last.toLowerCase();
        return ext == 'jpg' || ext == 'png' || ext == 'jpeg';
      })
          .toList();

      filesOnDisk.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));

      // 2. READ CSV DATA
      List<Map<String, dynamic>> rawCsvData = await MetadataService.readCsvData(widget.projectName);

      Map<String, Map<String, dynamic>> csvMap = {};
      for (var row in rawCsvData) {
        String rawPath = row['path'] ?? '';
        String filename = rawPath.split(Platform.pathSeparator).last;
        if (filename.isNotEmpty) {
          csvMap[filename] = row;
        }
      }

      // 3. MERGE
      List<Map<String, dynamic>> cleanDataList = [];
      Map<String, String> newLabelMap = {};

      for (File file in filesOnDisk) {
        String filename = file.path.split(Platform.pathSeparator).last;
        String currentAbsolutePath = file.path;

        if (csvMap.containsKey(filename)) {
          var existingRow = csvMap[filename]!;
          existingRow['path'] = currentAbsolutePath;
          cleanDataList.add(existingRow);
          newLabelMap[filename] = existingRow['class'] ?? 'Unclassified';
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

          Map<String, dynamic> newRow = {
            'path': currentAbsolutePath,
            'class': 'Unclassified',
            'lat': lat,
            'lng': lng,
            'time': file.lastModifiedSync().toIso8601String(),
          };
          cleanDataList.add(newRow);
          newLabelMap[filename] = 'Unclassified';
        }
      }

      await _saveCsvToDisk(cleanDataList);

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

  Future<void> _saveCsvToDisk(List<Map<String, dynamic>> data) async {
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final File csvFile = File('${docDir.path}/projects/${widget.projectName}/project_data.csv');
      final IOSink sink = csvFile.openWrite();

      sink.writeln("path,class,lat,lng,time");

      for (var row in data) {
        String fullPath = row['path'].toString();
        String filename = fullPath.split(Platform.pathSeparator).last;
        String cls = row['class'] ?? 'Unclassified';
        String lat = row['lat']?.toString() ?? '0.0';
        String lng = row['lng']?.toString() ?? '0.0';
        String time = row['time']?.toString() ?? DateTime.now().toIso8601String();

        sink.writeln("$filename,$cls,$lat,$lng,$time");
      }
      await sink.flush();
      await sink.close();
    } catch (e) {
      debugPrint("❌ Failed to save CSV: $e");
    }
  }

  Future<void> _loadClasses() async {
    final classes = await MetadataService.getClasses(widget.projectName);
    if (mounted) {
      setState(() => _projectClasses = classes);
    }
  }

  Future<void> _handleExport() async {
    setState(() => _isExporting = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: Duration(milliseconds: 1000),
        content: Text("Exporting the Project..."),
        behavior: SnackBarBehavior.floating, // This makes it float
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
    await ExportService.exportProject(widget.projectName);
    if (mounted) {
      setState(() => _isExporting = false);
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
    }
  }

  void _showAddClassDialog() async {
    // Direct navigation to CreateClassPage for the "More" menu
    final String? newClassName = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreateClassPage(projectName: widget.projectName),
      ),
    );

    if (newClassName != null && mounted) {
      _loadClasses(); // Refresh
    }
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
      await MetadataService.rebuildProjectData(newName);
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

  void _openManageClasses() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ManageClassesPage(projectName: widget.projectName),
      ),
    );

    // When we return, reload everything in case user deleted/edited classes
    if (mounted) {
      await _loadClasses();      // Refresh class list
      await _synchronizeData();  // Refresh images (in case of reclassification)
      setState(() {});           // Force UI rebuild
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      CameraPage(
        projectName: widget.projectName,
        projectClasses: _projectClasses,
        onClassesUpdated: () async {
          await _loadClasses();
          setState(() {});
        },
        onPhotoTaken: _synchronizeData,
      ),
      ImagesPage(
        projectName: widget.projectName,
        images: _projectImages,
        labelMap: _labelMap,
        projectClasses: _projectClasses,
        isLoading: _isLoadingImages,
        onDataChanged: _synchronizeData,
        onClassesUpdated: () async {
          await _loadClasses();
          setState(() {});
        },
      ),
      MapPage(
        projectName: widget.projectName,
        mapData: _csvData,
        projectClasses: _projectClasses,
        onClassesUpdated: () async {
          await _loadClasses();
          setState(() {});
        },
      ),
    ];

    // --- NEW: Wrap Scaffold in PopScope ---
    return PopScope(
      canPop: false, // 1. Disable automatic back navigation
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        if (didPop) return; // If system already handled it, do nothing

        // 2. Show Confirmation Dialog
        final bool shouldLeave = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("Exit Project?"),
            content: const Text("Are you sure you want to return to the home screen?"),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false), // Stay
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(context, true), // Leave
                child: const Text("Exit"),
              ),
            ],
          ),
        ) ?? false;

        // 3. Manually pop if user confirmed
        if (shouldLeave && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.lightGreenAccent,
          automaticallyImplyLeading: false, // We handle back manually now
          centerTitle: true,
          // Add a manual Back Button to the AppBar that triggers the same logic
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              // Trigger the same dialog logic manually
              final bool shouldLeave = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text("Exit Project?"),
                  content: const Text("Are you sure you want to return to the home screen?"),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text("Cancel"),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text("Exit"),
                    ),
                  ],
                ),
              ) ?? false;

              if (shouldLeave && context.mounted) {
                Navigator.of(context).pop();
              }
            },
          ),
          title: Text(widget.projectName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          actions: [
            _isExporting
                ? const Padding(padding: EdgeInsets.all(12.0), child: CircularProgressIndicator())
                : IconButton(
                icon: const Icon(Icons.ios_share),
                onPressed: _handleExport
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                if (value == 'rename') _renameProject();
                if (value == 'classes') _openManageClasses();
                if (value == 'delete') _confirmDelete();
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'classes', child: Text('Manage Classes')),
                const PopupMenuItem(value: 'rename', child: Text('Rename Project')),
                const PopupMenuItem(value: 'delete', child: Text('Delete Project', style: TextStyle(color: Colors.red))),
              ],
            ),
          ],
        ),
        body: IndexedStack(
          index: _currentIndex,
          children: pages,
        ),
        bottomNavigationBar: BottomNavigationBar(
          backgroundColor: Colors.lightGreenAccent,
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.camera_alt), label: 'Camera'),
            BottomNavigationBarItem(icon: Icon(Icons.photo_library), label: 'Gallery'),
            BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Map'),
          ],
        ),
      ),
    );
  }
}