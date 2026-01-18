import 'dart:async'; // Required for StreamSubscription
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import '../../components/class_selector_dropdown.dart';
import '../../functions/camera/image_processor.dart';
import '../../functions/metadata_handle.dart';

class CameraPage extends StatefulWidget {
  final String projectName;
  final List<dynamic> projectClasses;
  final VoidCallback? onClassesUpdated;
  final VoidCallback? onPhotoTaken;
  final bool isActive;
  final String projectType;

  const CameraPage({
    super.key,
    required this.projectName,
    required this.projectClasses,
    required this.projectType,
    this.onClassesUpdated,
    this.onPhotoTaken,
    this.isActive = true,
  });

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> with WidgetsBindingObserver {
  CameraController? _controller;
  Future<void>? _initializeControllerFuture;
  bool _isCapturing = false;
  String _activeTag = "Unclassified";

  // --- LOCATION STATE VARIABLES ---
  StreamSubscription<Position>? _positionStreamSubscription;
  Position? _currentPosition;
  bool _isLocationPermissionGranted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.isActive) {
      _setupCamera();
      _startLocationStream(); // Start listening to location
    }
  }

  @override
  void didUpdateWidget(CameraPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive) {
      if (widget.isActive) {
        _setupCamera();
        _startLocationStream();
      } else {
        _stopCamera();
        _stopLocationStream();
      }
    }
  }

  // --- LOCATION FUNCTIONS ---

  Future<void> _startLocationStream() async {
    // 1. Check Service Status
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) setState(() => _isLocationPermissionGranted = false);
      return;
    }

    // 2. Check Permissions
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (mounted) setState(() => _isLocationPermissionGranted = false);
        return;
      }
    }

    if (mounted) setState(() => _isLocationPermissionGranted = true);

    // 3. Start Stream
    // We use a distance filter of 5 meters to avoid excessive updates
    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
    );

    _positionStreamSubscription = Geolocator.getPositionStream(locationSettings: locationSettings)
        .listen((Position? position) {
      if (mounted) {
        setState(() {
          _currentPosition = position;
        });
      }
    });
  }

  void _stopLocationStream() {
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
  }

  // --- CAMERA FUNCTIONS ---

  Future<void> _setupCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;

      await _controller?.dispose();

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

  Future<void> _stopCamera() async {
    await _controller?.dispose();
    _controller = null;
    if (mounted) setState(() {});
  }

  Future<void> _takePicture() async {
    final controller = _controller;
    if (!widget.isActive || controller == null || !controller.value.isInitialized || _isCapturing) {
      return;
    }

    final String tagForThisPhoto = widget.projectType == 'segmentation' ? "" : _activeTag;

    setState(() => _isCapturing = true);

    try {
      // Use the cached _currentPosition if available, otherwise try to fetch one last time
      Position? locationToSave = _currentPosition;
      if (locationToSave == null && _isLocationPermissionGranted) {
        try {
          locationToSave = await Geolocator.getCurrentPosition(
              timeLimit: const Duration(seconds: 2)
          );
        } catch (_) {}
      }

      final XFile rawImage = await controller.takePicture();

      if (mounted) setState(() => _isCapturing = false);

      // Pass the location directly (wrapped in a Future for compatibility if needed,
      // or modify pipeline to accept Position object directly.
      // Here we wrap it in Future.value to match existing signature)
      _backgroundPipeline(rawImage, tagForThisPhoto, Future.value(locationToSave));
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

      final String fileName = await MetadataService.generateNextFileName(
          imagesDir,
          widget.projectName,
          className,
          projectType: widget.projectType
      );

      final String finalPath = '${imagesDir.path}/$fileName';

      final File tempFile = File(rawImage.path);
      await tempFile.copy(finalPath);
      await tempFile.delete();

      await FileImage(File(finalPath)).evict();
      await ResizeImage(FileImage(File(finalPath)), width: 300).evict();

      final Position? position = await locationFuture;

      String? metaClass = widget.projectType == 'segmentation' ? null : className;

      await MetadataService.embedMetadata(
        filePath: finalPath,
        lat: position?.latitude ?? 0.0,
        lng: position?.longitude ?? 0.0,
        className: metaClass,
        time: DateTime.now(),
      );

      await MetadataService.saveToCsv(
          projectName: widget.projectName,
          imagePath: finalPath,
          position: position,
          className: className,
          projectType: widget.projectType
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    _stopLocationStream(); // Ensure stream is cancelled
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      _controller?.dispose();
      _stopLocationStream(); // Pause location updates when app is backgrounded
    } else if (state == AppLifecycleState.resumed) {
      if (widget.isActive) {
        _setupCamera();
        _startLocationStream(); // Resume location updates
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

                    // --- LOCATION INDICATOR WIDGET ---
                    _buildLocationIndicator(),
                    const SizedBox(height: 15),

                    _buildCaptureButton(),
                    const SizedBox(height: 20),
                  ],
                );
              } else {
                return Container(
                    color: Colors.black,
                    child: Center(
                      child: widget.isActive
                          ? const CircularProgressIndicator()
                          : const Icon(Icons.camera_alt, color: Colors.grey),
                    )
                );
              }
            },
          ),
        ),

        if (widget.projectType == 'classification')
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

  Widget _buildLocationIndicator() {
    if (!_isLocationPermissionGranted) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.location_off, color: Colors.redAccent, size: 16),
            SizedBox(width: 8),
            Text(
              "Location Off",
              style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      );
    }

    if (_currentPosition == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            SizedBox(
                width: 12, height: 12,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)
            ),
            SizedBox(width: 8),
            Text(
              "Acquiring GPS...",
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      );
    }

    // Location found
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
          color: Colors.black45,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.green.withValues(alpha: 0.3))
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.my_location, color: Colors.greenAccent, size: 16),
          const SizedBox(width: 8),
          Text(
            "Lat: ${_currentPosition!.latitude.toStringAsFixed(5)}  Lng: ${_currentPosition!.longitude.toStringAsFixed(5)}",
            style: const TextStyle(
                color: Colors.greenAccent,
                fontSize: 12,
                fontFamily: 'Monospace',
                fontWeight: FontWeight.bold
            ),
          ),
        ],
      ),
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