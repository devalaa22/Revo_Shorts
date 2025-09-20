import 'dart:async';

import 'package:dramix/main.dart';
import 'package:flutter/material.dart';
import 'package:dramix/screens/Home_Screenn.dart';
//import 'package:flutter_windowmanager/flutter_windowmanager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import 'package:flutter/scheduler.dart';

class LoginPage extends StatefulWidget {
  final VoidCallback? onLoginSuccess;
  const LoginPage({super.key, this.onLoginSuccess});

  @override
  // ignore: library_private_types_in_public_api
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _isLoading = false;
  final AuthService _authService = AuthService();
  late PageController _pageController;
  int _currentPage = 0;
  late Timer _timer;

  // قائمة بصور الخلفية
  final List<String> _backgroundImages = [
    'assets/images/bg1.jpg',
    'assets/images/bg2.jpg',
    'assets/images/bg3.jpg',
    'assets/images/bg4.jpg',
  ];

  @override
  void initState() {
    super.initState();
    checkPackageName();

    //FlutterWindowManager.addFlags(FlutterWindowManager.FLAG_SECURE);
    // تحريك اللوجو
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    // تحريك الخلفية
    _pageController = PageController(initialPage: 0);
    _startBackgroundAnimation();

    SchedulerBinding.instance.addPostFrameCallback((_) {
      _checkLoginStatus();
    });
  }

  void _startBackgroundAnimation() {
    _timer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_currentPage < _backgroundImages.length - 1) {
        _currentPage++;
      } else {
        _currentPage = 0;
      }

      if (mounted) {
        _pageController.animateToPage(
          _currentPage,
          duration: const Duration(milliseconds: 1000),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  Future<void> _checkLoginStatus() async {
    final isLoggedIn = await _authService.isSignedIn();
    if (isLoggedIn && widget.onLoginSuccess != null) {
      widget.onLoginSuccess!();
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      final result = await _authService.signInWithGoogle();
      if (result['success'] && mounted) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('isLoggedIn', true);
        await prefs.setString('user_name', result['user']['name'] ?? '');
        await prefs.setString('user_email', result['user']['email']);
        await prefs.setString('user_photo', result['photo_url'] ?? '');
        await prefs.setInt('user_coins', result['user']['coins'] ?? 0);
        await prefs.setString('user_id', result['user']['id'].toString());

        if (mounted) {
          Navigator.pushReplacement(
            context,
            PageRouteBuilder(
              pageBuilder: (_, __, ___) => const MainNavigationScreen(),
              transitionsBuilder: (_, a, __, c) =>
                  FadeTransition(opacity: a, child: c),
              transitionDuration: const Duration(milliseconds: 800),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ أثناء تسجيل الدخول: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _pageController.dispose();
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // خلفية متحركة ضبابية
          PageView.builder(
            controller: _pageController,
            itemCount: _backgroundImages.length,
            itemBuilder: (context, index) {
              return AnimatedBuilder(
                animation: _pageController,
                builder: (context, child) {
                  final page = index.toDouble();
                  final value = (_pageController.page ?? 0) - page;
                  final opacity = 1.0 - (value.abs() * 0.5).clamp(0.0, 1.0);

                  return Opacity(
                    opacity: opacity,
                    child: Container(
                      decoration: BoxDecoration(
                        image: DecorationImage(
                          image: AssetImage(_backgroundImages[index]),
                          fit: BoxFit.cover,
                          colorFilter: ColorFilter.mode(
                            Colors.black.withOpacity(0.6),
                            BlendMode.darken,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),

          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 40),
                    const Text(
                      'مرحباً بعودتك!',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),

                    const SizedBox(height: 10),
                    const Text(
                      'سجل الدخول لمتابعة أفضل المسلسلات الصينية',
                      style: TextStyle(fontSize: 16, color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 60),

                    SizedBox(
                      width: double.infinity,
                      height: 60,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black.withOpacity(0.7),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(25),
                            side: const BorderSide(
                              color: Colors.white,
                              width: 2,
                            ),
                          ),
                          elevation: 8,
                        ),
                        onPressed: _isLoading ? null : _signInWithGoogle,
                        child: _isLoading
                            ? const CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.deepPurple,
                                ),
                              )
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Image.asset(
                                    'assets/images/ic_login_tips_google.png',
                                    height: 30,
                                  ),
                                  const SizedBox(width: 12),
                                  const Text(
                                    'متابعة بحساب Google',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.7),
              child: const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.deepPurple),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
