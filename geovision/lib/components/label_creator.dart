import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../functions/metadata_handle.dart';

class CreateLabelPage extends StatefulWidget {
  final String projectName;
  final String? initialName;
  final Color? initialColor;

  const CreateLabelPage({
    super.key,
    required this.projectName,
    this.initialName,
    this.initialColor,
  });

  @override
  State<CreateLabelPage> createState() => _CreateLabelPageState();
}

class _CreateLabelPageState extends State<CreateLabelPage> {
  late TextEditingController _nameController;
  late Color _currentColor;

  bool get _isEditing => widget.initialName != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName ?? "");
    // Default to Blue for labels to distinguish from Classes (Red default)
    _currentColor = widget.initialColor ?? Colors.blue;
  }

  Future<void> _saveLabel() async {
    final newName = _nameController.text.trim();
    if (newName.isEmpty) return;

    if (_isEditing) {
      await MetadataService.updateLabel(
          widget.projectName, widget.initialName!, newName, _currentColor.toARGB32());
    } else {
      await MetadataService.addLabelDefinition(
          widget.projectName, newName, _currentColor.toARGB32());
    }

    if (mounted) Navigator.pop(context, newName);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.lightBlueAccent, // Blue theme for Labels
        title: Text(_isEditing ? "Edit Label" : "Create New Label"),
        actions: [IconButton(icon: const Icon(Icons.check), onPressed: _saveLabel)],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Preview
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              color: Colors.grey[100],
              child: Column(
                children: [
                  Chip(
                    backgroundColor: _currentColor,
                    label: Text(
                      _nameController.text.isEmpty ? "Label Name" : _nameController.text,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
            // Input
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: "Label Name",
                  hintText: "e.g. Urgent, Verified, Blur",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.tag),
                ),
                onChanged: (val) => setState(() {}),
              ),
            ),
            const Divider(),
            // Color Picker (Simplified for brevity)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: BlockPicker(
                pickerColor: _currentColor,
                onColorChanged: (color) => setState(() => _currentColor = color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}