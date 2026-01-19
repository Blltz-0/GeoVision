import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

class ProjectSettings extends StatefulWidget {
  final String projectName;
  final String projectType;
  final VoidCallback onManageClasses;
  final VoidCallback onManageLabels;
  final VoidCallback onRenameProject;
  final VoidCallback onDeleteProject;

  const ProjectSettings({
    super.key,
    required this.projectName,
    required this.projectType,
    required this.onManageClasses,
    required this.onManageLabels,
    required this.onRenameProject,
    required this.onDeleteProject,
  });

  @override
  State<ProjectSettings> createState() => _ProjectSettingsState();
}

class _ProjectSettingsState extends State<ProjectSettings> {
  String _author = "";
  String _description = "";
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMetadata();
  }

  Future<void> _loadMetadata() async {
    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      final projectPath = '${appDocDir.path}/projects/${widget.projectName}';

      String auth = "";
      String desc = "";

      final authFile = File('$projectPath/author.txt');
      if (await authFile.exists()) {
        auth = await authFile.readAsString();
      }

      final descFile = File('$projectPath/description.txt');
      if (await descFile.exists()) {
        desc = await descFile.readAsString();
      }

      if (mounted) {
        setState(() {
          _author = auth;
          _description = desc;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- SAVE FUNCTIONS ---

  Future<void> _saveAuthor(String newAuthor) async {
    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      final authFile = File('${appDocDir.path}/projects/${widget.projectName}/author.txt');

      await authFile.writeAsString(newAuthor.trim());

      if (mounted) {
        setState(() => _author = newAuthor.trim());
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Author updated.")));
      }
    } catch (e) {
      debugPrint("Error saving author: $e");
    }
  }

  Future<void> _saveDescription(String newDesc) async {
    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      final descFile = File('${appDocDir.path}/projects/${widget.projectName}/description.txt');

      await descFile.writeAsString(newDesc.trim());

      if (mounted) {
        setState(() => _description = newDesc.trim());
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Description updated.")));
      }
    } catch (e) {
      debugPrint("Error saving description: $e");
    }
  }

  // --- DIALOGS ---

  void _showEditAuthorDialog() {
    final controller = TextEditingController(text: _author);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Edit Author"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: "Author Name",
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.person),
          ),
          textCapitalization: TextCapitalization.words,
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _saveAuthor(controller.text);
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  void _showEditDescriptionDialog() {
    final controller = TextEditingController(text: _description);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Edit Description"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: "Project Description",
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.description),
            hintText: "Enter a brief description...",
          ),
          maxLines: 4,
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _saveDescription(controller.text);
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Determine display text
    final displayAuthor = _author.isNotEmpty ? "By $_author" : "Author: Unknown";
    final displayDesc = _description.isNotEmpty ? _description : "No description provided.";

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // --- TOP HEADER (Info Only) ---
          const SizedBox(height: 20),
          Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.folder_copy, size: 70, color: Colors.amber,),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Project Name
                      Text(
                        widget.projectName,
                        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                      ),

                      // Mode
                      Text(
                        widget.projectType == 'segmentation' ? "Segmentation Mode" : "Classification Mode",
                        style: const TextStyle(color: Colors.blueGrey, fontSize: 13, fontStyle: FontStyle.italic),
                      ),

                      const SizedBox(height: 8),

                      // Author (Plain Text)
                      Text(
                        displayAuthor,
                        style: TextStyle(fontSize: 14, color: Colors.grey[800], fontWeight: FontWeight.w500),
                      ),

                      const SizedBox(height: 4),

                      // Description (Plain Text)
                      Text(
                        displayDesc,
                        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                )
              ]
          ),

          const SizedBox(height: 30),

          // --- DATA SETTINGS SECTION ---
          _buildSectionHeader("Data Management"),
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                if (widget.projectType == 'classification')
                  _buildSettingsTile(
                    icon: Icons.category,
                    color: Colors.blue,
                    title: "Manage Classes",
                    subtitle: "Add or edit image classifications",
                    onTap: widget.onManageClasses,
                  ),

                if (widget.projectType == 'segmentation')
                  _buildSettingsTile(
                    icon: Icons.label,
                    color: Colors.lightBlue,
                    title: "Manage Labels",
                    subtitle: "Add or edit image annotation labels",
                    onTap: widget.onManageLabels,
                  ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // --- PROJECT CONFIGURATION SECTION ---
          _buildSectionHeader("Project Configuration"),
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                // Edit Author
                _buildSettingsTile(
                  icon: Icons.person_outline,
                  color: Colors.purple,
                  title: "Edit Author",
                  subtitle: "Change project author name",
                  onTap: _showEditAuthorDialog,
                ),
                const Divider(height: 1),

                // Edit Description
                _buildSettingsTile(
                  icon: Icons.description_outlined,
                  color: Colors.teal,
                  title: "Edit Description",
                  subtitle: "Update project description",
                  onTap: _showEditDescriptionDialog,
                ),
                const Divider(height: 1),

                // Rename
                _buildSettingsTile(
                  icon: Icons.drive_file_rename_outline,
                  color: Colors.orange,
                  title: "Rename Project",
                  subtitle: "Change the project folder name",
                  onTap: widget.onRenameProject,
                ),
                const Divider(height: 1),

                // Delete
                _buildSettingsTile(
                  icon: Icons.delete_forever,
                  color: Colors.red,
                  title: "Delete Project",
                  subtitle: "Permanently remove this project",
                  onTap: widget.onDeleteProject,
                  textColor: Colors.red,
                ),
              ],
            ),
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 8.0, bottom: 8.0),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: Colors.grey,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? textColor,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha:0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: textColor ?? Colors.black87,
        ),
      ),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: onTap,
    );
  }
}