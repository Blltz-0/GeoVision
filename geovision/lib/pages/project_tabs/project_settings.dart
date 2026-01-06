import 'package:flutter/material.dart';

class ProjectSettings extends StatelessWidget {
  final String projectName;

  // Callbacks to trigger functions in the parent widget
  final VoidCallback onManageClasses;
  final VoidCallback onManageLabels;
  final VoidCallback onRenameProject;
  final VoidCallback onDeleteProject;

  const ProjectSettings({
    super.key,
    required this.projectName,
    required this.onManageClasses,
    required this.onManageLabels,
    required this.onRenameProject,
    required this.onDeleteProject,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50], // Light background
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          _buildSectionHeader("Project Configuration"),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.folder_copy, size: 60, color: Colors.amber,),
              const SizedBox(width: 20),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Project Name",
                    style: TextStyle(color: Colors.grey, fontSize: 20)),
                  Text(
                    projectName,
                    style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
                  ),
                ],
              )
            ]
          ),
          const SizedBox(height: 40),

          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                _buildSettingsTile(
                  icon: Icons.category,
                  color: Colors.blue,
                  title: "Manage Classes",
                  subtitle: "Add or edit image classifications",
                  onTap: onManageClasses,
                ),
                _buildSettingsTile(
                  icon: Icons.label,
                  color: Colors.lightBlue,
                  title: "Manage Labels",
                  subtitle: "Add or edit image annotation labels",
                  onTap: onManageLabels,
                ),
                const Divider(height: 1),
                _buildSettingsTile(
                  icon: Icons.drive_file_rename_outline,
                  color: Colors.orange,
                  title: "Rename Project",
                  subtitle: "Change the project folder name",
                  onTap: onRenameProject,
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: _buildSettingsTile(
              icon: Icons.delete_forever,
              color: Colors.red,
              title: "Delete Project",
              subtitle: "Permanently remove this project and all images",
              onTap: onDeleteProject,
              textColor: Colors.red,
            ),
          ),

          const SizedBox(height: 40),
          Center(
            child: Text(
              "Project: $projectName",
              style: TextStyle(color: Colors.grey[400], fontSize: 12),
            ),
          ),
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
          color: color.withOpacity(0.1),
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