import 'package:flutter/material.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import '../functions/metadata_handle.dart';
import 'class_creator.dart';

class ClassSelectorDropdown extends StatefulWidget {
  final String projectName;
  final String selectedClass; // The currently active filter
  final Function(String) onClassSelected;
  final bool showAllOption;

  const ClassSelectorDropdown({
    super.key,
    required this.projectName,
    required this.selectedClass,
    required this.onClassSelected,
    this.showAllOption = true,
  });

  @override
  State<ClassSelectorDropdown> createState() => _ClassSelectorDropdownState();
}

class _ClassSelectorDropdownState extends State<ClassSelectorDropdown> {
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

  void _showAddDialog() async {
    // 1. Navigate to the new page
    // We wait for the result (the new class name)
    final String? newClassName = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreateClassPage(projectName: widget.projectName),
      ),
    );

    // 2. If user saved (didn't press back)
    if (newClassName != null && mounted) {
      await _loadClasses(); // Refresh the list from disk
      widget.onClassSelected(newClassName); // Auto-select the new class
    }
  }

  @override
  Widget build(BuildContext context) {
    List<DropdownMenuItem<String>> menuItems = [];

    if (widget.showAllOption) {
      menuItems.add(
        const DropdownMenuItem(
          value: "All",
          child: Text("All Classes", style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      );
    }

    if (!widget.showAllOption) {
      menuItems.add(
        const DropdownMenuItem(
          value: "Unclassified",
          child: Row(
            children: [
              Icon(Icons.help_outline, size: 16, color: Colors.grey),
              SizedBox(width: 8),
              Text("Unclassified"),
            ],
          ),
        ),
      );
    }

    for (var classes in _projectClasses) {
      menuItems.add(
        DropdownMenuItem<String>(
          value: classes['name'],
          child: Row(
            children: [
              Container(
                width: 12, height: 12,
                decoration: BoxDecoration(
                  color: Color(classes['color']),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Text(classes['name']),
            ],
          ),
        ),
      );
    }

    return Container(
      height: 50,
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: EdgeInsets.symmetric(horizontal: 12),


      decoration: BoxDecoration(
        color: widget.showAllOption ? Colors.white: Colors.transparent,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: Colors.white,
          width: 1,
        )
      ),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton2<String>(
                value: _checkValue(widget.selectedClass),
                isExpanded: true,
                onChanged: (String? newValue) {
                  if (newValue != null) {
                    widget.onClassSelected(newValue);
                  }
                },
                buttonStyleData: const ButtonStyleData(
                  height: 50,
                  width: double.infinity,
                  padding: EdgeInsets.only(right: 8), // Padding for the arrow
                ),

                dropdownStyleData: DropdownStyleData(
                  // THIS IS THE MAGIC FIX:
                  // Offset(0, -4) pushes the menu slightly up/down relative to the button.
                  // By defining this, we stop the "jump to selection" behavior.
                  offset: const Offset(0, -4),

                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: widget.showAllOption ? Colors.white: Colors.transparent,
                    border: Border.all(
                      color: widget.showAllOption ? Colors.black: Colors.white,
                      width: 1,
                    ),
                  ),
                  maxHeight: 200, // Scroll if list is too long
                ),
                menuItemStyleData: const MenuItemStyleData(
                  height: 40,

                ),
                iconStyleData: const IconStyleData(
                  icon: Icon(Icons.arrow_drop_down, color: Colors.blue),
                  iconSize: 24,
                ),

              items: [
                if (widget.showAllOption)
                  DropdownMenuItem(
                    value: "All",
                    child: Text("All",style: TextStyle(color: widget.showAllOption ? Colors.black: Colors.white,),),
                  ),

                  DropdownMenuItem(
                    value: "Unclassified",
                    child: Text("Unclassified",style: TextStyle(color: widget.showAllOption ? Colors.black: Colors.white,),),
                  ),

                ..._projectClasses.map((classes) {
                  return DropdownMenuItem<String>(
                    value: classes['name'],
                    child: Row(
                      children: [
                        Container(
                          width: 12, height: 12,
                          decoration: BoxDecoration(
                            color: Color(classes['color']),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(classes['name'],style: TextStyle(color: widget.showAllOption ? Colors.black: Colors.white,),),
                      ],
                    ),
                  );
                }),
              ],

            )),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle, color: Colors.blue),
            onPressed: _showAddDialog,
          ),
        ],
      ),

    );
  }

  String? _checkValue(String val) {
    if (val == "All" && widget.showAllOption) return "All";
    if (val == "Unclassified" && !widget.showAllOption) return "Unclassified";

    // Check if value exists in loaded classes
    bool exists = _projectClasses.any((c) => c['name'] == val);
    if (exists) return val;

    // Fallback
    return widget.showAllOption ? "All" : "Unclassified";
  }
}
