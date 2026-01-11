import 'package:flutter/material.dart';

class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Help & Support'),
        backgroundColor: Colors.lightGreenAccent,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: const [
          Text(
            "Frequently Asked Questions",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 20),

          ExpansionTile(
            leading: Icon(Icons.create_new_folder_outlined),
            title: Text("How do I create a project?"),
            children: [
              Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  "Tap the 'New' button on the Home Screen. Enter a unique project name and select the mode (Classification or Segmentation). This will create a folder in your device storage.",
                ),
              )
            ],
          ),
          ExpansionTile(
            leading: Icon(Icons.camera_alt_outlined),
            title: Text("How do I capture images?"),
            children: [
              Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  "Open a project and go to the 'Camera' tab. Select a class at the bottom of the screen and tap the shutter button. The image will be saved with location data automatically.",
                ),
              )
            ],
          ),
          ExpansionTile(
            leading: Icon(Icons.ios_share),
            title: Text("How do I export my data?"),
            children: [
              Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  "Inside a project, tap the Share icon in the top right corner of the AppBar. This will package your images and CSV data into a format ready for sharing.",
                ),
              )
            ],
          ),
          ExpansionTile(
            leading: Icon(Icons.map_outlined),
            title: Text("Why don't I see map pins?"),
            children: [
              Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  "Ensure your device has GPS enabled when taking photos. Images without GPS metadata (EXIF) will default to (0,0) coordinates.",
                ),
              )
            ],
          ),
        ],
      ),
    );
  }
}