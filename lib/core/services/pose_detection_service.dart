import 'dart:io';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// Wraps ML Kit's [PoseDetector] and knows how to turn a raw [CameraImage]
/// (as delivered by `CameraController.startImageStream`) into the
/// [InputImage] format ML Kit expects.
class PoseDetectionService {
  PoseDetectionService()
    : _detector = PoseDetector(
        options: PoseDetectorOptions(
          mode: PoseDetectionMode.stream,
          model: PoseDetectionModel.base,
        ),
      );

  final PoseDetector _detector;
  bool _isBusy = false;

  bool get isBusy => _isBusy;

  /// Processes a camera frame and returns the first detected [Pose], or
  /// null if no pose was found, the frame couldn't be converted, or a
  /// previous frame is still being processed (frames are dropped rather
  /// than queued to keep up with the camera feed).
  Future<Pose?> processCameraImage(CameraImage image, CameraDescription camera) async {
    if (_isBusy) return null;
    _isBusy = true;
    try {
      final inputImage = _inputImageFromCameraImage(image, camera);
      if (inputImage == null) return null;
      final poses = await _detector.processImage(inputImage);
      return poses.isEmpty ? null : poses.first;
    } catch (e) {
      debugPrint('PoseDetectionService: failed to process frame: $e');
      return null;
    } finally {
      _isBusy = false;
    }
  }

  InputImage? _inputImageFromCameraImage(CameraImage image, CameraDescription camera) {
    final rotation = _rotationFromSensorOrientation(camera.sensorOrientation);
    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    final isValidFormat = Platform.isAndroid
        ? format == InputImageFormat.nv21
        : format == InputImageFormat.bgra8888;
    if (format == null || !isValidFormat) return null;

    if (image.planes.length != 1) return null;
    final plane = image.planes.first;

    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  InputImageRotation? _rotationFromSensorOrientation(int sensorOrientation) {
    switch (sensorOrientation) {
      case 0:
        return InputImageRotation.rotation0deg;
      case 90:
        return InputImageRotation.rotation90deg;
      case 180:
        return InputImageRotation.rotation180deg;
      case 270:
        return InputImageRotation.rotation270deg;
      default:
        return null;
    }
  }

  Future<void> dispose() => _detector.close();
}
