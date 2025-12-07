import 'package:flutter/material.dart';

class EllipsisMenu extends StatelessWidget {
  final VoidCallback onInfo;
  final VoidCallback onDelete;
  final VoidCallback onTag; // <--- 1. NEW CALLBACK

  const EllipsisMenu({
    super.key,
    required this.onInfo,
    required this.onDelete,
    required this.onTag, // <--- Require it
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: (String value) {
        if (value == 'Info') onInfo();
        if (value == 'Delete') onDelete();
        if (value == 'Tag') onTag();
      },
      itemBuilder: (BuildContext context) {
        return [
          // 1. TAG OPTION (Add this first or where you prefer)
          const PopupMenuItem(
            value: 'Tag',
            child: Row(
              children: [
                Icon(Icons.label, color: Colors.blue),
                SizedBox(width: 10),
                Text('Tag Image'),
              ],
            ),
          ),
          const PopupMenuDivider(), // Optional separator
          const PopupMenuItem(
            value: 'Info',
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.black54),
                SizedBox(width: 10),
                Text('Info'),
              ],
            ),
          ),
          const PopupMenuItem(
            value: 'Delete',
            child: Row(
              children: [
                Icon(Icons.delete, color: Colors.red),
                SizedBox(width: 10),
                Text('Delete', style: TextStyle(color: Colors.red)),
              ],
            ),
          ),
        ];
      },
    );
  }
}