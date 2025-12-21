import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../functions/metadata_handle.dart';

class CreateClassPage extends StatefulWidget {
  final String projectName;

  //Edit Mode if provided
  final String? initialName;
  final Color? initialColor;

  const CreateClassPage({
    super.key,
    required this.projectName,
    this.initialName,
    this.initialColor,
  });

  @override
  State<CreateClassPage> createState() => _CreateClassPageState();
}

class _CreateClassPageState extends State<CreateClassPage> {
  late TextEditingController _nameController;
  late Color _currentColor;

  bool get _isEditing => widget.initialName != null;

  @override
  void initState() {
    super.initState();
    // Pre-fill data if editing, otherwise use defaults
    _nameController = TextEditingController(text: widget.initialName ?? "");
    _currentColor = widget.initialColor ?? Colors.red;
  }

  String get _hexCode {
    return '#${_currentColor.toARGB32().toRadixString(16).toUpperCase().padLeft(8, '0').substring(2)}';
  }

  Future<void> _saveClass() async {
    final newName = _nameController.text.trim();
    if (newName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter a class name")),
      );
      return;
    }

    if (_isEditing) {
      // --- UPDATE EXISTING CLASS ---
      // We pass the OLD name (widget.initialName) so the service knows what to look for
      await MetadataService.updateClass(
          widget.projectName,
          widget.initialName!, // Old Name
          newName,             // New Name
          _currentColor.toARGB32()
      );
    } else {
      // --- CREATE NEW CLASS ---
      await MetadataService.addClassDefinition(
        widget.projectName,
        newName,
        _currentColor.toARGB32(),
      );
    }

    if (mounted) {
      Navigator.pop(context, newName);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.lightGreenAccent,
        // Change Title based on mode
        title: Text(_isEditing ? "Edit Class" : "Create New Class"),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: _saveClass,
          )
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // PREVIEW SECTION
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              color: Colors.grey[100],
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                        color: _currentColor,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha:0.2), blurRadius: 5, offset: const Offset(0, 2))
                        ]
                    ),
                    child: Text(
                      _nameController.text.isEmpty ? "Class Name" : _nameController.text,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    "HEX: $_hexCode",
                    style: TextStyle(
                        color: Colors.grey[700],
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace'
                    ),
                  ),
                ],
              ),
            ),

            // INPUT SECTION
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: "Class Name",
                  hintText: "e.g. Crack, Pothole, Vegetation",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.label_outline),
                ),
                onChanged: (val) => setState(() {}),
              ),
            ),

            const Divider(),

            // QUICK COLORS
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Text("Quick Colors", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: BlockPicker(
                pickerColor: _currentColor,
                onColorChanged: (color) => setState(() => _currentColor = color),
                availableColors: const [
                  Colors.red, Colors.pink, Colors.purple, Colors.deepPurple,
                  Colors.indigo, Colors.blue, Colors.lightBlue, Colors.cyan,
                  Colors.teal, Colors.green, Colors.lightGreen, Colors.lime,
                  Colors.yellow, Colors.amber, Colors.orange, Colors.deepOrange,
                  Colors.brown, Colors.grey, Colors.blueGrey, Colors.black,
                ],
              ),
            ),

            const Divider(),

            // CUSTOM WHEEL
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Text("Custom Color", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            ColorPicker(
              pickerColor: _currentColor,
              onColorChanged: (color) => setState(() => _currentColor = color),
              enableAlpha: false,
              displayThumbColor: true,
              paletteType: PaletteType.hsvWithHue,
              labelTypes: const [],
              pickerAreaHeightPercent: 0.7,
            ),
            const SizedBox(height: 50),
          ],
        ),
      ),
    );
  }
}