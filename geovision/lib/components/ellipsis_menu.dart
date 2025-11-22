import 'package:flutter/material.dart';

class EllipsisMenu extends StatelessWidget {
  // 1. Define the functions we expect the parent to provide
  final VoidCallback onInfo;
  final VoidCallback onDelete;

  const EllipsisMenu({
    super.key,
    required this.onInfo,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      // 2. Handle the selection
      onSelected: (String value) {
        if (value == 'Info') {
          onInfo(); // Call the parent's function
        } else if (value == 'Delete') {
          onDelete(); // Call the parent's function
        }
      },
      // 3. Draw the items
      itemBuilder: (BuildContext context) {
        return [
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