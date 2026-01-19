import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'project_container.dart';

class HomeAddPage extends StatefulWidget {
  const HomeAddPage({super.key});

  @override
  State<HomeAddPage> createState() => _HomeAddPageState();
}

class _HomeAddPageState extends State<HomeAddPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _authorController = TextEditingController();
  final TextEditingController _descController = TextEditingController();

  String _selectedType = 'classification';
  bool _isCreating = false;

  @override
  void dispose() {
    _nameController.dispose();
    _authorController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<bool> _createProjectFolder() async {
    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      final folderName = _nameController.text.trim();
      final projectDirPath = '${appDocDir.path}/projects/$folderName';
      final newProjectDir = Directory(projectDirPath);

      if (await newProjectDir.exists()) {
        return false; // Project already exists
      }

      // 1. Create Directories
      await newProjectDir.create(recursive: true);
      await Directory('$projectDirPath/images').create();

      // 2. Write Metadata Files
      await File('$projectDirPath/project_type.txt').writeAsString(_selectedType);
      await File('$projectDirPath/last_opened.txt').writeAsString(DateTime.now().toIso8601String());

      // New: Author and Description
      if (_authorController.text.isNotEmpty) {
        await File('$projectDirPath/author.txt').writeAsString(_authorController.text.trim());
      }
      if (_descController.text.isNotEmpty) {
        await File('$projectDirPath/description.txt').writeAsString(_descController.text.trim());
      }

      return true;
    } catch (e) {
      debugPrint("Error creating project: $e");
      return false;
    }
  }

  void _submit() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isCreating = true);

      bool success = await _createProjectFolder();

      if (!mounted) return;

      if (success) {
        // Navigate directly to the new project
        Navigator.pop(context); // Close Add Page
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ProjectContainerPage(projectName: _nameController.text.trim()),
          ),
        );
      } else {
        setState(() => _isCreating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("A project with this name already exists."),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Create New Project"),
        backgroundColor: Colors.lightGreenAccent,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Project Details", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),

              // Project Name
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: "Project Name",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.folder),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) return "Please enter a name";
                  if (value.contains(RegExp(r'[<>:"/\\|?*]'))) return "Invalid characters in name";
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // Author
              TextFormField(
                controller: _authorController,
                decoration: const InputDecoration(
                  labelText: "Author (Optional)",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 20),

              // Description
              TextFormField(
                controller: _descController,
                decoration: const InputDecoration(
                  labelText: "Description (Optional)",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.description),
                  alignLabelWithHint: true,
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 20),

              const Divider(),
              const SizedBox(height: 10),

              const Text("Configuration", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 15),

              // --- NEW MODE SELECTION BUTTONS ---
              Row(
                children: [
                  Expanded(
                    child: _buildModeCard(
                      label: "Classification",
                      value: "classification",
                      icon: Icons.grid_view,
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: _buildModeCard(
                      label: "Segmentation",
                      value: "segmentation",
                      icon: Icons.brush,
                    ),
                  ),
                ],
              ),
              // ----------------------------------

              const SizedBox(height: 40),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.lightGreen,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _isCreating ? null : _submit,
                  child: _isCreating
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text("Create Project", style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModeCard({
    required String label,
    required String value,
    required IconData icon,
  }) {
    final bool isSelected = _selectedType == value;

    return InkWell(
      onTap: () {
        setState(() {
          _selectedType = value;
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
        decoration: BoxDecoration(
          color: isSelected ? Colors.lightGreenAccent.withOpacity(0.2) : Colors.white,
          border: Border.all(
            color: isSelected ? Colors.lightGreen : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 40,
              color: isSelected ? Colors.green[800] : Colors.grey[600],
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? Colors.green[900] : Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}