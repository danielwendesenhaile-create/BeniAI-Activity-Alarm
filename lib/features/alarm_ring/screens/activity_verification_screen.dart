import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import '../../../core/providers/service_providers.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/analytics_service.dart';
import '../../../core/services/openai_service.dart';
import '../../../core/services/pose_detection_service.dart';
import '../../../core/services/rep_counter.dart';
import '../../../core/utils/camera_permission.dart';
import '../../../models/activity_model.dart';
import '../../alarms/providers/alarm_providers.dart';
import '../widgets/rep_progress_ring.dart';

/// The screen that actually stops the alarm: opens the camera and requires
/// the user to perform the activity their alarm was configured with.
///
/// - Pose-countable activities (squats, push-ups, jumping jacks) are
///   counted live and continuously on-device with ML Kit pose detection -
///   nothing pauses the camera stream mid-activity.
/// - Custom activities (not pose-countable) are verified entirely through
///   OpenAI vision: the user captures a photo and BeniAI judges it.
class ActivityVerificationScreen extends ConsumerStatefulWidget {
  const ActivityVerificationScreen({super.key, required this.alarmId});

  final String alarmId;

  @override
  ConsumerState<ActivityVerificationScreen> createState() => _ActivityVerificationScreenState();
}

class _ActivityVerificationScreenState extends ConsumerState<ActivityVerificationScreen> {
  CameraController? _controller;
  final _poseService = PoseDetectionService();
  RepCounter? _repCounter;

  List<CameraDescription> _cameras = const [];
  int _cameraIndex = 0;
  bool _switchingCamera = false;

  bool _isVerifyingCustom = false;
  bool _isStreaming = false;
  bool _completed = false;

  String? _error;
  String _statusMessage = 'Get in frame to begin.';
  int _count = 0;

  /// The activity's saved reference demo photo, if it has one - fetched
  /// once and passed to OpenAI vision alongside each live capture so it can
  /// compare what the user's doing now against what they actually
  /// demonstrated, instead of judging from a text label alone.
  Uint8List? _referenceImageBytes;

  @override
  void initState() {
    super.initState();
    ref.read(analyticsServiceProvider).track(AnalyticsEvents.activityVerificationStarted, {
      'alarm_id': widget.alarmId,
    });
    _setup();
  }

