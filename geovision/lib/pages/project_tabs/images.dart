import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../components/image_grid.dart';

class ImagesPage extends StatefulWidget {
  final String projectName;

  const ImagesPage({
    super.key,
    required this.projectName,
  });

  @override
  State<ImagesPage> createState() => _ImagesPageState();
}

class _ImagesPageState extends State<ImagesPage> {
  List<File> _imageFiles=[];
  bool _isLoading=true;

  @override
  void initState() {
    super.initState();
    _loadImages(); // Load data on startup
  }

  Future<void> _loadImages() async {
    final appDir = await getApplicationDocumentsDirectory();
    // USE widget.projectName TO FIND THE CORRECT FOLDER
    final imagesDirPath = '${appDir.path}/projects/${widget.projectName}/images';
    final imagesDir = Directory(imagesDirPath);

    if (await imagesDir.exists()) {
      final files = imagesDir.listSync().map((item) => item as File).where((item) {
        final ext = item.path.split('.').last.toLowerCase();
        return ext == 'jpg' || ext == 'png' || ext == 'jpeg';
      }).toList();

      setState(() {
        _imageFiles = files;
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
    }
  }



  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> gridData = _imageFiles.map((file) {
      return {"path": file.path};
    }).toList();

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('GeoVision'),
      ),
      body: _isLoading ? const Center(child: CircularProgressIndicator()) : SingleChildScrollView(
        child: Container(
          padding: EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('${widget.projectName} Gallery'),
              SizedBox(height:20),
              _imageFiles.isEmpty
                  ? const Center(child: Text("No images yet"))
                  : ImageGrid(
                columns: 3,
                itemCount: gridData.length,
                dataList: gridData,
              ),
            ],
          ),
        ),
      ),
    );
  }
}