import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';

// Your custom imports
import 'package:geovision/components/class_selector_dropdown.dart';
import 'package:geovision/functions/metadata_handle.dart';
import '../../functions/camera/image_processor.dart';

class CameraPage extends StatefulWidget {
  final String projectName;

  // --- NEW PARAMS ---
  final List<dynamic> projectClasses;      // Receive data
  final VoidCallback? onClassesUpdated;    // Receive refresh trigger

  // Callback to notify parent (ProjectContainer) when photo is saved
  final VoidCallback? onPhotoTaken;

  const CameraPage({
    super.key,
    required this.projectName,
    required this.projectClasses,   // Add this
    this.onClassesUpdated,          // Add this
    this.onPhotoTaken,
  });

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> with WidgetsBindingObserver {
  CameraController? _controller;
  Future<void>? _initializeControllerFuture;
  bool _isCapturing = false;

  // This tracks the tag applied to the NEXT photo taken
  String _activeTag = "Unclassified";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupCamera();
  }

  Future<void> _setupCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;

      _controller = CameraController(
        cameras.first,
        ResolutionPreset.high,
        enableAudio: false,
      );

      _initializeControllerFuture = _controller!.initialize();
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint("Camera Error: $e");
    }
  }

  Future<void> _takePicture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _isCapturing) {
      return;
    }

    final String tagForThisPhoto = _activeTag;
    setState(() => _isCapturing = true);

    try {
      final Future<Position?> positionFuture = _getCurrentLocation();
      final XFile rawImage = await controller.takePicture();

      if (mounted) setState(() => _isCapturing = false);

      _backgroundPipeline(rawImage, tagForThisPhoto, positionFuture);

    } catch (e) {
      debugPrint("Capture Error: $e");
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  Future<void> _backgroundPipeline(
      XFile rawImage,
      String className,
      Future<Position?> locationFuture
      ) async {
    try {
      await compute(cropSquareImage, rawImage.path);

      final appDir = await getApplicationDocumentsDirectory();
      final imagesDir = Directory('${appDir.path}/projects/${widget.projectName}/images');
      if (!await imagesDir.exists()) await imagesDir.create(recursive: true);

      final String fileName = await MetadataService.generateNextFileName(
          imagesDir,
          widget.projectName,
          className
      );
      final String finalPath = '${imagesDir.path}/$fileName';

      final File tempFile = File(rawImage.path);
      await tempFile.copy(finalPath);
      await tempFile.delete();

      final Position? position = await locationFuture;

      await MetadataService.embedMetadata(
        filePath: finalPath,
        lat: position?.latitude ?? 0.0,
        lng: position?.longitude ?? 0.0,
        className: className,
      );

      await MetadataService.saveToCsv(
        projectName: widget.projectName,
        imagePath: finalPath,
        position: position,
        className: className,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Saved: $fileName"),
            duration: const Duration(milliseconds: 800),
            behavior: SnackBarBehavior.floating,
          ),
        );
        widget.onPhotoTaken?.call();
      }

    } catch (e) {
      debugPrint("Background Pipeline Error: $e");
    }
  }

  Future<Position?> _getCurrentLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        return null;
      }
    }

    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _controller?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _setupCamera();
    }
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;

    return Stack(
      children: [
        Scaffold(
          backgroundColor: Colors.black,
          body: FutureBuilder<void>(
            future: _initializeControllerFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.done) {
                var cameraRatio = _controller!.value.aspectRatio;
                if (cameraRatio > 1) cameraRatio = 1 / cameraRatio;

                return Column(
                  children: [
                    const Spacer(),
                    const SizedBox(height: 100),
                    SizedBox(
                      width: screenWidth,
                      height: screenWidth,
                      child: ClipRect(
                        child: FittedBox(
                          fit: BoxFit.cover,
                          child: SizedBox(
                            width: screenWidth,
                            height: screenWidth / cameraRatio,
                            child: CameraPreview(_controller!),
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
                    _buildCaptureButton(),
                    const SizedBox(height: 20),
                  ],
                );
              } else {
                return const Center(child: CircularProgressIndicator());
              }
            },
          ),
        ),

        // --- CLASS SELECTOR DROPDOWN ---
        Positioned(
          top: 40, left: 0, right: 0,
          child: ClassSelectorDropdown(
            projectName: widget.projectName,
            selectedClass: _activeTag, // Use _activeTag here
            showAllOption: false, // Usually camera doesn't need "All", just specific tags

            // 1. Pass Data
            classes: widget.projectClasses,

            // 2. Pass Refresh Callback
            onClassAdded: widget.onClassesUpdated,

            onClassSelected: (String newClass) {
              setState(() => _activeTag = newClass);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCaptureButton() {
    return GestureDetector(
      onTap: _isCapturing ? null : _takePicture,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: 80,
        width: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
              color: _isCapturing ? Colors.grey : Colors.white,
              width: 4
          ),
          color: _isCapturing ? Colors.grey.withValues(alpha:0.5) : Colors.transparent,
        ),
        child: _isCapturing
            ? const Padding(
          padding: EdgeInsets.all(20),
          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
        )
            : const Icon(Icons.camera, color: Colors.white, size: 40),
      ),
    );
  }
}