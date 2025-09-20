import 'package:dramix/services/api_service.dart';
import 'package:flutter/material.dart';

class AppConfig {
  static int _appMode = 1; // 1 = paid, 0 = free
  
  static bool get isFreeMode => _appMode == 0;
  static int get appMode => _appMode;
  
  static Future<void> loadAppMode() async {
    try {
      final response = await ApiService().getAppMode();
      if (response['status'] == 'success') {
        _appMode = response['app_mode'];
      }
    } catch (e) {
      debugPrint('خطأ في تحميل وضع التطبيق: $e');
    }
  }
}