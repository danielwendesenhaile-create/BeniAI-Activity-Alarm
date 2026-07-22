import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
///   counted live on-device with ML Kit pose detection.
/// - A periodic OpenAI vision spot-check runs alongside it (hybrid mode) as
///   a light sanity check.
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

  Timer? _spotCheckTimer;
  bool _spotChecking = false;
  bool _isVerifyingCustom = false;
  bool _isStreaming = false;
  bool _completed = false;

  String? _error;
  String _statusMessage = 'Get in frame to begin.';
  int _count = 0;

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
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _error = 'No camera found on this device.');
        return;
      }
      var camera = cameras.first;
      final backCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => camera,
      );
      camera = backCamera;

      _controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
      );
      await _controller!.initialize();

      _repCounter = RepCounter(alarm.activityType);

      if (mounted) setState(() {});

      if (alarm.activityPreset.supportsPoseDetection) {
        await _startTracking();
        _scheduleSpotCheck();
      } else {
        setState(() => _statusMessage = 'Capture a photo showing you\'ve done it.');
      }
    } catch (e) {
      setState(() => _error = 'Could not start the camera: $e');
    }
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
    if (controller == null || repCounter == null || _completed || _spotChecking) {
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

  void _scheduleSpotCheck() {
    _spotCheckTimer = Timer.periodic(const Duration(seconds: 18), (_) {
      _runSpotCheck();
    });
  }

  Future<void> _runSpotCheck() async {
    final alarm = ref.read(alarmByIdProvider(widget.alarmId));
    final controller = _controller;
    if (alarm == null || controller == null || _completed || _spotChecking) return;

    setState(() => _spotChecking = true);
    try {
      await _stopTracking();
      final file = await controller.takePicture();
      final bytes = await file.readAsBytes();
      final result = await ref
          .read(openAIServiceProvider)
          .verifyActivityFrame(
            jpegBytes: bytes,
            activityLabel: alarm.activityLabel,
            targetCount: alarm.targetReps,
            currentCount: _count,
          );
      if (!mounted) return;
      setState(() {
        _statusMessage = result.isPerformingActivity
            ? 'Looking good - keep going!'
            : "Make sure BeniAI can see you doing it.";
      });
    } catch (_) {
      // Spot-checks are best-effort; ignore failures.
    } finally {
      if (mounted) {
        setState(() => _spotChecking = false);
      }
      if (!_completed) await _startTracking();
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
    _spotCheckTimer?.cancel();
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
    _spotCheckTimer?.cancel();
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
          child: Text(
            _statusMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              shadows: [Shadow(blurRadius: 8, color: Colors.black)],
            ),
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
