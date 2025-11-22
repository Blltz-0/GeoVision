import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

import '../../components/image_processor.dart';


class CameraPage extends StatefulWidget {
  final String projectName;

  const CameraPage({
    super.key,
    required this.projectName,

  });

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  CameraController? _controller;
  Future<void>? _initializeControllerFuture;
  bool _isProcessing = false;
  List<CameraDescription> cameras = [];

  @override
  void initState() {
    super.initState();
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

    setState(() {
      _isProcessing = true;
    });

    try {
      final XFile rawImage = await _controller!.takePicture();

      await compute(cropSquareImage, rawImage.path);

      final appDir = await getApplicationDocumentsDirectory();
      final String fileName = 'img_${DateTime.now().millisecondsSinceEpoch}.jpg';

      final String savePath = '${appDir.path}/projects/${widget.projectName}/images/$fileName';

      await File(rawImage.path).copy(savePath);

      await File(rawImage.path).delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Image saved to: $savePath'),
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
    _controller?.dispose();
    super.dispose();
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

          // 2. ROBUST FIX: Normalize the ratio.
          // Sensors usually report landscape ratios (e.g., 4:3 = 1.33).
          // In Portrait mode, we need the frame to be tall (e.g., 3:4).
          // So, if the ratio is "wide" (greater than 1), we invert it for our container
          // to ensure the container is taller than it is wide.
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
            : const Icon(Icons.camera, color: Colors.white, size: 40),
      ),
    );
  }


}

