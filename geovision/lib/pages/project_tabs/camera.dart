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
  final List<dynamic> projectClasses;
  final VoidCallback? onClassesUpdated;
  final VoidCallback? onPhotoTaken;

  // --- NEW: Controls if camera should be running ---
  final bool isActive;

  const CameraPage({
    super.key,
    required this.projectName,
    required this.projectClasses,
    this.onClassesUpdated,
    this.onPhotoTaken,
    this.isActive = true, // Default to true
  });

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> with WidgetsBindingObserver {
  CameraController? _controller;
  Future<void>? _initializeControllerFuture;
  bool _isCapturing = false;
  String _activeTag = "Unclassified";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Only setup if we start active
    if (widget.isActive) {
      _setupCamera();
    }
  }

  // --- NEW: Detect Tab Switching ---
  @override
  void didUpdateWidget(CameraPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the active state changed (User switched tabs)
    if (widget.isActive != oldWidget.isActive) {
      if (widget.isActive) {
        _setupCamera(); // Tab selected -> Start Camera
      } else {
        _stopCamera();  // Tab deselected -> Stop Camera
      }
    }
  }

  Future<void> _setupCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;

      // Dispose existing if any to prevent memory leaks before new init
      await _controller?.dispose();

      _controller = CameraController(
        cameras.first,
        ResolutionPreset.high,
        enableAudio: false,
      );

      _initializeControllerFuture = _controller!.initialize();

      // Rebuild to show preview
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint("Camera Error: $e");
    }
  }

  // --- NEW: Helper to stop camera ---
  Future<void> _stopCamera() async {
    await _controller?.dispose();
    _controller = null;
    if (mounted) setState(() {});
  }

  Future<void> _takePicture() async {
    final controller = _controller;
    // Check isActive to ensure we don't snap if user just switched tabs
    if (!widget.isActive || controller == null || !controller.value.isInitialized || _isCapturing) {
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

  Future<void> _backgroundPipeline(XFile rawImage, String className, Future<Position?> locationFuture) async {
    try {
      await compute(cropSquareImage, rawImage.path);

      final appDir = await getApplicationDocumentsDirectory();
      final imagesDir = Directory('${appDir.path}/projects/${widget.projectName}/images');
      if (!await imagesDir.exists()) await imagesDir.create(recursive: true);

      final String fileName = await MetadataService.generateNextFileName(imagesDir, widget.projectName, className);
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
    if (state == AppLifecycleState.inactive) {
      // App went to background -> Stop camera
      _controller?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      // App came back -> Start camera ONLY if we are the active tab
      if (widget.isActive) {
        _setupCamera();
      }
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
              // Only show preview if connection done AND controller is active
              if (snapshot.connectionState == ConnectionState.done && _controller != null) {
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
                // Show black screen or loader when camera is off
                return Container(
                    color: Colors.black,
                    child: Center(
                      child: widget.isActive
                          ? const CircularProgressIndicator() // Loading if active
                          : const Icon(Icons.camera_alt, color: Colors.grey), // Icon if inactive
                    )
                );
              }
            },
          ),
        ),
        Positioned(
          top: 40, left: 0, right: 0,
          child: ClassSelectorDropdown(
            projectName: widget.projectName,
            selectedClass: _activeTag,
            showAllOption: false,
            classes: widget.projectClasses,
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