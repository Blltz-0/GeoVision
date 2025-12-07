import 'package:flutter/material.dart';
import '../functions/metadata_handle.dart';

class ClassSelectorBar extends StatefulWidget {
  final String projectName;
  final String selectedClass; // The currently active filter
  final Function(String) onClassSelected; // Callback to parent

  const ClassSelectorBar({
    super.key,
    required this.projectName,
    required this.selectedClass,
    required this.onClassSelected,
  });

  @override
  State<ClassSelectorBar> createState() => _ClassSelectorBarState();
}

class _ClassSelectorBarState extends State<ClassSelectorBar> {
  List<Map<String, dynamic>> _projectClasses = [];

  @override
  void initState() {
    super.initState();
    _loadClasses();
  }

  Future<void> _loadClasses() async {
    final classes = await MetadataService.getClasses(widget.projectName);
    setState(() => _projectClasses = classes);
  }

  void _showAddDialog() {
    final nameCtrl = TextEditingController();

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
    return SizedBox(
      height: 50,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        children: [
          // 1. "ALL" or "NO TAG" Option (Optional, depends on page)
          _buildPill("All", Colors.grey, widget.selectedClass == "All"),

          // 2. Dynamic Classes
          ..._projectClasses.map((cls) => _buildPill(
              cls['name'],
              Color(cls['color']),
              widget.selectedClass == cls['name']
          )),

          // 3. Add Button
          IconButton(
            icon: const Icon(Icons.add_circle, color: Colors.blue),
            onPressed: _showAddDialog,
          ),
        ],
      ),
    );
  }

  Widget _buildPill(String label, Color color, bool isSelected) {
    return GestureDetector(
      onTap: () => widget.onClassSelected(label),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color),
          boxShadow: isSelected ? [const BoxShadow(color: Colors.black26, blurRadius: 4)] : [],
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : color,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}