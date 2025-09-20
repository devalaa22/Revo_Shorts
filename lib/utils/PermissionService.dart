import 'package:permission_handler/permission_handler.dart';
import 'dart:io';

class PermissionService {
  // طلب إذن الكاميرا
  Future<void> requestCameraPermission() async {
    final status = await Permission.camera.status;
    if (status.isDenied) {
      final result = await Permission.camera.request();
      if (result.isGranted) {
        print('Camera permission granted');
      } else {
        print('Camera permission denied');
      }
    } else if (status.isGranted) {
      print('Camera permission already granted');
    }
  }

  // طلب إذن الميكروفون
  Future<void> requestMicrophonePermission() async {
    final status = await Permission.microphone.status;
    if (status.isDenied) {
      final result = await Permission.microphone.request();
      if (result.isGranted) {
        print('Microphone permission granted');
      } else {
        print('Microphone permission denied');
      }
    } else if (status.isGranted) {
      print('Microphone permission already granted');
    }
  }

  // طلب إذن الموقع (Location)
  Future<void> requestLocationPermission() async {
    final status = await Permission.location.status;
    if (status.isDenied) {
      final result = await Permission.location.request();
      if (result.isGranted) {
        print('Location permission granted');
      } else {
        print('Location permission denied');
      }
    } else if (status.isGranted) {
      print('Location permission already granted');
    }
  }

  // طلب إذن الوصول إلى التخزين (Storage)
  Future<void> requestStoragePermission() async {
    final status = await Permission.storage.status;
    if (status.isDenied) {
      final result = await Permission.storage.request();
      if (result.isGranted) {
        print('Storage permission granted');
      } else {
        print('Storage permission denied');
      }
    } else if (status.isGranted) {
      print('Storage permission already granted');
    }
  }

  // طلب إذن الإشعارات (Notifications)
  Future<void> requestNotificationPermission() async {
    final status = await Permission.notification.status;
    if (status.isDenied) {
      final result = await Permission.notification.request();
      if (result.isGranted) {
        print('Notification permission granted');
      } else {
        print('Notification permission denied');
      }
    } else if (status.isGranted) {
      print('Notification permission already granted');
    }
  }

  // طلب إذن الوصول إلى الوسائط (Media) في Android 13 (Tiramisu)
  Future<void> requestMediaPermission() async {
    if (Platform.version.contains('Tiramisu')) {
      final status = await Permission.mediaLibrary.status;
      if (status.isDenied) {
        final result = await Permission.mediaLibrary.request();
        if (result.isGranted) {
          print('Media permission granted');
        } else {
          print('Media permission denied');
        }
      } else if (status.isGranted) {
        print('Media permission already granted');
      }
    }
  }
}
