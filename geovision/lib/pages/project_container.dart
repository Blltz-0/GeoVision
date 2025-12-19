import 'package:flutter/material.dart';
import 'package:geovision/pages/project_tabs/camera.dart';
import 'package:geovision/pages/project_tabs/images.dart';
import 'package:geovision/pages/project_tabs/map.dart';

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
  List<Map<String, dynamic>> _projectClasses = [];
  int _currentIndex=1;
  bool _isExporting = false;

  Future<void> _handleExport() async {
    setState(() => _isExporting = true);

    // Show a snackbar immediately
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Generating map and zipping project...')),
    );

    // Run the export service
    await ExportService.exportProject(widget.projectName);

    if (mounted) {
      setState(() => _isExporting = false);
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
    }
  }

  late final List<Widget> _tabs = [
    CameraPage(projectName: widget.projectName,),
    ImagesPage(projectName: widget.projectName,),
    MapPage(projectName: widget.projectName,),
  ];

  Future<void> _loadClasses() async {
    final classes = await MetadataService.getClasses(widget.projectName);
    setState(() => _projectClasses = classes);
  }

  void _showAddClassDialog() {
    final nameCtrl = TextEditingController();
    Color selectedColor = Colors.red; // Default

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("New Class"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "Class Name")),
            const SizedBox(height: 15),
            const Text("Select Color:"),
            const SizedBox(height: 10),
            // Simple Color Picker Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [Colors.red, Colors.green, Colors.blue, Colors.orange, Colors.purple].map((c) {
                return GestureDetector(
                  onTap: () {
                    selectedColor = c; // (Note: In a real StatefulWidget dialog, you'd need setState)
                    Navigator.pop(ctx);
                    _finalizeAddClass(nameCtrl.text, c); // Call helper
                  },
                  child: CircleAvatar(backgroundColor: c, radius: 15),
                );
              }).toList(),
            )
          ],
        ),
      ),
    );
  }

  void _finalizeAddClass(String name, Color color) async {
    if (name.isEmpty) return;
    await MetadataService.addClassDefinition(widget.projectName, name, color.value);
    _loadClasses(); // Refresh list
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.lightGreenAccent,
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: Image.asset(
          'assets/logo.png',
          height: 80, // Keep it constrained so it doesn't overflow
          fit: BoxFit.contain, // Ensures it doesn't get cut off
        ),
        actions: [
          // If exporting, show spinner, otherwise show button
          _isExporting
              ? const Padding(
            padding: EdgeInsets.all(12.0),
            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
          )
              : IconButton(
            icon: const Icon(Icons.ios_share), // Or Icons.download / Icons.archive
            tooltip: 'Export Project to ZIP',
            onPressed: _handleExport,
          ),
        ],

      ),
      body: _tabs[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: Colors.lightGreenAccent,
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.camera), label: 'Camera'),
          BottomNavigationBarItem(icon: Icon(Icons.image), label: 'Images'),
          BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Map'),
        ],
      ),
    );
  }
}