  Future<void> _setup() async {
    final alarm = ref.read(alarmByIdProvider(widget.alarmId));
    if (alarm == null) {
      setState(() => _error = 'Could not load this alarm.');
      return;
    }

    final granted = await ensureCameraPermission();
    if (!granted) {
      setState(
        () => _error = 'Camera permission is required to verify your activity and stop the alarm.',
      );
      return;
    }

    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() => _error = 'No camera found on this device.');
        return;
      }
      // Front camera by default: when the phone is propped up during a
      // workout, the screen (and its status text / rep count) needs to
      // face the user, not away from them. A switch button lets them
      // flip to the back camera if they'd rather prop it facing away.
      _cameraIndex = _cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.front);
      if (_cameraIndex < 0) _cameraIndex = 0;

      await _startCamera(_cameras[_cameraIndex]);

      _repCounter = RepCounter(alarm.activityType);

      if (alarm.activityPreset.supportsPoseDetection) {
        await _startTracking();
      } else {
        setState(() => _statusMessage = 'Capture a photo showing you\'ve done it.');
        _loadReferenceImage(alarm.referenceImageUrl);
      }
    } catch (e) {
      setState(() => _error = 'Could not start the camera: $e');
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
        imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not switch camera: $e');
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _switchingCamera) return;
    final alarm = ref.read(alarmByIdProvider(widget.alarmId));
    if (alarm == null) return;

    setState(() => _switchingCamera = true);
    await _stopTracking();

    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    await _startCamera(_cameras[_cameraIndex]);

    if (!mounted) return;
    if (alarm.activityPreset.supportsPoseDetection) {
      await _startTracking();
    }
    setState(() => _switchingCamera = false);
  }

  Future<void> _startTracking() async {
    final controller = _controller;
    if (controller == null || _isStreaming) return;
    _isStreaming = true;
    _repCounter?.rearm();
    setState(() => _statusMessage = 'Tracking your reps...');
    await controller.startImageStream(_onCameraFrame);
  }

  Future<void> _stopTracking() async {
    final controller = _controller;
    if (controller == null || !_isStreaming) return;
    _isStreaming = false;
    try {
      await controller.stopImageStream();
    } catch (_) {
      // Already stopped.
    }
  }

  void _onCameraFrame(CameraImage image) {
    final controller = _controller;
    final repCounter = _repCounter;
    if (controller == null || repCounter == null || _completed) {
      return;
    }

    _poseService.processCameraImage(image, controller.description).then((pose) {
      if (!mounted || pose == null || _completed) return;
      final gotNewRep = repCounter.processPose(pose);
      if (gotNewRep) {
        setState(() => _count = repCounter.reps);
        ref.read(analyticsServiceProvider).track(AnalyticsEvents.activityRepCounted, {
          'alarm_id': widget.alarmId,
          'count': _count,
        });
        final alarm = ref.read(alarmByIdProvider(widget.alarmId));
        if (alarm != null && _count >= alarm.targetReps) {
          _completeVerification();
        }
      }
    });
  }

  /// Best-effort fetch of the alarm's saved reference demo photo (if it has
  /// one) so it can be compared against live captures. Failures are silent
  /// since the custom-activity flow still works fine without it.
  Future<void> _loadReferenceImage(String? url) async {
    if (url == null || url.isEmpty) return;
    try {
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200 && mounted) {
        _referenceImageBytes = response.bodyBytes;
      }
    } catch (_) {
      // No reference image available for this session - not fatal.
    }
  }

  Future<void> _captureCustomActivity() async {
    final alarm = ref.read(alarmByIdProvider(widget.alarmId));
    final controller = _controller;
    if (alarm == null || controller == null || _isVerifyingCustom) return;

    setState(() {
      _isVerifyingCustom = true;
      _statusMessage = 'Checking with BeniAI...';
    });

    try {
      final file = await controller.takePicture();
      final bytes = await file.readAsBytes();
      final ActivityVisionCheck result = await ref
          .read(openAIServiceProvider)
          .verifyActivityFrame(
            jpegBytes: bytes,
            activityLabel: alarm.activityLabel,
            targetCount: alarm.targetReps,
            currentCount: _count,
            referenceJpegBytes: _referenceImageBytes,
          );

      if (!mounted) return;

      if (result.looksComplete) {
        setState(() => _count = alarm.targetReps);
        await _completeVerification();
      } else {
        setState(() {
          _statusMessage = result.reasoning.isNotEmpty
              ? result.reasoning
              : "Doesn't look complete yet - try again.";
        });
      }
    } catch (e) {
      if (mounted) setState(() => _statusMessage = 'Could not verify: $e');
    } finally {
      if (mounted) setState(() => _isVerifyingCustom = false);
    }
  }

  Future<void> _completeVerification() async {
    if (_completed) return;
    _completed = true;
    await _stopTracking();

    final alarm = ref.read(alarmByIdProvider(widget.alarmId));
    if (alarm != null) {
      await ref.read(alarmSchedulerServiceProvider).stopById(alarm.nativeAlarmId);
    }

    final analytics = ref.read(analyticsServiceProvider);
    analytics.track(AnalyticsEvents.activityVerificationCompleted, {'alarm_id': widget.alarmId});
    analytics.track(AnalyticsEvents.alarmDismissed, {'alarm_id': widget.alarmId});

    if (!mounted) return;
    setState(() => _statusMessage = 'Nice work! Alarm stopped.');

    await Future<void>.delayed(const Duration(milliseconds: 1400));
    if (mounted) context.go(AppRoutes.home);
  }

  @override
  void dispose() {
    _controller?.dispose();
    _poseService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final alarm = ref.watch(alarmByIdProvider(widget.alarmId));

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: _error != null
              ? _buildError()
              : (_controller == null || !_controller!.value.isInitialized || alarm == null)
              ? const Center(child: CircularProgressIndicator(color: Colors.white))
              : _buildCameraUi(alarm.activityPreset),
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_off_outlined, color: Colors.white, size: 56),
            const SizedBox(height: 16),
            Text(
              _error!,
              style: const TextStyle(color: Colors.white),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraUi(ActivityPreset preset) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: AspectRatio(
            aspectRatio: _controller!.value.aspectRatio,
            child: CameraPreview(_controller!),
          ),
        ),
        Positioned(
          top: 16,
          left: 16,
          right: 16,
          child: Column(
            children: [
              Text(
                _statusMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  shadows: [Shadow(blurRadius: 8, color: Colors.black)],
                ),
              ),
              if (_cameras.length > 1)
                IconButton(
                  onPressed: _switchingCamera ? null : _switchCamera,
                  icon: const Icon(Icons.cameraswitch_outlined, color: Colors.white),
                  tooltip: 'Switch camera',
                ),
            ],
          ),
        ),
        Positioned(
          bottom: 32,
          left: 0,
          right: 0,
          child: Center(
            child: preset.supportsPoseDetection
                ? RepProgressRing(
                    current: _count,
                    target: ref.watch(alarmByIdProvider(widget.alarmId))?.targetReps ?? 1,
                    unitLabel: preset.unitLabel,
                  )
                : ElevatedButton.icon(
                    onPressed: _isVerifyingCustom ? null : _captureCustomActivity,
                    icon: _isVerifyingCustom
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.camera_alt),
                    label: Text(_isVerifyingCustom ? 'Checking...' : 'Verify with Camera'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
