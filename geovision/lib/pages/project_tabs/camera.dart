import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import '../../components/class_selector_dropdown.dart';
import '../../functions/image_processor.dart';
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
  List<CameraDescription> _cameras = [];
  int _selectedCameraIndex = 0;
  bool _isCapturing = false;
  String _activeTag = "Unclassified";

  double _minAvailableZoom = 1.0;
  double _maxAvailableZoom = 1.0;
  double _currentZoomLevel = 1.0;
  double _baseScale = 1.0;
  FlashMode _currentFlashMode = FlashMode.off;

  StreamSubscription<Position>? _positionStreamSubscription;
  Position? _currentPosition;
  bool _isLocationPermissionGranted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    availableCameras().then((cameras) {
      _cameras = cameras;
      if (widget.isActive) {
        _setupCamera();
        _startLocationStream();
      }
    });
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

  // --- LOCATION & CAMERA LOGIC ---
  Future<void> _startLocationStream() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return;
    }
    if (mounted) setState(() => _isLocationPermissionGranted = true);
    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5),
    ).listen((Position? position) {
      if (mounted) setState(() => _currentPosition = position);
    });
  }

  void _stopLocationStream() => _positionStreamSubscription?.cancel();

  Future<void> _setupCamera() async {
    if (_cameras.isEmpty) return;
    setState(() => _initializeControllerFuture = null);
    try {
      if (_controller != null) await _controller!.dispose();
      final newController = CameraController(
        _cameras[_selectedCameraIndex],
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.jpeg : ImageFormatGroup.bgra8888,
      );
      _controller = newController;
      _initializeControllerFuture = newController.initialize().then((_) async {
        _minAvailableZoom = await newController.getMinZoomLevel();
        _maxAvailableZoom = await newController.getMaxZoomLevel();
        await newController.setZoomLevel(_minAvailableZoom);
        await newController.setFlashMode(_currentFlashMode);
        if (mounted) {
          setState(() {});
        }
      });
      if (mounted) setState(() {});
    } catch (e) { debugPrint("Camera Setup Error: $e"); }
  }

  Future<void> _stopCamera() async {
    await _controller?.dispose();
    _controller = null;
    if (mounted) setState(() => _initializeControllerFuture = null);
  }

  void _handleScaleStart(ScaleStartDetails details) => _baseScale = _currentZoomLevel;

  Future<void> _handleScaleUpdate(ScaleUpdateDetails details) async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    double newZoom = (_baseScale * details.scale).clamp(_minAvailableZoom, _maxAvailableZoom);
    if (newZoom != _currentZoomLevel) {
      _currentZoomLevel = newZoom;
      await _controller!.setZoomLevel(newZoom);
    }
  }

  Future<void> _toggleFlash() async {
    if (_controller == null) return;
    FlashMode newMode = _currentFlashMode == FlashMode.off
        ? FlashMode.auto : (_currentFlashMode == FlashMode.auto ? FlashMode.torch : FlashMode.off);
    try {
      await _controller!.setFlashMode(newMode);
      setState(() => _currentFlashMode = newMode);
    } catch (e) { setState(() => _currentFlashMode = FlashMode.off); }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2) return;
    _selectedCameraIndex = (_selectedCameraIndex + 1) % _cameras.length;
    _currentZoomLevel = 1.0;
    _currentFlashMode = FlashMode.off;
    await _setupCamera();
  }

  Future<void> _takePicture() async {
    if (!widget.isActive || _controller == null || !_controller!.value.isInitialized || _isCapturing) return;

    setState(() => _isCapturing = true);
    final String tagForThisPhoto = widget.projectType == 'segmentation' ? "" : _activeTag;
    try {
      Position? locationToSave = _currentPosition ?? await Geolocator.getCurrentPosition().catchError((_) => null);
      final XFile rawImage = await _controller!.takePicture();
      if (mounted) setState(() => _isCapturing = false);
      _backgroundPipeline(rawImage, tagForThisPhoto, Future.value(locationToSave));
    } catch (e) { if (mounted) setState(() => _isCapturing = false);}
  }

  Future<void> _backgroundPipeline(XFile rawImage, String className, Future<Position?> locationFuture) async {
    try {
      await compute(cropSquareImage, rawImage.path);
      final appDir = await getApplicationDocumentsDirectory();
      final imagesDir = Directory('${appDir.path}/projects/${widget.projectName}/images');
      if (!await imagesDir.exists()) await imagesDir.create(recursive: true);
      final String fileName = await MetadataService.generateNextFileName(
          imagesDir, widget.projectName, className, projectType: widget.projectType);
      final String finalPath = '${imagesDir.path}/$fileName';
      await File(rawImage.path).copy(finalPath);
      await File(rawImage.path).delete();
      await FileImage(File(finalPath)).evict();
      final pos = await locationFuture;
      await MetadataService.embedMetadata(
        filePath: finalPath, lat: pos?.latitude ?? 0.0, lng: pos?.longitude ?? 0.0,
        className: widget.projectType == 'segmentation' ? null : className, time: DateTime.now(),
      );
      await MetadataService.saveToCsv(
          projectName: widget.projectName, imagePath: finalPath,
          position: pos, className: className, projectType: widget.projectType);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Saved: $fileName"), duration: const Duration(milliseconds: 800), behavior: SnackBarBehavior.floating));
        widget.onPhotoTaken?.call();
      }
    } catch (e) { debugPrint("Pipeline Error: $e"); }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    _stopLocationStream();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // --- TOP: CLASS SELECTOR ---
            if (widget.projectType == 'classification')
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: ClassSelectorDropdown(
                  projectName: widget.projectName,
                  selectedClass: _activeTag,
                  showAllOption: false,
                  classes: widget.projectClasses,
                  onClassAdded: widget.onClassesUpdated,
                  onClassSelected: (val) => setState(() => _activeTag = val),
                ),
              ),

            const Spacer(),

            // --- CENTER: CAMERA BOX ---
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: FutureBuilder<void>(
                key: ValueKey(_selectedCameraIndex),
                future: _initializeControllerFuture,
                builder: (context, snapshot) {
                  if (_controller != null &&
                      _controller!.value.isInitialized) {


                    var cameraRatio = _controller!.value.aspectRatio;
                    if (cameraRatio > 1) cameraRatio = 1 / cameraRatio;

                    return GestureDetector(
                      onScaleStart: _handleScaleStart,
                      onScaleUpdate: _handleScaleUpdate,
                      child: SizedBox(
                        width: screenWidth,
                        height: screenWidth,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: ClipRect(
                                child: FittedBox(
                                  fit: BoxFit.cover,
                                  child: SizedBox(
                                    width: screenWidth,
                                    height: screenWidth / cameraRatio,
                                    child: _controller != null && _controller!.value.isInitialized
                                        ? CameraPreview(_controller!)
                                        : Container(color: Colors.black),
                                  ),
                                ),
                              ),
                            ),

                            // INTERNAL BUTTONS
                            Positioned(
                              top: 15, left: 15,
                              child: _buildGlassIconButton(
                                icon: _getFlashIcon(),
                                color: _currentFlashMode == FlashMode.off ? Colors.white : Colors.yellowAccent,
                                onTap: _toggleFlash,
                              ),
                            ),
                            Positioned(
                              top: 15, right: 15,
                              child: _buildGlassIconButton(
                                icon: Icons.flip_camera_ios,
                                color: Colors.white,
                                onTap: _switchCamera,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  } else {
                    return Container(
                      width: screenWidth, height: screenWidth,
                      color: Colors.black,
                      child: const Center(child: CircularProgressIndicator(color: Colors.white)),
                    );
                  }
                },
              ),
            ),

            const Spacer(),

            // --- BOTTOM: LOCATION & CAPTURE ---
            _buildLocationIndicator(),
            const SizedBox(height: 20),
            _buildCaptureButton(),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildGlassIconButton({required IconData icon, required Color color, required VoidCallback onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(30),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.4),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 24),
        ),
      ),
    );
  }

  IconData _getFlashIcon() {
    if (_currentFlashMode == FlashMode.auto) return Icons.flash_auto;
    if (_currentFlashMode == FlashMode.torch) return Icons.highlight;
    return Icons.flash_off;
  }

  Widget _buildLocationIndicator() {
    bool hasPos = _currentPosition != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(hasPos ? Icons.my_location : Icons.location_off,
              color: hasPos ? Colors.greenAccent : Colors.redAccent, size: 14),
          const SizedBox(width: 8),
          Text(
            hasPos
                ? "${_currentPosition!.latitude.toStringAsFixed(5)}, ${_currentPosition!.longitude.toStringAsFixed(5)}"
                : (_isLocationPermissionGranted ? "Acquiring GPS..." : "GPS Off"),
            style: const TextStyle(color: Colors.white70, fontSize: 10, fontFamily: 'Monospace'),
          ),
        ],
      ),
    );
  }

  Widget _buildCaptureButton() {
    return GestureDetector(
      onTap: _isCapturing ? null : _takePicture,
      child: Container(
        height: 80, width: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 4),
        ),
        child: Center(
          child: _isCapturing
              ? const SizedBox(width: 30, height: 30, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Container(
            width: 60, height: 60,
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          ),
        ),
      ),
    );
  }
}