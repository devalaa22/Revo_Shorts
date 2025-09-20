import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  /// ✅ التهيئة
  static Future<void> init() async {
    // أندرويد
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS
    final DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
          notificationCategories: [
            DarwinNotificationCategory(
              'series_notifications',
              actions: <DarwinNotificationAction>[
                DarwinNotificationAction.plain(
                  'watch_now',
                  '🎬 شاهد الآن',
                  options: <DarwinNotificationActionOption>{
                    DarwinNotificationActionOption.foreground,
                  },
                ),
              ],
            ),
          ],
        );

    final InitializationSettings settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notificationsPlugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        if (response.payload != null) {
          final data = jsonDecode(response.payload!);
          debugPrint("📩 تم الضغط على الإشعار: $data");

          // معالجة الضغط على زر "شاهد الآن"
          if (response.actionId == 'watch_now') {
            debugPrint("🎬 تم الضغط على زر 'شاهد الآن'");
            // توجه إلى صفحة المشاهدة
            _navigateToSeries(data['series_id']);
          }
        }
      },
    );

    // قناة إشعارات احترافية
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'professional_series_channel',
      'إشعارات المسلسلات',
      description: 'إشعارات المسلسلات الاحترافية',
      importance: Importance.max,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('notification_sound'),
      enableVibration: true,
      ledColor: Color(0xFFFF0000),
      showBadge: true,
    );

    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);

    // 🔹 إعداد FCM
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);
    await messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  /// ✅ عرض إشعار مسلسل احترافي مع زر "شاهد الآن"
  static Future<void> showSeriesNotification({
    required String seriesId,
    required String seriesTitle,
    required String seriesDescription,
    required String imageUrl,
  }) async {
    try {
      // تحميل الصورة
      final String? imagePath = await _downloadAndSaveImage(imageUrl);

      // إعدادات الأزرار
      const List<AndroidNotificationAction> actions = [
        AndroidNotificationAction(
          'watch_now',
          '🎬 شاهد الآن',
          showsUserInterface: true,
        ),
      ];

      // إعداد نمط الصورة الكبيرة
      BigPictureStyleInformation? bigPictureStyle;
      if (imagePath != null) {
        bigPictureStyle = BigPictureStyleInformation(
          FilePathAndroidBitmap(imagePath),
          largeIcon: FilePathAndroidBitmap(imagePath),
          contentTitle: '🎬 $seriesTitle',
          htmlFormatContentTitle: true,
          summaryText: seriesDescription,
          htmlFormatSummaryText: true,
          hideExpandedLargeIcon: false,
        );
      }

      // إعدادات الإشعار لأندرويد
      final AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
            'professional_series_channel',
            'إشعارات المسلسلات',
            channelDescription: 'إشعارات المسلسلات الاحترافية',
            importance: Importance.max,
            priority: Priority.max,
            color: Colors.red,
            colorized: true,
            category: AndroidNotificationCategory.recommendation,
            visibility: NotificationVisibility.public,
            enableLights: true,
            ledColor: const Color(0xFFFF0000),
            ledOnMs: 500,
            ledOffMs: 500,
            playSound: true,
            sound: const RawResourceAndroidNotificationSound(
              'notification_sound',
            ),
            enableVibration: true,
            largeIcon: imagePath != null
                ? FilePathAndroidBitmap(imagePath)
                : const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
            styleInformation:
                bigPictureStyle ??
                BigTextStyleInformation(
                  seriesDescription,
                  htmlFormatBigText: true,
                  contentTitle: '🎬 $seriesTitle',
                  htmlFormatContentTitle: true,
                  summaryText: 'مسلسل جديد',
                  htmlFormatSummaryText: true,
                ),
            actions: actions,
            showWhen: true,
            autoCancel: true,
            timeoutAfter: 60000,
          );

      // إعدادات الإشعار لـ iOS
      final List<DarwinNotificationAttachment> attachments = [];
      if (imagePath != null) {
        attachments.add(DarwinNotificationAttachment(imagePath));
      }

      final DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        subtitle: seriesDescription,
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        badgeNumber: 1,
        categoryIdentifier: 'series_notifications',
        attachments: attachments,
      );

      // عرض الإشعار
      await _notificationsPlugin.show(
        int.tryParse(seriesId) ?? DateTime.now().millisecondsSinceEpoch,
        '🎬 $seriesTitle',
        seriesDescription,
        NotificationDetails(android: androidDetails, iOS: iosDetails),
        payload: jsonEncode({
          'type': 'series',
          'series_id': seriesId,
          'series_title': seriesTitle,
          'series_description': seriesDescription,
          'image_url': imageUrl,
        }),
      );
    } catch (e) {
      debugPrint('❌ Error showing series notification: $e');
    }
  }

  /// ✅ تحميل الصورة وحفظها مؤقتاً
  static Future<String?> _downloadAndSaveImage(String url) async {
    try {
      if (url.isEmpty) return null;

      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) return null;

      final directory = await getTemporaryDirectory();
      final imagePath =
          '${directory.path}/series_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final File imageFile = File(imagePath);
      await imageFile.writeAsBytes(response.bodyBytes);
      return imagePath;
    } catch (e) {
      debugPrint('❌ Error downloading image: $e');
      return null;
    }
  }

  /// ✅ التوجيه إلى صفحة المسلسل
  static void _navigateToSeries(String seriesId) {
    // استخدم Navigator أو أي طريقة للتوجيه في تطبيقك
    debugPrint("🔗 التوجيه إلى المسلسل: $seriesId");
    // مثال:
    // Navigator.push(context, MaterialPageRoute(builder: (context) => SeriesDetailScreen(seriesId: seriesId)));
  }

  static Future<void> cancelAllNotifications() async {
    await _notificationsPlugin.cancelAll();
  }
}
