import 'package:flutter/material.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

// COMPONENT IMPORTS
import '../components/project_card.dart';
import '../components/project_list.dart';
import 'home_tabs/about.dart';
import 'home_tabs/help.dart';
import 'project_container.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Map<String, dynamic>> _foldersData = [];
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
    if (!await projectDir.exists()) await projectDir.create(recursive: true);
    return projectDir.path;
  }

  Future<void> _loadFolders() async {
    final path = await _getAppPath();
    final myDir = Directory(path);

    if (await myDir.exists()) {
      final List<FileSystemEntity> entities = myDir.listSync().whereType<Directory>().toList();

      final List<Map<String, dynamic>> foldersWithDetails = await Future.wait(
        entities.map((dir) async {
          final stat = await dir.stat();
          String type = 'classification';
          final typeFile = File('${dir.path}/project_type.txt');
          if (await typeFile.exists()) {
            type = (await typeFile.readAsString()).trim();
          }

          DateTime lastOpenedDate = stat.modified;
          final lastOpenedFile = File('${dir.path}/last_opened.txt');
          if (await lastOpenedFile.exists()) {
            try {
              lastOpenedDate = DateTime.parse(await lastOpenedFile.readAsString());
            } catch (_) {}
          }

          return {
            'folder': dir,
            'modified': stat.modified,
            'lastOpened': lastOpenedDate,
            'type': type,
            'title': dir.path.split(Platform.pathSeparator).last,
          };
        }),
      );

      foldersWithDetails.sort((a, b) => b['lastOpened'].compareTo(a['lastOpened']));

      setState(() {
        _foldersData = foldersWithDetails;
      });
    }
  }

  Future<bool> _createFolder(String folderName, String projectType) async {
    final projectsPath = await _getAppPath();
    final newProjectDir = Directory('$projectsPath/$folderName');
    final imagesSubDir = Directory('$projectsPath/$folderName/images');
    final typeFile = File('$projectsPath/$folderName/project_type.txt');
    final lastOpenedFile = File('$projectsPath/$folderName/last_opened.txt');

    if (await newProjectDir.exists()) {
      return false;
    } else {
      await newProjectDir.create();
      await imagesSubDir.create();
      await typeFile.writeAsString(projectType);
      await lastOpenedFile.writeAsString(DateTime.now().toIso8601String());
      _loadFolders();
      return true;
    }
  }

  IconData _getIconForType(String type) {
    return type == 'segmentation' ? Icons.brush : Icons.grid_view;
  }

  void _showCreateDialog() {
    final controller = TextEditingController();
    String selectedType = 'classification';

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text("New Project"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    decoration: const InputDecoration(hintText: "Project Name"),
                    textInputAction: TextInputAction.done,
                    autofocus: true,
                  ),
                  const SizedBox(height: 20),
                  DropdownButtonFormField<String>(
                    initialValue: selectedType,
                    decoration: const InputDecoration(labelText: "Project Mode", border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'classification', child: Text("Image Classification")),
                      DropdownMenuItem(value: 'segmentation', child: Text("Segmentation")),
                    ],
                    onChanged: (value) => setState(() => selectedType = value!),
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
                ElevatedButton(
                  onPressed: () async {
                    if (controller.text.isNotEmpty) {
                      bool success = await _createFolder(controller.text, selectedType);
                      if (!context.mounted) return;

                      if (success) {
                        Navigator.pop(context);
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ProjectContainerPage(projectName: controller.text),
                          ),
                        );
                        _loadFolders();
                      } else {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Error: That project name already exists!"), backgroundColor: Colors.red),
                        );
                      }
                    }
                  },
                  child: const Text("Create"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // 1. Prepare Data
    final List<Map<String, dynamic>> alphaSortedData = List.from(_foldersData);
    alphaSortedData.sort((a, b) => a['title'].toString().toLowerCase().compareTo(b['title'].toString().toLowerCase()));

    final List<Map<String, dynamic>> filteredData = alphaSortedData.where((item) {
      return item['title'].toString().toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    final int recentCount = _foldersData.length > 4 ? 4 : _foldersData.length;

    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.lightGreenAccent,
          automaticallyImplyLeading: false,
          centerTitle: true,
          // --- TITLE WITH LOGO ---
          title: Image.asset('assets/logo.png', height: 80, fit: BoxFit.contain),

          // --- UPDATED ACTIONS WITH ICONS ---
          actions: [
            IconButton(
              icon: const Icon(Icons.help_outline),
              tooltip: 'Help',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const HelpPage()),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.info_outline),
              tooltip: 'About',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const AboutPage()),
                );
              },
            ),
          ],
        ),
        body: SingleChildScrollView(
          child: Column(
            children: [
              // --- RECENT ITEMS AREA ---
              Container(
                  padding: const EdgeInsets.all(20),
                  color: Colors.white,
                  height: 180,
                  width: double.infinity,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const Text('Recent Items', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                      const SizedBox(height:10),
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              GestureDetector(
                                onTap: _showCreateDialog,
                                child: Container(
                                  height: 90, width: 90,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    border: Border.all(color: Colors.lightGreenAccent.withValues(alpha: 0.3), width: 1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.add, color: Colors.green.withValues(alpha: 0.8)),
                                      const Text("New", style: TextStyle(color: Colors.green, fontSize: 10))
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 5),
                              ...List.generate(recentCount, (index) {
                                final project = _foldersData[index];
                                return Row(
                                  children: [
                                    ProjectCard(
                                      title: project["title"],
                                      iconData: _getIconForType(project['type']),
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
              // --- ALL PROJECTS AREA ---
              Container(
                padding: const EdgeInsets.all(20),
                color: Colors.grey[100],
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      TextField(
                        autofocus: false,
                        onChanged: (val) => setState(() => _searchQuery = val),
                        decoration: InputDecoration(
                          hintText: "Search projects...",
                          prefixIcon: const Icon(Icons.search, color: Colors.grey),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 20),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide(color: Colors.grey.shade300)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: const BorderSide(color: Colors.lightGreen)),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text('All Projects', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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