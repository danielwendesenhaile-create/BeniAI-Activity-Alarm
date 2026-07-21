import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/service_providers.dart';
import '../../../core/utils/camera_permission.dart';
import '../../../models/activity_model.dart';

/// What the user picked/confirmed for the alarm's activity, returned by
/// popping this screen.
class ActivitySetupResult {
  final String activityTypeId;
  final String label;
  final int target;

  const ActivitySetupResult({
    required this.activityTypeId,
    required this.label,
    required this.target,
  });
}

/// Setup-time flow: "open the camera and show the activity" so BeniAI can
/// use OpenAI vision to identify it and pre-fill the alarm's activity
/// fields. The user still confirms/edits the result before saving.
class ActivityCameraSetupScreen extends ConsumerStatefulWidget {
  const ActivityCameraSetupScreen({super.key});

  @override
  ConsumerState<ActivityCameraSetupScreen> createState() => _ActivityCameraSetupScreenState();
}

class _ActivityCameraSetupScreenState extends ConsumerState<ActivityCameraSetupScreen> {
  CameraController? _controller;
  List<CameraDescription> _cameras = const [];
  int _cameraIndex = 0;
  bool _initializing = true;
  bool _analyzing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _setup();
  }

  Future<void> _setup() async {
    final granted = await ensureCameraPermission();
    if (!granted) {
      setState(() {
        _initializing = false;
        _error = 'Camera permission is required to set an activity this way.';
      });
      return;
    }

    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() {
          _initializing = false;
          _error = 'No camera found on this device.';
        });
        return;
      }
      _cameraIndex = _cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.front);
      if (_cameraIndex < 0) _cameraIndex = 0;
      await _startCamera(_cameras[_cameraIndex]);
    } catch (e) {
      setState(() {
        _initializing = false;
        _error = 'Could not start the camera: $e';
      });
    }
  }

  Future<void> _startCamera(CameraDescription description) async {
    final previous = _controller;
    _controller = CameraController(description, ResolutionPreset.medium, enableAudio: false);
    await _controller!.initialize();
    await previous?.dispose();
    if (mounted) setState(() => _initializing = false);
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2) return;
    setState(() => _initializing = true);
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    await _startCamera(_cameras[_cameraIndex]);
  }

  Future<void> _captureAndIdentify() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _analyzing) {
      return;
    }

    setState(() => _analyzing = true);
    try {
      final file = await controller.takePicture();
      final bytes = await file.readAsBytes();
      final result = await ref.read(openAIServiceProvider).identifyActivity(bytes);

      if (!mounted) return;

      if (result == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Couldn't identify the activity. Try again or pick manually."),
          ),
        );
        return;
      }

      Navigator.of(context).pop(
        ActivitySetupResult(
          activityTypeId: result.type.id,
          label: result.label,
          target: result.suggestedTarget,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Capture failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Show BeniAI the activity'),
        actions: [
          if (_cameras.length > 1)
            IconButton(
              icon: const Icon(Icons.cameraswitch_outlined),
              onPressed: _initializing ? null : _switchCamera,
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }

    if (_initializing || _controller == null || !_controller!.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Frame yourself doing the activity (e.g. mid-squat), then tap capture. '
            "BeniAI will identify it and suggest a target for your alarm.",
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: AspectRatio(
                aspectRatio: 3 / 4,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: CameraPreview(_controller!),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(24),
          child: ElevatedButton.icon(
            onPressed: _analyzing ? null : _captureAndIdentify,
            icon: _analyzing
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.camera_alt_outlined),
            label: Text(_analyzing ? 'Identifying...' : 'Capture & Set Activity'),
          ),
        ),
      ],
    );
  }
}
