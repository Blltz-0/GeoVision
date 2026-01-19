import 'package:flutter/material.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';
import 'package:permission_handler/permission_handler.dart';

// COMPONENT IMPORTS
import '../components/project_card.dart';
import '../components/project_list.dart';
import 'home_add.dart';
import 'home_tabs/about.dart';
import 'home_tabs/help.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Map<String, dynamic>> _foldersData = [];
  String _searchQuery = "";

  // 1. ADDED: Filter state variable
  String _projectFilter = 'all'; // Options: 'all', 'classification', 'segmentation'

  @override
  void initState() {
    super.initState();
    _requestInitialPermissions();
    _loadFolders();
  }

  Future<void> _requestInitialPermissions() async {
    // Request Camera and Location permissions simultaneously
    await [
      Permission.camera,
      Permission.location,
    ].request();

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

          // Determine Project Type
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

          // Count Items (Classes vs Labels)
          int itemCount = 0;
          String itemLabel = "Classes";

          if (type == 'segmentation') {
            itemLabel = "Labels";
            final labelsFile = File('${dir.path}/labels.json');
            if (await labelsFile.exists()) {
              try {
                final content = await labelsFile.readAsString();
                final List<dynamic> jsonList = jsonDecode(content);
                itemCount = jsonList.length;
              } catch (_) {}
            }
          } else {
            final classesFile = File('${dir.path}/classes.json');
            if (await classesFile.exists()) {
              try {
                final content = await classesFile.readAsString();
                final List<dynamic> jsonList = jsonDecode(content);
                itemCount = jsonList.length;
              } catch (_) {}
            }
          }

          return {
            'folder': dir,
            'modified': stat.modified,
            'lastOpened': lastOpenedDate,
            'type': type,
            'title': dir.path.split(Platform.pathSeparator).last,
            'itemCount': itemCount,
            'itemLabel': itemLabel,
          };
        }),
      );

      foldersWithDetails.sort((a, b) => b['lastOpened'].compareTo(a['lastOpened']));

      setState(() {
        _foldersData = foldersWithDetails;
      });
    }
  }

  IconData _getIconForType(String type) {
    return type == 'segmentation' ? Icons.brush : Icons.grid_view;
  }


  // 2. ADDED: Helper widget for filter buttons
  Widget _buildFilterBtn(IconData icon, String value, String tooltip) {
    bool isSelected = _projectFilter == value;
    return GestureDetector(
      onTap: () => setState(() => _projectFilter = value),
      child: Tooltip(
        message: tooltip,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            shape: BoxShape.circle,
            boxShadow: isSelected
                ? [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4, offset: const Offset(0, 2))]
                : [],
          ),
          child: Icon(
            icon,
            size: 20,
            color: isSelected ? Colors.green[700] : Colors.grey[500],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> alphaSortedData = List.from(_foldersData);
    alphaSortedData.sort((a, b) => a['title'].toString().toLowerCase().compareTo(b['title'].toString().toLowerCase()));

    // 3. UPDATED: Filtering logic now includes _projectFilter
    final List<Map<String, dynamic>> filteredData = alphaSortedData.where((item) {
      final matchesSearch = item['title'].toString().toLowerCase().contains(_searchQuery.toLowerCase());
      final matchesType = _projectFilter == 'all' || item['type'] == _projectFilter;
      return matchesSearch && matchesType;
    }).toList();

    final int recentCount = _foldersData.length > 4 ? 4 : _foldersData.length;

    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.lightGreenAccent,
          automaticallyImplyLeading: false,
          centerTitle: true,
          title: Image.asset('assets/logo.png', height: 80, fit: BoxFit.contain),
          actions: [
            IconButton(
              icon: const Icon(Icons.help_outline),
              tooltip: 'Help',
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const HelpPage())),
            ),
            IconButton(
              icon: const Icon(Icons.info_outline),
              tooltip: 'About',
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const AboutPage())),
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
                                onTap: () async {
                        // Navigate to the project creation
                        await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const HomeAddPage())
                        );
                        // Refresh list when returning
                        _loadFolders();
                        },
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
                                      projectType: project['type'],
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

                      // 4. UPDATED: Header Row with Toggle
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('All Projects', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),

                          // Toggle Container
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.grey[300],
                              borderRadius: BorderRadius.circular(24),
                            ),
                            padding: const EdgeInsets.all(3),
                            child: Row(
                              children: [
                                _buildFilterBtn(Icons.apps, 'all', 'All Projects'),
                                _buildFilterBtn(Icons.grid_view, 'classification', 'Classification Only'),
                                _buildFilterBtn(Icons.brush, 'segmentation', 'Segmentation Only'),
                              ],
                            ),
                          )
                        ],
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