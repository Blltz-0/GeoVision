import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';
import 'package:permission_handler/permission_handler.dart';
import '../components/project/project_card.dart';
import '../components/project/project_list.dart';
import '../functions/data_service/import_service.dart';
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
      Permission.storage,
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

  void _showAddOptions() {
    // 1. THIS IS THE STABLE CONTEXT.
    // It belongs to the HomePage, which stays alive throughout the import.
    final homeContext = context;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Add New Project"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildActionCard(
              icon: Icons.create_new_folder,
              color: Colors.green,
              title: "Create New Project",
              onTap: () {
                Navigator.pop(dialogContext); // Close menu
                Navigator.push(
                  homeContext,
                  MaterialPageRoute(builder: (context) => const HomeAddPage()),
                );
              },
            ),
            const SizedBox(height: 12),
            _buildActionCard(
              icon: Icons.unarchive,
              color: Colors.blue,
              title: "Import Project (.zip)",
              onTap: () async {
                // 1. Close the menu immediately using its specific context
                Navigator.pop(dialogContext);

                // 2. Pick the file
                FilePickerResult? result = await FilePicker.platform.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: ['zip'],
                );

                // 3. EXIT if cancelled or if the user left the screen
                if (result == null || result.files.single.path == null) return;
                if (!mounted) return;

                // 4. SHOW SPINNER using the STABLE homeContext
                // We check homeContext.mounted to be 100% safe
                if (homeContext.mounted) {
                  showDialog(
                    context: homeContext,
                    barrierDismissible: false,
                    builder: (loadingContext) => const PopScope(
                      canPop: false,
                      child: AlertDialog(
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 20),
                            Text("Importing Project..."),
                          ],
                        ),
                      ),
                    ),
                  );
                }

                try {
                  // 5. RUN IMPORT
                  bool success = await ImportService.executeImport(homeContext, result);

                  // 6. DISMISS SPINNER safely
                  if (homeContext.mounted) {
                    Navigator.of(homeContext, rootNavigator: true).pop();
                  }

                  if (success) {
                    _loadFolders();
                    ScaffoldMessenger.of(homeContext).showSnackBar(
                      const SnackBar(content: Text("Import Successful!")),
                    );
                  }
                } catch (e) {
                  if (homeContext.mounted) {
                    Navigator.of(homeContext, rootNavigator: true).pop();
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required Color color,
    required String title,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          child: Row(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> alphaSortedData = List.from(_foldersData);
    alphaSortedData.sort((a, b) => a['title'].toString().toLowerCase().compareTo(b['title'].toString().toLowerCase()));

    // Filtering logic
    final List<Map<String, dynamic>> filteredData = alphaSortedData.where((item) {
      final matchesSearch = item['title'].toString().toLowerCase().contains(_searchQuery.toLowerCase());
      final matchesType = _projectFilter == 'all' || item['type'] == _projectFilter;
      return matchesSearch && matchesType;
    }).toList();

    final int recentCount = _foldersData.length > 4 ? 4 : _foldersData.length;

    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: Scaffold(
        body: Container(
          width: double.infinity,
          height: double.infinity,
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
          child: SingleChildScrollView(
            child: Column(
              children: [
                // --- RECENT ITEMS AREA ---
                Column(
                  children: [
                    SizedBox(height: 20,),
                    Container(
                      padding: const EdgeInsets.all(20),
                      height: 320,
                      width: double.infinity,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.help_outline, color: Colors.white),
                                tooltip: 'Help',
                                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const HelpPage())),
                              ),
                              IconButton(
                                icon: const Icon(Icons.info_outline, color: Colors.white),
                                tooltip: 'About',
                                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const AboutPage())),
                              ),
                            ],
                          ),
                          Image.asset('assets/logo.png', height: 80, fit: BoxFit.contain),
                          const Text('Recent Items', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold,color: Colors.white)),
                          const SizedBox(height:10),
                          Expanded(
                            flex: 1,
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              height: 300,
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    const SizedBox(width: 5),

                                    GestureDetector(
                                      onTap: _showAddOptions,
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
                                    const SizedBox(width: 5),
                                  ],
                                ),
                              ),
                            ),
                          )
                        ],
                      )
                    ),
                    // --- ALL PROJECTS AREA ---
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(30),
                        color: Colors.grey[100],
                      ),

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
              ],
            ),
          ),
        ),
      ),
    );
  }
}