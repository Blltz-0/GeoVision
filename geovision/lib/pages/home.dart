import 'package:flutter/material.dart';
import 'package:geovision/components/project_card.dart';
import 'package:geovision/components/project_grid.dart';

import 'dart:io';
import 'package:path_provider/path_provider.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<FileSystemEntity> _folders = [];

  @override
  void initState() {
    super.initState();
    _loadFolders(); // 4. Load data when app starts
  }

  // Replace your old _getAppPath with this one
  Future<String> _getAppPath() async {
    final appDocDir = await getApplicationDocumentsDirectory();

    // 1. Define the specific subfolder path
    final projectDirPath = '${appDocDir.path}/projects';
    final projectDir = Directory(projectDirPath);

    // 2. Check if 'projects' folder exists; if not, create it!
    if (!await projectDir.exists()) {
      await projectDir.create(recursive: true);
    }

    // 3. Return THIS path instead of the root
    return projectDir.path;
  }

  Future<void> _loadFolders() async {
    final path = await _getAppPath();
    final myDir = Directory(path);

    if (await myDir.exists()) {
      setState(() {
        // Get all folders and ignore files
        _folders = myDir.listSync().whereType<Directory>().toList();
      });
    }
  }

  Future<bool> _createFolder(String folderName) async {
    final projectsPath = await _getAppPath();

    final newProjectDir = Directory('$projectsPath/$folderName');
    final imagesSubDir = Directory('$projectsPath/$folderName/images');

    // CHECK IF EXISTS
    if (await newProjectDir.exists()) {
      // Return FALSE so the UI knows it failed
      return false;
    } else {
      // Create folders
      await newProjectDir.create();
      await imagesSubDir.create();

      _loadFolders(); // Refresh list
      return true; // Return TRUE for success
    }
  }

  // --- UI: Show Dialog ---
  void _showCreateDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("New Project"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: "Project Name"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {

                // 1. Call the function and wait for the result
                bool success = await _createFolder(controller.text);

                if (!context.mounted) return; // Safety check

                if (success) {
                  // SUCCESS: Close dialog
                  Navigator.pop(context);

                  // Optional: Show success message
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Project created successfully!")),
                  );
                } else {
                  // FAILURE (Duplicate): Keep dialog open, show RED Error
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text("Error: That project name already exists!"),
                      backgroundColor: Colors.red,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              }
            },
            child: const Text("Create"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> displayData = _folders.map((folder) {
      return {
        "title": folder.path.split(Platform.pathSeparator).last, // Get name from path
        // You can add "color": Colors.blue here if you want
      };
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('GeoVision'),
        shadowColor: Colors.black54,

        backgroundColor: Colors.white,
        elevation: 0.4,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            //---------SECTION 1: RECENT ITEMS ------------
            Container(
              padding: const EdgeInsets.all(20),
              color: Colors.white,
              height: 150,
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    'Recent Items',
                    style: TextStyle(
                      fontSize: 15,
                    ),
                  ),
                  SizedBox(height:10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: _showCreateDialog,
                          child: Container(
                            height: 75,
                            width: 75,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(
                                color: Colors.blueAccent.withValues(alpha: 0.3), // fixed withValues syntax
                                width: 1
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add, color: Colors.blueAccent.withValues(alpha: 0.8),),
                                Text("New Project", style: TextStyle(color: Colors.blueAccent, fontSize: 10),)
                              ],
                            ),
                          ),
                        ),
                        SizedBox(width: 5),
                        ...List.generate(displayData.length, (index) {

                          final project = displayData[index];

                          return Row(
                            children: [
                              ProjectCard(
                                title: project["title"],
                              ),
                              SizedBox(width: 5),
                            ]
                          );
                          },
                        )
                      ],
                    ),
                  )
                ],
              )
            ),

            Container(
              padding: const EdgeInsets.all(20),
              color: Colors.white,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text('All Projects'),
                  SizedBox(height:10),
                  SingleChildScrollView(
                    child: ProjectGrid(columns: 3, itemCount: displayData.length, dataList: displayData,)
                  )
                ]
              ),
            ),
            Container(
              color: Colors.green,
              height: 200,
            ),
          ],
        ),
      ),
    );
  }
}
