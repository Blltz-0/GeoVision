import 'package:flutter/material.dart';
import 'package:geovision/pages/project_tabs/camera.dart';
import 'package:geovision/pages/project_tabs/images.dart';
import 'package:geovision/pages/project_tabs/map.dart';


class ProjectContainerPage extends StatefulWidget {
  const ProjectContainerPage({super.key});

  @override
  State<ProjectContainerPage> createState() => _ProjectContainerPageState();
}

class _ProjectContainerPageState extends State<ProjectContainerPage> {
  int _currentIndex=1;

  final List<Widget> _tabs = [
    const CameraPage(),
    const ImagesPage(),
    const MapPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(

      body: _tabs[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.camera), label: 'Camera'),
          BottomNavigationBarItem(icon: Icon(Icons.image), label: 'Images'),
          BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Map'),
        ],
      ),
    );
  }
}