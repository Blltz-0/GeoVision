import 'package:flutter/material.dart';
import '../components/class_creator.dart';
import '../functions/metadata_handle.dart';

class ManageClassesPage extends StatefulWidget {
  final String projectName;

  const ManageClassesPage({super.key, required this.projectName});

  @override
  State<ManageClassesPage> createState() => _ManageClassesPageState();
}

class _ManageClassesPageState extends State<ManageClassesPage> {
  List<Map<String, dynamic>> _classes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadClasses();
  }

  Future<void> _loadClasses() async {
    setState(() => _isLoading = true);
    final data = await MetadataService.getClasses(widget.projectName);
    if (mounted) {
      setState(() {
        _classes = data;
        _isLoading = false;
      });
    }
  }

  // --- DELETE LOGIC ---
  Future<void> _confirmDelete(String className) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Class?"),
        content: Text(
            "Are you sure you want to delete '$className'?\n\n"
                "All images currently labeled as '$className' will be set to 'Unclassified'."
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Delete & Reclassify"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await MetadataService.deleteClass(widget.projectName, className);
      _loadClasses(); // Refresh list
    }
  }

  // --- EDIT LOGIC ---
  void _navigateToEditPage(Map<String, dynamic> classData) async {
    // Navigate to CreateClassPage in "Edit Mode"
    // We pass the existing name and color via the new optional parameters
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreateClassPage(
          projectName: widget.projectName,
          initialName: classData['name'],
          initialColor: Color(classData['color']),
        ),
      ),
    );

    // If result is not null, the user saved changes
    if (result != null && mounted) {
      _loadClasses(); // Refresh the list to show new name/color
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Manage Classes"),
        backgroundColor: Colors.lightGreenAccent, // Matches your app theme
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _classes.isEmpty
          ? const Center(child: Text("No classes defined."))
          : ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _classes.length,
        separatorBuilder: (ctx, i) => const Divider(),
        itemBuilder: (ctx, index) {
          final cls = _classes[index];
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            leading: CircleAvatar(
              backgroundColor: Color(cls['color']),
              radius: 18,
            ),
            title: Text(
              cls['name'],
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Edit Button -> Navigates to CreateClassPage
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.blue),
                  onPressed: () => _navigateToEditPage(cls),
                  tooltip: 'Edit Class',
                ),
                // Delete Button -> Shows Confirmation
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _confirmDelete(cls['name']),
                  tooltip: 'Delete Class',
                ),
              ],
            ),
          );
        },
      ),
      // Optional: Add floating button to create new class from here as well
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.lightGreenAccent,
        child: const Icon(Icons.add),
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CreateClassPage(projectName: widget.projectName),
            ),
          );
          if (result != null && mounted) _loadClasses();
        },
      ),
    );
  }
}