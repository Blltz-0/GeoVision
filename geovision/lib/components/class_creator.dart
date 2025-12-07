import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../functions/metadata_handle.dart'; // Import your service

class CreateClassPage extends StatefulWidget {
  final String projectName;

  const CreateClassPage({super.key, required this.projectName});

  @override
  State<CreateClassPage> createState() => _CreateClassPageState();
}

class _CreateClassPageState extends State<CreateClassPage> {
  // State variables
  final TextEditingController _nameController = TextEditingController();
  Color _currentColor = Colors.red; // Default start color

  // Helper to get HEX string (e.g., #FF0000)
  String get _hexCode {
    return '#${_currentColor.value.toRadixString(16).toUpperCase().padLeft(8, '0').substring(2)}';
  }

  Future<void> _saveClass() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter a class name")),
      );
      return;
    }

    // Call your existing service
    await MetadataService.addClassDefinition(
      widget.projectName,
      _nameController.text.trim(),
      _currentColor.value,
    );

    if (mounted) {
      // Return the new name so the previous page can auto-select it
      Navigator.pop(context, _nameController.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.lightGreenAccent,
        title: const Text("Create New Class"),
        actions: [
          // Save Button
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
            // ---------------------------------------------
            // 1. PREVIEW SECTION
            // ---------------------------------------------
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              color: Colors.grey[100],
              child: Column(
                children: [
                  // The "Chip" Preview
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                        color: _currentColor,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 5, offset: const Offset(0, 2))
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
                  // The Hex Code
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

            // ---------------------------------------------
            // 2. INPUT SECTION
            // ---------------------------------------------
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
                onChanged: (val) => setState(() {}), // Updates preview text
              ),
            ),

            const Divider(),

            // ---------------------------------------------
            // 3. PRESETS (Block Picker)
            // ---------------------------------------------
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

            // ---------------------------------------------
            // 4. CUSTOM WHEEL (Color Picker)
            // ---------------------------------------------
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
              labelTypes: const [], // Hides the internal text inputs since we made our own
              pickerAreaHeightPercent: 0.7,
            ),

            const SizedBox(height: 50), // Bottom padding
          ],
        ),
      ),
    );
  }
}