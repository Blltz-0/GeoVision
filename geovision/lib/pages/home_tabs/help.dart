import 'package:flutter/material.dart';

class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Help & Support'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
              gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Colors.lightGreen[300]!,
                    Colors.lightGreen[400]!,
                    Colors.lightGreen[400]!,
                    Colors.lightGreen[500]!,
                    Colors.lightGreen[500]!,
                    Colors.lightGreen[600]!,
                    Colors.lightGreen[700]!,
                  ])
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          const Text(
            "Project Workflow",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          _buildWorkflowStep(Icons.looks_one, "Create", "Start a Classification or Segmentation project."),
          _buildWorkflowStep(Icons.looks_two, "Capture", "Use the camera with real-time GPS tagging."),
          _buildWorkflowStep(Icons.looks_3, "Review", "Organize images in the Gallery or view them on the Map."),
          _buildWorkflowStep(Icons.looks_4, "Export", "Generate COCO and GeoJSON data for GIS or ML."),

          const SizedBox(height: 30),
          const Text(
            "Frequently Asked Questions",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),

          const ExpansionTile(
            leading: Icon(Icons.create_new_folder_outlined, color: Colors.green),
            title: Text("How do I create a project?"),
            children: [
              Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  "Tap the 'New' button on the Home Screen. Select 'Classification' for tagging whole images or 'Segmentation' for annotating images.",
                ),
              )
            ],
          ),
          const ExpansionTile(
            leading: Icon(Icons.camera_alt_outlined, color: Colors.green),
            title: Text("How do I capture images?"),
            children: [
              Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  "In the 'Camera' tab, select a class first. When you snap a photo, GeoVision automatically embeds GPS coordinates, a timestamp, and the class name into the image's EXIF metadata.",
                ),
              )
            ],
          ),
          const ExpansionTile(
            leading: Icon(Icons.file_download_outlined, color: Colors.green),
            title: Text("What is the GeoJSON file?"),
            children: [
              Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  "GeoVision uses the GeoJSON (RFC 7946) standard. It is a GIS-compatible file (project_data.geojson) that stores your image paths, labels, and GPS locations as 'Point' features. You can open this in QGIS, ArcGIS, or Google Earth.",
                ),
              )
            ],
          ),
          const ExpansionTile(
            leading: Icon(Icons.ios_share, color: Colors.green),
            title: Text("How do I export my data?"),
            children: [
              Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  "Tap the Export icon. The app generates a ZIP file containing: \n• Your original images\n• _annotations.coco.json (for AI training)\n• project_data.geojson (for GIS use)\n• A PDF/PNG map overview.",
                ),
              )
            ],
          ),
          const ExpansionTile(
            leading: Icon(Icons.map_outlined, color: Colors.green),
            title: Text("Why don't I see map pins?"),
            children: [
              Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  "1. Check if GPS was enabled during capture.\n2. In the Map tab, ensure your filters (Date/Class) aren't excluding the images."
                ),
              )
            ],
          ),
          const ExpansionTile(
            leading: Icon(Icons.storage_outlined, color: Colors.green),
            title: Text("Where is my data stored?"),
            children: [
              Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  "All data is stored locally on your device in the App Documents folder. GeoVision does not upload your private photos to any cloud servers unless you manually share them.",
                ),
              )
            ],
          ),

          const SizedBox(height: 40),
          Center(
            child: Text(
              "GeoVision Tagger v1.0.0",
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildWorkflowStep(IconData icon, String title, String desc) {
    return ListTile(
      leading: Icon(icon, color: Colors.lightGreen[700]),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(desc),
    );
  }
}