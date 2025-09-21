import 'dart:convert';

import 'package:dramix/services/ApiEndpoints.dart';
import 'package:dramix/utils/app_config.dart';
import 'package:dramix/utils/fcm_notification_service.dart';
import 'package:dramix/screens/splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_update/in_app_update.dart';
import 'package:logger/logger.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'l10n/app_localizations.dart';
import 'services/api_service.dart';

final Logger logger = Logger();

// 🔹 معالج الإشعارات في الخلفية
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint("📩 رسالة في الخلفية: ${message.data}");

  final data = message.data;
  if (data['type'] == 'new_series') {
    await NotificationService.showSeriesNotification(
      seriesId: data['series_id'] ?? '0',
      seriesTitle: data['series_title'] ?? 'مسلسل جديد',
      seriesDescription: data['series_description'] ?? 'مسلسل جديد متاح الآن!',
      imageUrl: data['image_url'] ?? '',
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // تهيئة الإشعارات بعد Firebase
  await NotificationService.init();

  // Provide a friendly error screen for uncaught errors (prevents red error screen)
  ErrorWidget.builder = (FlutterErrorDetails details) {
    // Log the error for debugging
    debugPrint('Unhandled Flutter error: ${details.exceptionAsString()}');
    return MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'حدث خطأ غير متوقع. الرجاء إعادة المحاولة لاحقاً. \n${details.exceptionAsString()}',
              style: const TextStyle(color: Colors.white),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  };

  // 🔹 تشغيل التطبيق مباشرة مع عرض Splash Screen
  runApp(
    MultiProvider(
      providers: [Provider(create: (context) => ApiService())],
      child: const MyApp(),
    ),
  );

  // 🔹 بعد عرض الشاشة، نفذ العمليات الثقيلة في الخلفية
  _initializeApp();
}

// 🔹 دالة لتهيئة كل العمليات الثقيلة في الخلفية
Future<void> _initializeApp() async {
  try {
    await initAdMobAppId("app_id");
    await AppConfig.loadAppConfig();
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    await FirebaseMessaging.instance.subscribeToTopic('all');
    await MobileAds.instance.initialize();
    await NotificationService.init();
    await _checkForUpdate();
  } catch (e) {
    debugPrint("❌ خطأ أثناء تهيئة التطبيق: $e");
  }

  // 🔹 معالجة الإشعارات أثناء التطبيق يعمل
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    debugPrint("📩 رسالة واردة: ${message.data}");
    final data = message.data;
    if (data['type'] == 'new_series') {
      NotificationService.showSeriesNotification(
        seriesId: data['series_id'] ?? '0',
        seriesTitle: data['series_title'] ?? 'مسلسل جديد',
        seriesDescription:
            data['series_description'] ?? 'مسلسل جديد متاح الآن!',
        imageUrl: data['image_url'] ?? '',
      );
    }
  });

  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    debugPrint("🔗 فتح من الإشعار: ${message.data}");
    // توجه إلى صفحة المسلسل
  });
}

// 🔹 نقل فحص التحديثات إلى دالة منفصلة
Future<void> _checkForUpdate() async {
  try {
    AppUpdateInfo info = await InAppUpdate.checkForUpdate();

    if (info.updateAvailability == UpdateAvailability.updateAvailable) {
      await InAppUpdate.performImmediateUpdate();
    }
  } catch (e) {
    debugPrint("❌ خطأ أثناء فحص التحديث: $e");
  }
}

// 🔹 تهيئة AdMob
Future<void> initAdMobAppId(String keyName) async {
  try {
    final response = await http.get(
      Uri.parse('${ApiEndpoints.getAdMob}?key=$keyName'),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final appId = data['app_id'].toString();

      await MobileAds.instance.initialize();

      logger.i("✅ AdMob App ID Loaded: $appId"); // Log success
    } else {
      logger.w("⚠️ Unexpected status code: ${response.statusCode}");
    }
  } catch (e, stack) {
    logger.e("❌ Error fetching App ID", error: e, stackTrace: stack);
  }
}

// 🔹 التحقق من اسم الحزمة
Future<bool> checkPackageName() async {
  final info = await PackageInfo.fromPlatform();
  const encoded = "Y29tLmFsYWEuZHJhbWV4YXN5cmlh";
  final decoded = utf8.decode(base64.decode(encoded));
  return info.packageName == decoded;
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Revo Shorts',
      theme: ThemeData(
        fontFamily: 'Tajawal',
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: Colors.black,
      ),
      home: const FuturisticSplashScreen(), // 🔹 عرض Splash Screen فورًا
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('ar')],
      locale: const Locale('ar'),
    );
  }
}
