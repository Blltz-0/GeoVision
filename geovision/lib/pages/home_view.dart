import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:geovision/pages/project_container.dart';
import '../components/image_grid.dart';

// 1. Change to StatefulWidget
class HomeViewPage extends StatefulWidget {
  final String title;

  const HomeViewPage({
    super.key,
    required this.title,
  });

  @override
  State<HomeViewPage> createState() => _HomeViewPageState();
}

class _HomeViewPageState extends State<HomeViewPage> {
  // This list stores the actual image files found on the phone
  List<File> _imageFiles = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadImages(); // Load images immediately when page opens
  }

  // --- LOGIC: Get the specific images folder ---
  Future<void> _loadImages() async {
    // 1. Get App Documents Directory
    final appDir = await getApplicationDocumentsDirectory();

    // 2. Construct path: .../projects/[ProjectName]/images
    final imagesDirPath = '${appDir.path}/projects/${widget.title}/images';
    final imagesDir = Directory(imagesDirPath);

    // 3. Check if it exists. If not, create it!
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }

    // 4. List files and filter for images (jpg, png, jpeg)
    if (await imagesDir.exists()) {
      final files = imagesDir.listSync().map((item) => item as File).where((item) {
        final ext = item.path.split('.').last.toLowerCase();
        return ext == 'jpg' || ext == 'png' || ext == 'jpeg';
      }).toList();

      setState(() {
        _imageFiles = files;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {

    // 5. Prepare data for your ImageGrid
    // We convert the File list into a List of Maps, because your grid likely expects Maps
    final List<Map<String, dynamic>> gridData = _imageFiles.map((file) {
      return {
        "path": file.path, // The ImageGrid needs this to display the image
        "file": file,      // Passing the actual File object is helpful too
      };
    }).toList();

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(widget.title), // Use widget.title in State class
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        child: Container(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('${widget.title} Images'),
              const SizedBox(height: 20),

              // 6. Pass the real data to the grid
              _imageFiles.isEmpty
                  ? const Center(child: Text("No images found."))
                  : ImageGrid(
                columns: 3,
                itemCount: gridData.length,
                dataList: gridData,
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: BottomAppBar(
        color: Colors.white,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            GestureDetector(
              onTap: () {
                Navigator.pop(context);
              },
              child: Container(
                  height: 40,
                  width: 100,
                  decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: Colors.white,
                      border: Border.all(
                        color: Colors.black54.withValues(alpha: 0.3), // fixed withValues syntax
                        width: 2,
                      )
                  ),
                  alignment: Alignment.center,
                  child: const Text("Back")
              ),
            ),
            GestureDetector(
              onTap: () {
                Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => ProjectContainerPage(projectName: widget.title,)),);
              },
              child: Container(
                  height: 40,
                  width: 100,
                  decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: Colors.blueAccent,
                      border: Border.all(
                        color: Colors.black54.withValues(alpha: 0.1),
                        width: 2,
                      )
                  ),
                  alignment: Alignment.center,
                  child: const Text("Confirm", style: TextStyle(
                    color: Colors.white,
                  ),)
              ),
            ),
          ],
        ),
      ),
    );
  }
}