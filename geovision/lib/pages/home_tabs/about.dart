import 'package:flutter/material.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('About GeoVision'),
        backgroundColor: Colors.lightGreenAccent,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // App Logo
            const SizedBox(height: 20),
            Image.asset(
              'assets/logo.png', // Ensure you have this asset
              height: 100,
              errorBuilder: (context, error, stackTrace) =>
              const Icon(Icons.eco, size: 100, color: Colors.green),
            ),
            const SizedBox(height: 20),

            // App Name & Version
            const Text(
              'GeoVision',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const Text(
              'Version 1.0.0',
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
            const SizedBox(height: 30),

            // Description
            const Text(
              'GeoVision is a specialized tool designed for field data collection, '
                  'image classification, and segmentation. Easily capture geotagged '
                  'images, annotate data, and export your projects for analysis.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, height: 1.5),
            ),
            const SizedBox(height: 30),
            const Divider(),
            const SizedBox(height: 20),

            // Developer / Contact Info
            _buildInfoRow(Icons.code, 'Developer/s', ['Lawrence C. Reolegio'],),
            const SizedBox(height: 10),
            _buildInfoRow(Icons.email, 'Contact', ['reolegio.l@gmail.com']),
            const SizedBox(height: 10),
            _buildInfoRow(Icons.copyright, 'License', ['MIT License']),

            const SizedBox(height: 40),
            const Text(
              '© 2025 GeoVision Inc.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, List<String> value) {
    return Row(
      children: [
        Icon(icon, color: Colors.green),
        const SizedBox(width: 15),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            //make a loop to iterate through the list value and show them each
            for (var value in value)
              Text(value, style: const TextStyle(fontSize: 16)),
          ],
        ),
      ],
    );
  }
}