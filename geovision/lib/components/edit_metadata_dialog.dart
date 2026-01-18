import 'package:flutter/material.dart';

// --- EDIT DIALOG ---
class EditMetadataDialog extends StatefulWidget {
  final String filename;
  final double initialLat;
  final double initialLng;
  final DateTime initialDate;
  final Function(double lat, double lng, DateTime date) onSave;

  const EditMetadataDialog({
    super.key,
    required this.filename,
    required this.initialLat,
    required this.initialLng,
    required this.initialDate,
    required this.onSave,
  });

  @override
  State<EditMetadataDialog> createState() => _EditMetadataDialogState();
}

class _EditMetadataDialogState extends State<EditMetadataDialog> {
  late TextEditingController _latController;
  late TextEditingController _lngController;
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    _latController = TextEditingController(text: widget.initialLat.toString());
    _lngController = TextEditingController(text: widget.initialLng.toString());
    _selectedDate = widget.initialDate;
  }

  @override
  void dispose() {
    _latController.dispose();
    _lngController.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (date == null) return;

    if (!mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedDate),
    );
    if (time == null) return;

    setState(() {
      _selectedDate = DateTime(
          date.year, date.month, date.day, time.hour, time.minute
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Edit Metadata"),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("File: ${widget.filename}", style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 15),

            const Text("Date & Time", style: TextStyle(fontWeight: FontWeight.bold)),
            InkWell(
              onTap: _pickDateTime,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: Colors.grey.shade400))
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("${_selectedDate.year}-${_selectedDate.month}-${_selectedDate.day}   ${_selectedDate.hour}:${_selectedDate.minute.toString().padLeft(2, '0')}"),
                    const Icon(Icons.edit_calendar, size: 20, color: Colors.blue),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 15),

            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _latController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    decoration: const InputDecoration(labelText: "Latitude", border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _lngController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    decoration: const InputDecoration(labelText: "Longitude", border: OutlineInputBorder()),
                  ),
                ),
              ],
            )
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
        ElevatedButton(
            onPressed: () {
              final lat = double.tryParse(_latController.text) ?? widget.initialLat;
              final lng = double.tryParse(_lngController.text) ?? widget.initialLng;
              widget.onSave(lat, lng, _selectedDate);
              Navigator.pop(context);
            },
            child: const Text("Save")
        ),
      ],
    );
  }
}