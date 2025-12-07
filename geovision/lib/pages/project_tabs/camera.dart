import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geovision/components/class_selector_dropdown.dart';
import 'package:geovision/functions/metadata_handle.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../../functions/camera/image_processor.dart';


class CameraPage extends StatefulWidget {
  final String projectName;

  const CameraPage({
    super.key,
    required this.projectName,
  });

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> with WidgetsBindingObserver{
  CameraController? _controller;
  Future<void>? _initializeControllerFuture;
  bool _isProcessing = false;
  List<CameraDescription> cameras = [];
  String _activeTag = "Unclassified";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupCamera();
  }

  Future<void> _setupCamera() async {
    cameras = await availableCameras();
    _controller = CameraController(cameras.first, ResolutionPreset.high);
    _initializeControllerFuture = _controller!.initialize();
    setState(() {
    });
  }

  Future<void> _takePicture() async {
    // 1. Block if camera is not ready OR if we are in "Cooldown"
    if (!_controller!.value.isInitialized || _isProcessing) {
      return;
    }

    // 2. Lock the Button (Start Cooldown)
    if (mounted) {
      setState(() => _isProcessing = true);
    }

    try {
      // 3. Hardware Work (Get Location & Snap Photo)
      final String tagForThisPhoto = _activeTag;
      final XFile rawImage = await _controller!.takePicture();
      final Position? position = await _getCurrentLocation();

      // 4. Background Work (Fire and Forget)
      // We do NOT await this. It runs on its own time.
      _processImage(rawImage, position, tagForThisPhoto);

      // 5. THE DELAY (Artificial Cooldown)
      // We force the user to wait 1 second before the button unlocks.
      // This gives the phone time to breathe.
      await Future.delayed(const Duration(milliseconds: 500));

    } catch (e) {
      if (kDebugMode) {
        print("Error capture: $e");
      }
    } finally {
      // 6. Unlock the Button
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _processImage(XFile rawImage, Position? position, String className) async {
    try {
      // 1. CROP
      await compute(cropSquareImage, rawImage.path);

      // 2. PREPARE PATHS
      final appDir = await getApplicationDocumentsDirectory();
      final projectDir = Directory('${appDir.path}/projects/${widget.projectName}/images');

      // --- NEW NAMING LOGIC ---
      final String fileName = await MetadataService.generateNextFileName(projectDir, widget.projectName, className);
      final String imagePath = '${projectDir.path}/$fileName';
      // ------------------------

      // 3. SAVE IMAGE
      await File(rawImage.path).copy(imagePath);
      await File(rawImage.path).delete();

      // 4. INJECT EXIF
      if (position != null) {
        await MetadataService.embedMetadata(
          filePath: imagePath,
          lat: position.latitude,
          lng: position.longitude,
          className: className,
        );
      }

      // 5. SAVE CSV
      await MetadataService.saveToCsv(
        projectName: widget.projectName,
        imagePath: imagePath,
        position: position,
        className: className,
      );

      print("✅ Saved as: $fileName");

    } catch (e) {
      print("❌ Background error: $e");
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = _controller;

    // App is not visible or Controller is null? Do nothing.
    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      // CASE 1: User minimized the app or turned off screen
      // Stop the camera to save battery and release resource
      cameraController.dispose();
    } else if (state == AppLifecycleState.resumed) {
      // CASE 2: User came back to the app
      // Restart the camera
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
          body: buildCameraPreview(screenWidth),
        ),
        Positioned(
          top: 40, left: 0, right: 0,
          child: ClassSelectorDropdown(
            projectName: widget.projectName,
            selectedClass: _activeTag,
            showAllOption: false,
            onClassSelected: (newClass) {
              setState(() => _activeTag = newClass);
            },
          ),
        ),
      ]
    );
  }

  FutureBuilder<void> buildCameraPreview(double screenWidth) {
    return FutureBuilder<void>(
      future: _initializeControllerFuture,
      builder: (BuildContext context, AsyncSnapshot<void> snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {

          // 1. Get the ratio directly from the controller
          var cameraRatio = _controller!.value.aspectRatio;

          if (cameraRatio > 1) {
            cameraRatio = 1 / cameraRatio;
          }

          return Column(
            children: [
              Spacer(),
              SizedBox(height: 100),
              // THE SQUARE FRAME
              SizedBox(
                width: screenWidth,
                height: screenWidth, // Perfect Square
                child: ClipRect(
                  child: FittedBox(
                    // 3. THE MAGIC WAND
                    // This automatically scales the child to fill the square
                    // and cuts off whatever sticks out.
                    fit: BoxFit.cover,

                    child: SizedBox(
                      // 4. The Child matches the CAMERA'S shape, not the square's.
                      width: screenWidth,
                      height: screenWidth / cameraRatio,
                      child: CameraPreview(_controller!),
                    ),
                  ),
                ),
              ),

              Spacer(),
              _buildCaptureButton(),
              SizedBox(height: 20),
            ],
          );
        } else {
          return const Center(child: CircularProgressIndicator());
        }
      },
    );
  }

  Widget _buildCaptureButton() {
    return GestureDetector(
      // If processing, do nothing on tap
      onTap: _isProcessing ? null : _takePicture,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200), // Smooth fade
        height: 80,
        width: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            // If processing, grey border. If ready, white border.
              color: _isProcessing ? Colors.grey : Colors.white,
              width: 4
          ),
          // If processing, fill with grey opacity.
          color: _isProcessing ? Colors.grey.withValues(alpha: 0.5) : Colors.transparent,
        ),
        child: _isProcessing
        // Optional: Show a tiny loader, or just the grey button
            ? const Padding(
          padding: EdgeInsets.all(20),
          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
        )
            : const Icon(Icons.camera, color: Colors.white, size: 40),
      ),
    );
  }

  Future<Position?> _getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Location services are disabled.');
    }

    permission = await Geolocator.checkPermission();
    if(permission == LocationPermission.denied){
      permission = await Geolocator.requestPermission();
      if(permission == LocationPermission.denied){
        return Future.error('Location permissions are denied');
      }
    }

    if(permission == LocationPermission.deniedForever){
      return null;
    }

    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 100,
      ),
    );
  }
}

