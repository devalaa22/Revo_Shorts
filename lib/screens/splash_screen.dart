import 'package:dramix/models/episode.dart';
import 'package:dramix/screens/TVseriesplayer.dart';
import 'package:dramix/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_links/app_links.dart';
import 'dart:async';

import 'package:dramix/screens/Home_Screenn.dart';
import 'package:dramix/screens/login_page.dart';

class FuturisticSplashScreen extends StatefulWidget {
  const FuturisticSplashScreen({super.key});

  @override
  State<FuturisticSplashScreen> createState() => _FuturisticSplashScreenState();
}

class _FuturisticSplashScreenState extends State<FuturisticSplashScreen> {
  Uri? _initialUri;
  StreamSubscription<Uri?>? _sub;

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
    _startSplashTimer();
  }

  void _initDeepLinks() async {
    final appLinks = AppLinks();

    // الرابط الأولي (عند فتح التطبيق من إعلان/رابط خارجي)
    try {
      final Uri? initialUri = await appLinks.getInitialLink();
      if (initialUri != null) {
        _initialUri = initialUri;
      }
    } catch (e) {
      debugPrint('خطأ في الحصول على الرابط الأولي: $e');
    }

    // الاستماع للروابط أثناء عمل التطبيق (background / foreground)
    _sub = appLinks.uriLinkStream.listen(
      (Uri? uri) {
        if (uri != null) {
          _initialUri = uri;
        }
      },
      onError: (err) {
        debugPrint('خطأ في الاستماع للروابط: $err');
      },
    );
  }

  Future<void> _startSplashTimer() async {
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;

    // تحقق إذا كان التطبيق فتح من رابط خارجي
    if (_initialUri != null) {
      final queryParams = _initialUri!.queryParameters;
      final seriesId = queryParams['series'];

      if (seriesId != null) {
        final episodes = await fetchEpisodesForSeries(seriesId);
        if (!mounted) return;

        // افتح TVseriesplayer مباشرة مع الحلقات
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => TVseriesplayer(
              episodes: episodes,
              initialIndex: 0, // يبدأ من الحلقة الأولى
              seriesId: int.parse(seriesId),
              seriesTitle: null,
              seriesImageUrl: null,
            ),
          ),
        );
        return; // يمنع الانتقال للشاشة الرئيسية بعد Deep Link
      }
    }

    // إذا لم يكن هناك رابط، تابع شاشة تسجيل الدخول/الرئيسية
    final prefs = await SharedPreferences.getInstance();
    final isLoggedIn = prefs.getBool('isLoggedIn') ?? false;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) =>
            isLoggedIn ? const MainNavigationScreen() : const LoginPage(),
      ),
    );
  }

  Future<List<Episode>> fetchEpisodesForSeries(String seriesId) async {
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final intId = int.tryParse(seriesId);
      if (intId == null) {
        debugPrint('خطأ: seriesId غير صالح');
        return [];
      }
      return await apiService.getEpisodesBySeries(intId);
    } catch (e) {
      debugPrint('خطأ في جلب الحلقات من API: $e');
      return [];
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/images/dramix_logo.png',
              width: 150,
              height: 150,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 20),
            const Text(
              "Revo Shorts",
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
