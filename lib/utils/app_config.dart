import 'package:dramix/services/api_service.dart';
import 'package:flutter/material.dart';

class AppConfig {
  static int _appMode = 1; // 1 = paid, 0 = free
  static int _freeModeAds = 1; // 1 = ads enabled in free mode, 0 = disabled

  static bool get isFreeMode => _appMode == 0;
  static int get appMode => _appMode;
  static bool get freeModeAdsEnabled => _freeModeAds == 1;

  static Future<void> loadAppConfig() async {
    try {
      final response = await ApiService().getAppConfig();
      if (response['status'] == 'success') {
        _appMode = response['app_mode'] ?? _appMode;
        _freeModeAds = response['free_mode_ads'] ?? _freeModeAds;
      }
    } catch (e) {
      debugPrint('خطأ في تحميل إعدادات التطبيق: $e');
    }
  }
}
