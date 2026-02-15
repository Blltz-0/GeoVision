import 'package:flutter/material.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'class_creator.dart';

class ClassSelectorDropdown extends StatefulWidget {
  final String projectName;
  final String selectedClass;
  final Function(String) onClassSelected;
  final bool showAllOption;

  final List<dynamic> classes;
  final VoidCallback? onClassAdded;

  const ClassSelectorDropdown({
    super.key,
    required this.projectName,
    required this.selectedClass,
    required this.onClassSelected,
    required this.classes,
    this.onClassAdded,
    this.showAllOption = true,
  });

  @override
  State<ClassSelectorDropdown> createState() => _ClassSelectorDropdownState();
}

class _ClassSelectorDropdownState extends State<ClassSelectorDropdown> {

  void _showAddDialog() async {
    final String? newClassName = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreateClassPage(projectName: widget.projectName),
      ),
    );

    if (newClassName != null && mounted) {
      widget.onClassAdded?.call();
      widget.onClassSelected(newClassName);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Value text color depends on mode
    final Color valueColor = widget.showAllOption ? Colors.black : Colors.white;
    const Color labelColor = Colors.grey;

    return Container(
      height: 56,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.only(left: 16, right: 4),
      decoration: BoxDecoration(
          color: widget.showAllOption ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(25),
          border: Border.all(
            color: widget.showAllOption ? Colors.grey.shade300 : Colors.white,
            width: 1,
          )
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // --- 1. LABEL  ---
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    "SELECT CLASS",
                    style: TextStyle(
                      color: labelColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),

                // --- 2. THE DROPDOWN ---
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
                          height: 30,
                          width: double.infinity,
                          padding: EdgeInsets.zero,
                        ),
                        dropdownStyleData: DropdownStyleData(
                          offset: const Offset(0, -10),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            color: widget.showAllOption ? Colors.white : Colors.black87,
                            border: Border.all(color: Colors.grey),
                          ),
                          maxHeight: 250,
                        ),
                        menuItemStyleData: const MenuItemStyleData(
                          height: 40,
                        ),
                        iconStyleData: const IconStyleData(
                          icon: Icon(Icons.arrow_drop_down, color: Colors.blue),
                          iconSize: 20,
                        ),

                        items: [
                          if (widget.showAllOption)
                            DropdownMenuItem(
                              value: "All",
                              child: Text("All Images", style: TextStyle(color: valueColor, fontWeight: FontWeight.w600)),
                            ),

                          DropdownMenuItem(
                            value: "Unclassified",
                            child: Text("Unclassified", style: TextStyle(color: valueColor, fontWeight: FontWeight.w600)),
                          ),

                          ...widget.classes.map((cls) {
                            return DropdownMenuItem<String>(
                              value: cls['name'],
                              child: Row(
                                children: [
                                  Container(
                                    width: 10, height: 10,
                                    decoration: BoxDecoration(
                                      color: Color(cls['color']),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    cls['name'],
                                    style: TextStyle(color: valueColor, fontWeight: FontWeight.w600),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            );
                          }),
                        ]
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 1,
            height: 40,
            child: DecoratedBox(decoration: BoxDecoration(border: Border(left: BorderSide(color: Colors.grey.shade300, width: 1)),),),),
          // Add Button
          IconButton(
            icon: const Icon(Icons.add_circle, color: Colors.blue),
            onPressed: _showAddDialog,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(), // Compact icon
          ),
        ],
      ),
    );
  }

  String? _checkValue(String val) {
    if (val == "All" && widget.showAllOption) return "All";
    if (val == "Unclassified") return "Unclassified";

    bool exists = widget.classes.any((c) => c['name'] == val);
    if (exists) return val;

    return widget.showAllOption ? "All" : "Unclassified";
  }
}