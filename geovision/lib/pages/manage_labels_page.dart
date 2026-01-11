import 'package:flutter/material.dart';
import '../components/label_creator.dart';
import '../functions/metadata_handle.dart';

class ManageLabelsPage extends StatefulWidget {
  final String projectName;
  const ManageLabelsPage({super.key, required this.projectName});

  @override
  State<ManageLabelsPage> createState() => _ManageLabelsPageState();
}

class _ManageLabelsPageState extends State<ManageLabelsPage> {
  List<Map<String, dynamic>> _labels = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLabels();
  }

  Future<void> _loadLabels() async {
    // You must ensure MetadataService.getLabels() exists
    final data = await MetadataService.getLabels(widget.projectName);
    if (mounted) setState(() { _labels = data; _isLoading = false; });
  }

  Future<void> _confirmDelete(String labelName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Label?"),
        content: Text("Are you sure you want to delete tag '$labelName'?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await MetadataService.deleteLabel(widget.projectName, labelName);
      _loadLabels();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Manage Labels"),
        backgroundColor: Colors.lightGreenAccent,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _labels.isEmpty
          ? const Center(child: Text("No labels created yet."))
          : ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _labels.length,
        separatorBuilder: (ctx, i) => const Divider(),
        itemBuilder: (ctx, index) {
          final lbl = _labels[index];
          return ListTile(
            leading: Icon(Icons.label, color: Color(lbl['color'])),
            title: Text(lbl['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.lightGreenAccent),
                  onPressed: () async {
                    await Navigator.push(context, MaterialPageRoute(
                      builder: (context) => CreateLabelPage(
                        projectName: widget.projectName,
                        initialName: lbl['name'],
                        initialColor: Color(lbl['color']),
                      ),
                    ));
                    _loadLabels();
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _confirmDelete(lbl['name']),
                ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.lightGreenAccent,
        child: const Icon(Icons.add),
        onPressed: () async {
          await Navigator.push(context, MaterialPageRoute(
            builder: (context) => CreateLabelPage(projectName: widget.projectName),
          ));
          _loadLabels();
        },
      ),
    );
  }
}