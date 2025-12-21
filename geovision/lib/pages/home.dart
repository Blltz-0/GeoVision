import 'package:flutter/material.dart';
import 'package:geovision/components/project_card.dart';
import 'package:geovision/components/project_list.dart';

import 'dart:io';
import 'package:path_provider/path_provider.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<FileSystemEntity> _folders = [];
  String _searchQuery = "";

  @override
  void initState() {
    super.initState();
    _loadFolders();
  }

  Future<String> _getAppPath() async {
    final appDocDir = await getApplicationDocumentsDirectory();
    final projectDirPath = '${appDocDir.path}/projects';
    final projectDir = Directory(projectDirPath);

    if (!await projectDir.exists()) {
      await projectDir.create(recursive: true);
    }
    return projectDir.path;
  }

  Future<void> _loadFolders() async {
    final path = await _getAppPath();
    final myDir = Directory(path);

    if (await myDir.exists()) {
      setState(() {
        _folders = myDir.listSync().whereType<Directory>().toList();
      });
    }
  }

  Future<bool> _createFolder(String folderName) async {
    final projectsPath = await _getAppPath();
    final newProjectDir = Directory('$projectsPath/$folderName');
    final imagesSubDir = Directory('$projectsPath/$folderName/images');

    if (await newProjectDir.exists()) {
      return false;
    } else {
      await newProjectDir.create();
      await imagesSubDir.create();
      _loadFolders();
      return true;
    }
  }

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
                bool success = await _createFolder(controller.text);
                if (!context.mounted) return;

                if (success) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Project created successfully!")),
                  );
                } else {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Error: That project name already exists!"),
                      backgroundColor: Colors.red,
                      duration: Duration(seconds: 2),
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
    final List<Map<String, dynamic>> allData = _folders.map((folder) {
      return {
        "title": folder.path.split(Platform.pathSeparator).last,
      };
    }).toList();

    final List<Map<String, dynamic>> filteredData = allData.where((item) {
      final title = item['title'].toString().toLowerCase();
      final query = _searchQuery.toLowerCase();
      return title.contains(query);
    }).toList();

    // 1. WRAP SCAFFOLD IN GESTURE DETECTOR
    // This detects taps anywhere on the background to close the keyboard
    return GestureDetector(
      onTap: () {
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.lightGreenAccent,
          automaticallyImplyLeading: false,
          centerTitle: true,
          title: Image.asset(
            'assets/logo.png',
            height: 80,
            fit: BoxFit.contain,
          ),
        ),
        body: SingleChildScrollView(
          child: Column(
            children: [
              //---------SECTION 1: RECENT ITEMS ------------
              Container(
                  padding: const EdgeInsets.all(20),
                  color: Colors.white,
                  height: 180,
                  width: double.infinity,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const Text(
                        'Recent Items',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height:10),
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              GestureDetector(
                                onTap: _showCreateDialog,
                                child: Container(
                                  height: 90,
                                  width: 90,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    border: Border.all(
                                        color: Colors.lightGreenAccent.withValues(alpha: 0.3),
                                        width: 1
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.add, color: Colors.green.withValues(alpha: 0.8),),
                                      const Text("New", style: TextStyle(color: Colors.green, fontSize: 10),)
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 5),
                              ...List.generate(allData.length, (index) {
                                final project = allData[index];
                                return Row(
                                  children: [
                                    ProjectCard(
                                      title: project["title"],
                                      onReturn: () => _loadFolders(),
                                    ),
                                    const SizedBox(width: 5),
                                  ],
                                );
                              }),
                            ],
                          ),
                        ),
                      )
                    ],
                  )
              ),

              //---------SECTION 2: ALL PROJECTS ------------
              Container(
                padding: const EdgeInsets.all(20),
                color: Colors.grey[100],
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[

                      // --- SEARCH BAR ---
                      TextField(
                        autofocus: false, // 2. Explicitly disable autofocus
                        onChanged: (val) {
                          setState(() => _searchQuery = val);
                        },
                        decoration: InputDecoration(
                          hintText: "Search projects...",
                          prefixIcon: const Icon(Icons.search, color: Colors.grey),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 20),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(30),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(30),
                            borderSide: const BorderSide(color: Colors.lightGreen),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      const Text(
                        'All Projects',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height:10),

                      SingleChildScrollView(
                          child: ProjectList(
                              dataList: filteredData,
                              onRefresh: () =>  _loadFolders()
                          )
                      )
                    ]
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}