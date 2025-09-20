import 'package:dramix/screens/Home_Screenn.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';

class LoginPage extends StatefulWidget {
  final VoidCallback? onLoginSuccess;
  const LoginPage({super.key, this.onLoginSuccess});

  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _isLoading = false;
  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
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
            MaterialPageRoute(builder: (context) => const MainNavigationScreen()),
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

  // دالة تسجيل الدخول بحساب فيسبوك (يمكنك تنفيذها لاحقاً)
  // ignore: unused_element
  Future<void> _signInWithFacebook() async {
    // سيتم تنفيذها لاحقاً
  }

  // دالة تسجيل الدخول بحساب تيك توك (يمكنك تنفيذها لاحقاً)
  // ignore: unused_element
  Future<void> _signInWithTikTok() async {
    // سيتم تنفيذها لاحقاً
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // خلفية ثابتة للمسلسلات الآسيوية
          Container(
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/images/asian_drama_bg.jpg'),
                fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(
                  Colors.black54,
                  BlendMode.darken,
                ),
              ),
            ),
          ),

          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 20),
                    
                    // شعار التطبيق
                    Image.asset(
                      'assets/images/dramix_logo.png',
                      height: 120,
                      width: 120,
                    ),
                    
                    const SizedBox(height: 30),
                    
                    const Text(
                      'سجل الدخول',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),

                    const SizedBox(height: 10),
                    
                    const Text(
                      'لمتابعة أفضل المسلسلات والافلام الآسيوية',
                      style: TextStyle(fontSize: 16, color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 100),

                    // زر تسجيل الدخول بحساب جوجل
                    _buildSocialLoginButton(
                      'متابعة بحساب Google',
                      'assets/images/ic_login_tips_google.png',
                      _signInWithGoogle,
                    ),

                    //const SizedBox(height: 20),

                    // زر تسجيل الدخول بحساب فيسبوك
                   /// _buildSocialLoginButton(
                     /// 'متابعة بحساب Facebook',
                    ///  'assets/images/ic_login_facebook.png',
                     // _signInWithFacebook,
                    //),

                   // const SizedBox(height: 20),

                    // زر تسجيل الدخول بحساب تيك توك
                   /// _buildSocialLoginButton(
                      //'متابعة بحساب TikTok',
                     // 'assets/images/ic_login_tiktok.png',
                     // _signInWithTikTok,
                  //  ),

                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),

          // مؤشر التحميل
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

  // دالة مساعدة لبناء أزرار تسجيل الدخول
  Widget _buildSocialLoginButton(String text, String iconPath, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      height: 55,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.black.withOpacity(0.6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(
              color: Colors.white24,
              width: 1,
            ),
          ),
          elevation: 5,
        ),
        onPressed: onPressed,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              iconPath,
              height: 25,
              width: 25,
            ),
            const SizedBox(width: 12),
            Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}