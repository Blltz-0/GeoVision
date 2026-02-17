import 'package:flutter/material.dart';
import '../../components/classes/class_creator.dart';
import '../../functions/data_service/metadata_handle.dart';

class ClassPickerDialog {
  static Future<String?> show({
    required BuildContext context,
    required String projectName,
    required VoidCallback? onClassesUpdated,
  }) async {
    String currentSelection = "Unclassified";
    final LayerLink layerLink = LayerLink();

    while (true) {
      List<dynamic> classes = await MetadataService.getClasses(projectName);
      if (!classes.any((c) => c['name'] == "Unclassified")) {
        classes.insert(0, {'name': 'Unclassified', 'color': Colors.grey.toARGB32()});
      }
      if (!context.mounted) return null;

      final String? result = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          OverlayEntry? dropdownOverlay;
          bool isDropdownOpen = false;

          void closeDropdown() {
            dropdownOverlay?.remove();
            dropdownOverlay = null;
            isDropdownOpen = false;
          }

          return StatefulBuilder(
            builder: (context, setStateDialog) {
              void toggleDropdown() {
                if (isDropdownOpen) {
                  closeDropdown();
                  setStateDialog(() {});
                  return;
                }
                dropdownOverlay = OverlayEntry(
                  builder: (context) {
                    return Stack(
                      children: [
                        Positioned.fill(
                          child: GestureDetector(
                            onTap: () {
                              closeDropdown();
                              setStateDialog(() {});
                            },
                            behavior: HitTestBehavior.translucent,
                            child: Container(color: Colors.transparent),
                          ),
                        ),
                        Positioned(
                          width: 200,
                          child: CompositedTransformFollower(
                            link: layerLink,
                            showWhenUnlinked: false,
                            offset: const Offset(0, 50),
                            child: Material(
                              elevation: 4,
                              borderRadius: BorderRadius.circular(8),
                              color: Colors.white,
                              child: Container(
                                constraints: const BoxConstraints(maxHeight: 250),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.grey.shade300),
                                ),
                                child: ListView(
                                  padding: EdgeInsets.zero,
                                  shrinkWrap: true,
                                  children: classes.where((c) => c['name'] != currentSelection).map((c) {
                                    return ListTile(
                                      dense: true,
                                      leading: CircleAvatar(backgroundColor: Color(c['color']), radius: 6),
                                      title: Text(c['name']),
                                      onTap: () {
                                        setStateDialog(() { currentSelection = c['name']; });
                                        closeDropdown();
                                      },
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                );
                Overlay.of(context).insert(dropdownOverlay!);
                isDropdownOpen = true;
                setStateDialog(() {});
              }
              final selectedClassData = classes.firstWhere((c) => c['name'] == currentSelection, orElse: () => {'color': Colors.grey.toARGB32()});
              Color selectedColor = Color(selectedClassData['color']);

              return PopScope(
                onPopInvokedWithResult: (_, _) => closeDropdown(),
                child: AlertDialog(
                  title: const Text("Assign Class"),
                  contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: CompositedTransformTarget(
                              link: layerLink,
                              child: InkWell(
                                onTap: toggleDropdown,
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  height: 48,
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(8)),
                                  child: Row(
                                    children: [
                                      CircleAvatar(backgroundColor: selectedColor, radius: 6),
                                      const SizedBox(width: 10),
                                      Expanded(child: Text(currentSelection, overflow: TextOverflow.ellipsis)),
                                      Icon(isDropdownOpen ? Icons.arrow_drop_up : Icons.arrow_drop_down, color: Colors.grey.shade700),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            height: 48, width: 48,
                            decoration: BoxDecoration(color: Colors.blue.withValues(alpha:0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue.withValues(alpha:0.3))),
                            child: IconButton(
                              icon: const Icon(Icons.add, color: Colors.blue),
                              onPressed: () {
                                closeDropdown();
                                Navigator.pop(dialogContext, "CREATE_NEW");
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                  actions: [
                    TextButton(onPressed: () { closeDropdown(); Navigator.pop(dialogContext, null); }, child: const Text("Cancel")),
                    FilledButton(onPressed: () { closeDropdown(); Navigator.pop(dialogContext, currentSelection); }, child: const Text("Select")),
                  ],
                ),
              );
            },
          );
        },
      );

      if (result == "CREATE_NEW") {
        if (!context.mounted) return null;
        await Navigator.push(context, MaterialPageRoute(builder: (context) => CreateClassPage(projectName: projectName)));
        onClassesUpdated?.call();
      } else {
        return result;
      }
    }
  }
}