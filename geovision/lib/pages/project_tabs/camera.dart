import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
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
    if(!_controller!.value.isInitialized || _isProcessing){
      return;
    }

    setState(() {_isProcessing = true;});

    try {
      final Position? position = await _getCurrentLocation();

      final XFile rawImage = await _controller!.takePicture();
      await compute(cropSquareImage, rawImage.path);

      final appDir = await getApplicationDocumentsDirectory();

      final String fileId = 'img_${DateTime.now().millisecondsSinceEpoch}.jpg';

      final String imagePath = '${appDir.path}/projects/${widget.projectName}/images/$fileId.jpg';

      await File(rawImage.path).copy(imagePath);
      await File(rawImage.path).delete();

      if (position != null) {
        await MetadataService.embedLocationIntoImage(
            imagePath,
            position.latitude,
            position.longitude
        );
      }

      await MetadataService.saveToCsv(
        projectName: widget.projectName,
        imagePath: imagePath,
        position: position,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Image saved to: $imagePath'),
          ),
        );
      }

    }catch (e) {
      if (kDebugMode) {
        print(e);
      }
    }finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
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

    return Scaffold(
      backgroundColor: Colors.black,
      body: buildCameraPreview(screenWidth),
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
      onTap: () {
        _takePicture();
      },
      child: Container(
        height: 80,
        width: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 4),
          color: _isProcessing ? Colors.grey : Colors.transparent, // Visual feedback
        ),
        child: _isProcessing
            ? const CircularProgressIndicator(color: Colors.white)
            : const Icon(Icons.circle, color: Colors.white, size: 40),
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

