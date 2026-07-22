import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/service_providers.dart';
import '../../../core/services/pose_detection_service.dart';
import '../../../core/services/rep_counter.dart';
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

enum _Stage { idle, recording, analyzing, reviewing }

/// Setup-time flow: the user explicitly starts a short recording, BeniAI
/// counts reps live on-device (falling back to an OpenAI vision snapshot if
/// it can't confidently pose-count anything), then the user reviews what
/// was detected/counted and taps "Set Activity" to confirm - rather than a
/// single silent photo capture.
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
  String? _error;

  final _poseService = PoseDetectionService();
  final Map<ActivityType, RepCounter> _counters = {
    ActivityType.squats: RepCounter(ActivityType.squats),
    ActivityType.pushUps: RepCounter(ActivityType.pushUps),
    ActivityType.jumpingJacks: RepCounter(ActivityType.jumpingJacks),
  };

  _Stage _stage = _Stage.idle;
  bool _isStreaming = false;
  Timer? _elapsedTimer;
  int _elapsedSeconds = 0;
  int _liveCount = 0;
  static const _maxRecordSeconds = 15;

  ActivityType? _detectedType;
  String _detectedLabel = '';
  int _targetReps = 0;
  String _reviewNote = '';

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
      // Default to the back camera: on-device pose detection is only
      // confirmed reliable on that lens. Front is still selectable via the
      // switch button for framing convenience.
      _cameraIndex = _cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
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
    // Dispose the old controller before creating the new one - initializing
    // a second CameraController while the first still holds the hardware
    // session can silently hang/fail (notably on iOS), which is why
    // switching cameras looked like it did nothing.
    await _controller?.dispose();
    _controller = null;

    try {
      final controller = CameraController(
        description,
        ResolutionPreset.medium,
        enableAudio: false,
        // Must match what PoseDetectionService expects per-platform, since
        // this screen streams frames for live rep counting too.
        imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _initializing = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _initializing = false;
          _error = 'Could not switch camera: $e';
        });
      }
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _stage == _Stage.recording) return;
    setState(() => _initializing = true);
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    await _startCamera(_cameras[_cameraIndex]);
  }

  Future<void> _startRecording() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _isStreaming) return;

    for (final counter in _counters.values) {
      counter.start();
    }

    setState(() {
      _stage = _Stage.recording;
      _elapsedSeconds = 0;
      _liveCount = 0;
    });

    _isStreaming = true;
    await controller.startImageStream(_onCameraFrame);

    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsedSeconds++);
      if (_elapsedSeconds >= _maxRecordSeconds) {
        _stopRecordingAndAnalyze();
      }
    });
  }

  void _onCameraFrame(CameraImage image) {
    final controller = _controller;
    if (controller == null || !_isStreaming) return;
    _poseService.processCameraImage(image, controller.description).then((pose) {
      if (pose == null || !mounted || !_isStreaming) return;
      var gotNewRep = false;
      for (final counter in _counters.values) {
        if (counter.processPose(pose)) gotNewRep = true;
      }
      if (gotNewRep) {
        final best = _counters.values.map((c) => c.reps).reduce((a, b) => a > b ? a : b);
        setState(() => _liveCount = best);
      }
    });
  }

  Future<void> _stopRecordingAndAnalyze() async {
    if (_stage != _Stage.recording) return;
    _elapsedTimer?.cancel();
    _isStreaming = false;
    final controller = _controller;
    try {
      await controller?.stopImageStream();
    } catch (_) {
      // Already stopped.
    }

    setState(() => _stage = _Stage.analyzing);

    // Pick whichever built-in activity racked up the most confirmed reps.
    ActivityType? bestType;
    var bestCount = 0;
    for (final entry in _counters.entries) {
      if (entry.value.reps > bestCount) {
        bestType = entry.key;
        bestCount = entry.value.reps;
      }
    }

    // A single confirmed rep is enough evidence now that RepCounter
    // debounces noise internally - requiring more just pushed borderline
    // demos (a person doing one clean push-up) into the weaker
    // single-photo OpenAI fallback, which then mislabels them "custom" and
    // leaves the alarm stuck with unreliable per-photo verification.
    if (bestType != null && bestCount >= 1) {
      final preset = ActivityPreset.byType(bestType);
      setState(() {
        _detectedType = bestType;
        _detectedLabel = preset.label;
        _targetReps = preset.defaultTarget;
        _reviewNote = 'BeniAI counted $bestCount ${preset.unitLabel} while you recorded.';
        _stage = _Stage.reviewing;
      });
      return;
    }

    await _identifyFromStillFrame(controller);
  }

  Future<void> _identifyFromStillFrame(CameraController? controller) async {
    if (controller == null) {
      setState(() => _stage = _Stage.idle);
      return;
    }

    try {
      final file = await controller.takePicture();
      final bytes = await file.readAsBytes();
      final result = await ref.read(openAIServiceProvider).identifyActivity(bytes);

      if (!mounted) return;

      final preset = ActivityPreset.byType(result.type);
      setState(() {
        _detectedType = result.type;
        _detectedLabel = result.label.isNotEmpty ? result.label : preset.label;
        _targetReps = result.suggestedTarget > 0 ? result.suggestedTarget : preset.defaultTarget;
        _reviewNote = result.reasoning.isNotEmpty
            ? result.reasoning
            : "BeniAI identified this from a photo - it wasn't confident counting reps live.";
        _stage = _Stage.reviewing;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _stage = _Stage.idle);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not analyze the recording: $e')));
    }
  }

  void _tryAgain() {
    for (final counter in _counters.values) {
      counter.reset();
    }
    setState(() {
      _stage = _Stage.idle;
      _detectedType = null;
      _reviewNote = '';
    });
  }

  void _adjustTarget(int delta) {
    setState(() => _targetReps = (_targetReps + delta).clamp(1, 200));
  }

  void _confirmActivity() {
    final type = _detectedType;
    if (type == null) return;
    Navigator.of(
      context,
    ).pop(ActivitySetupResult(activityTypeId: type.id, label: _detectedLabel, target: _targetReps));
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    _controller?.dispose();
    _poseService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Show BeniAI the activity'),
        actions: [
          if (_cameras.length > 1 && _stage != _Stage.recording)
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

    if (_stage == _Stage.reviewing) {
      return _buildReview();
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            _stage == _Stage.recording
                ? 'Recording ${_elapsedSeconds}s - reps detected so far: $_liveCount. '
                      'Do squats, push-ups or jumping jacks, then tap Stop.'
                : _stage == _Stage.analyzing
                ? 'Analyzing what BeniAI saw...'
                : 'Tap Start Recording, then perform the activity in view of the camera.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        Expanded(
          child: Stack(
            alignment: Alignment.topCenter,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: AspectRatio(
                  aspectRatio: 3 / 4,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: CameraPreview(_controller!),
                  ),
                ),
              ),
              if (_stage == _Stage.recording)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'REC ${_elapsedSeconds}s',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(24),
          child: _stage == _Stage.recording
              ? ElevatedButton.icon(
                  onPressed: _stopRecordingAndAnalyze,
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('Stop & Review'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
                  ),
                )
              : ElevatedButton.icon(
                  onPressed: _stage == _Stage.analyzing ? null : _startRecording,
                  icon: _stage == _Stage.analyzing
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.fiber_manual_record),
                  label: Text(_stage == _Stage.analyzing ? 'Analyzing...' : 'Start Recording'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildReview() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle_outline, size: 56, color: Colors.green),
          const SizedBox(height: 16),
          Text(
            _detectedLabel,
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(_reviewNote, textAlign: TextAlign.center),
          const SizedBox(height: 28),
          Text('Target for this alarm', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: () => _adjustTarget(-1),
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('$_targetReps', style: Theme.of(context).textTheme.headlineMedium),
              ),
              IconButton(
                onPressed: () => _adjustTarget(1),
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton(onPressed: _tryAgain, child: const Text('Try Again')),
              const SizedBox(width: 16),
              ElevatedButton(onPressed: _confirmActivity, child: const Text('Set Activity')),
            ],
          ),
        ],
      ),
    );
  }
}
