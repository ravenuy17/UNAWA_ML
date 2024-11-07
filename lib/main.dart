import 'dart:async'; // Add this for TimeoutException
import 'dart:convert';
import 'dart:io' show File, HttpException, Platform;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

//comment

// Add this main function at the top level
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  runApp(MaterialApp(
    home: CameraScreen(),
    theme: ThemeData(
      primarySwatch: Colors.blue,
      useMaterial3: true,
    ),
  ));
}

class CameraScreen extends StatefulWidget {
  // Modified constructor to be const
  const CameraScreen({super.key});

  @override
  _CameraScreenState createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  List<CameraDescription>? cameras;
  bool _isCameraInitialized = false;
  bool _isProcessing = false;
  String _lastDetection = '';
  double _confidence = 0.0;
  FlashMode _flashMode = FlashMode.off;
  CameraDescription? _currentCamera;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = _cameraController;

    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      cameraController.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    try {
      cameras = await availableCameras();
      if (cameras!.isEmpty) {
        throw CameraException('no_cameras', 'No cameras available');
      }

      _currentCamera = cameras!.first;
      _cameraController = CameraController(
        _currentCamera!,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _cameraController!.initialize();

      // Check if the camera supports flash
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        print('Desktop environment detected, flash mode may not be supported');
      } else if (_cameraController!.value.flashMode == FlashMode.off) {
        print('Flash mode is not supported by this camera');
      } else {
        await _cameraController!.setFlashMode(FlashMode.off);
      }

      setState(() => _isCameraInitialized = true);
    } on CameraException catch (e) {
      _showErrorDialog('Camera Error', e.description ?? 'Unknown camera error');
    } catch (e) {
      _showErrorDialog('Error', e.toString());
    }
  }

  Future<void> _switchCamera() async {
    if (cameras == null || cameras!.length < 2) return;

    setState(() => _isCameraInitialized = false);

    final newCameraIndex = cameras!.indexOf(_currentCamera!) == 0 ? 1 : 0;
    _currentCamera = cameras![newCameraIndex];

    await _cameraController?.dispose();

    _cameraController = CameraController(
      _currentCamera!,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    try {
      await _cameraController!.initialize();
      await _cameraController!.setFlashMode(_flashMode);
    } on CameraException catch (e) {
      _showErrorDialog('Camera Error', e.description ?? 'Unknown camera error');
    }

    setState(() => _isCameraInitialized = true);
  }

  Future<void> _toggleFlash() async {
    if (!_isCameraInitialized) return;

    try {
      if (_cameraController!.value.flashMode == FlashMode.off) {
        await _cameraController!.setFlashMode(FlashMode.torch);
        setState(() => _flashMode = FlashMode.torch);
      } else {
        await _cameraController!.setFlashMode(FlashMode.off);
        setState(() => _flashMode = FlashMode.off);
      }
    } on CameraException catch (e) {
      _showErrorDialog('Flash Error', e.description ?? 'Unknown flash error');
    } catch (e) {
      _showErrorDialog('Error', 'Failed to toggle flash: $e');
    }
  }

  Future<void> pickImage() async {
    if (_isProcessing) return;

    setState(() => _isProcessing = true);

    try {
      final ImagePicker picker = ImagePicker();
      final XFile? pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
      );

      if (pickedFile != null) {
        await sendImage(File(pickedFile.path));
      }
    } catch (e) {
      _showErrorDialog('Gallery Error', 'Failed to pick image: $e');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> sendImage(File imageFile) async {
    final uri = Uri.parse('http://172.20.10.13:8000/detect');

    final request = http.MultipartRequest('POST', uri)
      ..files.add(await http.MultipartFile.fromPath('image', imageFile.path));

    try {
      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException('Request timed out');
        },
      );

      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _lastDetection = data['label'] ?? 'Unknown';
          _confidence = (data['confidence'] ?? 0.0) * 100;
        });
      } else {
        throw HttpException('Server returned ${response.statusCode}');
      }
    } catch (e) {
      _showErrorDialog('Network Error', 'Failed to process image: $e');
    }
  }

  Future<void> _captureAndDetect() async {
    if (!_isCameraInitialized || _isProcessing) return;

    setState(() => _isProcessing = true);

    try {
      final XFile image = await _cameraController!.takePicture();
      await sendImage(File(image.path));
    } on CameraException catch (e) {
      _showErrorDialog(
          'Capture Error', e.description ?? 'Unknown capture error');
    } catch (e) {
      _showErrorDialog('Error', 'Failed to capture image: $e');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Filipino Sign Language Detection"),
        actions: [
          if (_isCameraInitialized)
            IconButton(
              icon: Icon(_flashMode == FlashMode.off
                  ? Icons.flash_off
                  : Icons.flash_on),
              onPressed: _toggleFlash,
            ),
          if (cameras != null && cameras!.length > 1)
            IconButton(
              icon: const Icon(Icons.switch_camera),
              onPressed: _switchCamera,
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _isCameraInitialized
                  ? Stack(
                      alignment: Alignment.center,
                      children: [
                        CameraPreview(_cameraController!),
                        if (_isProcessing)
                          Container(
                            color: Colors.black54,
                            child: const Center(
                              child: CircularProgressIndicator(
                                color: Colors.white,
                              ),
                            ),
                          ),
                      ],
                    )
                  : const Center(child: CircularProgressIndicator()),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.black87,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_lastDetection.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Column(
                        children: [
                          Text(
                            'Detected Sign: $_lastDetection',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Confidence: ${_confidence.toStringAsFixed(1)}%',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _isProcessing ? null : pickImage,
                        icon: const Icon(Icons.photo_library),
                        label: const Text("Gallery"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: _isProcessing ? null : _captureAndDetect,
                        icon: const Icon(Icons.camera),
                        label: const Text("Capture"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
