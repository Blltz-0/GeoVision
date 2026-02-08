import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../functions/metadata_handle.dart';

class CreateLabelPage extends StatefulWidget {
  final String projectName;

  // Edit Mode if provided
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

enum ColorPickerTab { quick, custom }

class _CreateLabelPageState extends State<CreateLabelPage> {
  late TextEditingController _nameController;
  late Color _currentColor;

  ColorPickerTab _activeTab = ColorPickerTab.quick;

  bool get _isEditing => widget.initialName != null;

  @override
  void initState() {
    super.initState();
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
        const SnackBar(content: Text("Please enter a label name")),
      );
      return;
    }

    if (_isEditing) {
      await MetadataService.updateLabel(
        widget.projectName,
        widget.initialName!,
        newName,
        _currentColor.toARGB32(),
      );
    } else {
      await MetadataService.addLabelDefinition(
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
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Color(0xFFAED581),
                Color(0xFF9CCC65),
                Color(0xFF9CCC65),
                Color(0xFF8BC34A),
                Color(0xFF8BC34A),
                Color(0xFF7CB342),
                Color(0xFF689F38),
              ],
            ),
          ),
        ),
        title: Text(_isEditing ? "Edit Label" : "Create New Label"),
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
            // PREVIEW
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              color: Colors.grey[100],
              child: Column(
                children: [
                  Container(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: _currentColor,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha:0.2),
                          blurRadius: 5,
                          offset: const Offset(0, 2),
                        )
                      ],
                    ),
                    child: Text(
                      _nameController.text.isEmpty
                          ? "Label Name"
                          : _nameController.text,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    "HEX: $_hexCode",
                    style: TextStyle(
                      color: Colors.grey[700],
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),

            // NAME INPUT
            Padding(
              padding: const EdgeInsets.all(20),
              child: TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: "Label Name",
                  hintText: "e.g. Crack, Pothole, Vegetation",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.label_outline),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),

            const Divider(),

            // TAB SELECTOR
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(
                children: [
                  _ColorTabButton(
                    label: "Quick Colors",
                    icon: Icons.palette,
                    isActive: _activeTab == ColorPickerTab.quick,
                    onTap: () {
                      setState(() => _activeTab = ColorPickerTab.quick);
                    },
                  ),
                  const SizedBox(width: 12),
                  _ColorTabButton(
                    label: "Custom Color",
                    icon: Icons.color_lens,
                    isActive: _activeTab == ColorPickerTab.custom,
                    onTap: () {
                      setState(() => _activeTab = ColorPickerTab.custom);
                    },
                  ),
                ],
              ),
            ),

            // TAB CONTENT
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: _activeTab == ColorPickerTab.quick
                  ? Padding(
                key: const ValueKey('quick'),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: BlockPicker(
                  pickerColor: _currentColor,
                  onColorChanged: (color) =>
                      setState(() => _currentColor = color),
                  availableColors: const [
                    Colors.red,
                    Colors.pink,
                    Colors.purple,
                    Colors.deepPurple,
                    Colors.indigo,
                    Colors.blue,
                    Colors.lightBlue,
                    Colors.cyan,
                    Colors.teal,
                    Colors.green,
                    Colors.lightGreen,
                    Colors.lime,
                    Colors.yellow,
                    Colors.amber,
                    Colors.orange,
                    Colors.deepOrange,
                    Colors.brown,
                    Colors.grey,
                    Colors.blueGrey,
                    Colors.black,
                  ],
                ),
              )
                  : Padding(
                key: const ValueKey('custom'),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: ColorPicker(
                  pickerColor: _currentColor,
                  onColorChanged: (color) =>
                      setState(() => _currentColor = color),
                  enableAlpha: false,
                  displayThumbColor: true,
                  paletteType: PaletteType.hsvWithHue,
                  labelTypes: const [],
                  pickerAreaHeightPercent: 0.7,
                ),
              ),
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

class _ColorTabButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  const _ColorTabButton({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isActive ? Colors.lightGreen : Colors.grey[200],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: isActive ? Colors.white : Colors.grey[700],
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isActive ? Colors.white : Colors.grey[700],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
