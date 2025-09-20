import 'dart:math';
import 'package:dramix/models/UserModel.dart';
import 'package:dramix/screens/in_app_purchase.dart';
import 'package:dramix/screens/login_page.dart';
import 'package:dramix/services/api_service.dart';
import 'package:dramix/screens/VipPackagesScreen.dart';
import 'package:dramix/screens/DailyrewardsScreen.dart';
import 'package:dramix/utils/app_config.dart';
import 'package:flutter/material.dart';

///import 'package:flutter_windowmanager/flutter_windowmanager.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  final AuthService _authService = AuthService();
  User? _currentUser;
  bool _isLoading = true;
  String _appVersion = '';
  int _userCoins = 0;
  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    //FlutterWindowManager.addFlags(FlutterWindowManager.FLAG_SECURE);

    // تهيئة التحريك للخلفية المتحركة
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 15),
    )..repeat();

    _animation = Tween<double>(begin: 0, end: 2 * pi).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.linear),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    await _loadUserData();
    await _loadAppVersion();
    await _loadUserCoins();
    await _checkVipStatus();
    setState(() => _isLoading = false);
  }

  Future<void> _loadUserCoins() async {
    try {
      final isSignedIn = await AuthService().isSignedIn();
      if (!isSignedIn) return;

      final response = await ApiService().getUserCoins();
      if (response['status'] == 'success' && mounted) {
        setState(() {
          _userCoins = response['coins'] ?? 0;
        });
      }
    } catch (e) {
      debugPrint('Error loading user coins: $e');
    }
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final isLoggedIn = prefs.getBool('isLoggedIn') ?? false;

    if (isLoggedIn) {
      final user = await _authService.getCurrentUser();
      setState(() {
        _currentUser = User(
          id: user['id'] ?? '',
          name: user['name'] ?? prefs.getString('user_name') ?? 'مستخدم',
          email: user['email'] ?? prefs.getString('user_email') ?? '',
          photoUrl: user['photo_url'] ?? prefs.getString('user_photo'),
          coins: user['coins'] ?? prefs.getInt('user_coins') ?? 0,
          isVip: prefs.getBool('is_vip') ?? false,
          vipExpiry: prefs.getString('vip_expiry'),
        );
      });
    }
  }

  Future<void> _loadAppVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    setState(() {
      _appVersion = 'الإصدار ${packageInfo.version}';
    });
  }

  Future<void> _checkVipStatus() async {
    if (_currentUser == null) return;

    try {
      final response = await ApiService().checkVipStatus(
        int.parse(_currentUser!.id),
      );

      if (response['success'] == true && mounted) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('is_vip', response['is_vip']);
        await prefs.setString('vip_expiry', response['vip_expiry'] ?? '');

        setState(() {
          _currentUser = _currentUser!.copyWith(
            isVip: response['is_vip'],
            vipExpiry: response['vip_expiry'],
          );
        });
      }
    } catch (e) {
      debugPrint('Error checking VIP status: $e');
    }
  }

  void _handleLogin() async {
    try {
      final result = await _authService.signInWithGoogle();
      if (result['success'] == true) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('isLoggedIn', true);
        await prefs.setString('user_name', result['user']['name'] ?? '');
        await prefs.setString('user_email', result['user']['email']);
        await prefs.setString('user_photo', result['photo_url'] ?? '');
        await prefs.setInt('user_coins', result['user']['coins'] ?? 0);
        await prefs.setString('user_id', result['user']['id'].toString());

        setState(() {
          _currentUser = User(
            id: result['user']['id'].toString(),
            name: result['user']['name'] ?? result['user']['email'],
            email: result['user']['email'],
            photoUrl: result['photo_url'],
            coins: result['user']['coins'] ?? 0,
            isVip: prefs.getBool('is_vip') ?? false,
            vipExpiry: prefs.getString('vip_expiry'),
          );
        });
        await _checkVipStatus();
        showToast("تم تسجيل الدخول بنجاح");
      }
    } catch (e) {
      showToast("خطأ في تسجيل الدخول: ${e.toString()}");
    }
  }

  void showToast(String message) {
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      backgroundColor: Colors.grey[800],
      textColor: Colors.white,
    );
  }

  // دالة مشاركة التطبيق - محسنة
  Future<void> _shareApp() async {
    //try {
    final packageInfo = await PackageInfo.fromPlatform();
    String shareText =
        'قم بتنزيل تطبيق دراميكس الآن لمشاهدة أحدث المسلسلات والأفلام! '
        'https://play.google.com/store/apps/details?id=${packageInfo.packageName}';

    // مشاركة التطبيق مع خيارات محددة لضمان المشاركة الفعلية
    // ignore: deprecated_member_use, unused_local_variable
    final result = await Share.share(
      shareText,
      subject: 'تطبيق دراميكس - أفضل تطبيق للمسلسلات والأفلام',
    );

    // الانتظار قليلاً ثم التحقق من نجاح المشاركة
    await Future.delayed(const Duration(seconds: 2));

    // نعتبر أن المشاركة ناجحة إذا وصلنا إلى هذه النقطة بدون أخطاء
    // if (_currentUser != null) {
    //try {
    // إضافة 200 نقطة للمستخدم
    ///  final response = await ApiService().updateUserCoins(
    ///  int.parse(_currentUser!.id),
    // 200,
    // );

    // if (response['status'] == 'success') {
    ////  setState(() {
    //  _userCoins += 200;
    //    _currentUser = _currentUser!.copyWith(coins: _userCoins);
    //  });

    // حفظ في SharedPreferences أيضًا
    //  final prefs = await SharedPreferences.getInstance();
    // await prefs.setInt('user_coins', _userCoins);

    //   showToast('تم إضافة 200 نقطة إلى رصيدك!');
    // } else {
    //   debugPrint('فشل تحديث النقاط: ${response['message']}');
    // }
    //} catch (e) {
    //  debugPrint('حدث خطأ أثناء إضافة النقاط: $e');
    //}
    // }
  }

  // دالة تقييم التطبيق - محسنة
  Future<void> _rateApp() async {
    // try {
    final packageInfo = await PackageInfo.fromPlatform();
    final url = Uri.parse(
      'https://play.google.com/store/apps/details?id=${packageInfo.packageName}',
    );

    if (await canLaunchUrl(url)) {
      // إضافة النقاط مباشرة عند الضغط على التقييم (لضمان الحصول عليها)
      if (_currentUser != null) {
        //try {
        // final response = await ApiService().updateUserCoins(
        // int.parse(_currentUser!.id),
        //  200,
        // );

        // if (response['status'] == 'success') {
        /// setState(() {
        //  _userCoins += 200;
        //  _currentUser = _currentUser!.copyWith(coins: _userCoins);
        //  });

        // حفظ في SharedPreferences أيضًا
        // final prefs = await SharedPreferences.getInstance();
        ///  await prefs.setInt('user_coins', _userCoins);

        ///  showToast('تم إضافة 200 نقطة إلى رصيدك!');
        // }
        /// } catch (e) {
        ///   debugPrint('Error adding coins for rating: $e');
        // }
        // }

        // فتح رابط التقييم
        await launchUrl(url, mode: LaunchMode.externalApplication);
        //  } else {
        showToast('لا يمكن فتح متجر التطبيقات');
        // }
        // } catch (e) {
        //  debugPrint('Error rating app: $e');
        //showToast('حدث خطأ أثناء فتح متجر التطبيقات');
        // }
      }
    }
  }

  // دالة الاتصال بالدعم
  Future<void> _contactSupport() async {
    final Uri emailLaunchUri = Uri(
      scheme: 'mailto',
      path: 'dramixshorte@gmail.com',
      queryParameters: {
        'subject': 'استفسار عن تطبيق دراميكس',
        'body': 'أود الاستفسار عن...',
      },
    );

    if (await canLaunchUrl(emailLaunchUri)) {
      await launchUrl(emailLaunchUri);
    } else {
      showToast('لا يوجد تطبيق بريد إلكتروني مثبت');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // خلفية متحركة بتأثير التموجات
          AnimatedBuilder(
            animation: _animation,
            builder: (context, child) {
              return CustomPaint(
                painter: WavePainter(_animation.value),
                size: Size(MediaQuery.of(context).size.width, 250),
              );
            },
          ),

          SafeArea(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.pink),
                  )
                : _currentUser == null
                ? _buildGuestView()
                : RefreshIndicator(
                    onRefresh: _loadInitialData,
                    color: const Color.fromARGB(255, 41, 40, 40),
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(top: 120, bottom: 20),
                      child: Column(
                        children: [
                          _buildUserHeader(),
                          const SizedBox(height: 30),
                          _buildPremiumContent(),
                          const SizedBox(height: 25),
                          _buildWalletSection(),
                          const SizedBox(height: 25),
                          _buildMenuItems(),
                          const SizedBox(height: 20),
                          Center(
                            child: Text(
                              _appVersion,
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuestView() {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 100),
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.grey[800],
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color.fromARGB(255, 43, 42, 42),
                  width: 2,
                ),
              ),
              child: const Icon(
                Icons.person_outline,
                size: 60,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 30),
            const Text(
              'لم تقم بتسجيل الدخول بعد',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'سجل الدخول للوصول إلى جميع الميزات والحصول على تجربة متكاملة',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
            const SizedBox(height: 40),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color.fromARGB(255, 37, 37, 37),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 40,
                  vertical: 15,
                ),
                shadowColor: const Color.fromARGB(
                  255,
                  56,
                  56,
                  56,
                ).withOpacity(0.5),
                elevation: 8,
              ),
              onPressed: _handleLogin,
              child: const Text(
                'تسجيل الدخول',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserHeader() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color.fromARGB(255, 48, 47, 47).withOpacity(0.1),
            blurRadius: 15,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: _currentUser?.isVip == true ? Colors.amber : Colors.pink,
                width: 2,
              ),
            ),
            child: ClipOval(
              child: _currentUser?.photoUrl != null
                  ? Image.network(
                      _currentUser!.photoUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          const Icon(Icons.person, color: Colors.white),
                    )
                  : const Icon(Icons.person, size: 30, color: Colors.white),
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _currentUser?.name ?? 'مستخدم',
                        style: const TextStyle(
                          fontSize: 20,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_currentUser?.isVip == true)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.amber.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.amber, width: 1),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.verified, color: Colors.amber, size: 14),
                            SizedBox(width: 4),
                            Text(
                              'VIP',
                              style: TextStyle(
                                color: Colors.amber,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  _currentUser?.email ?? '',
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.star, color: Colors.amber, size: 16),
                    const SizedBox(width: 5),
                    Text(
                      'رصيدك: $_userCoins',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color.fromARGB(
                  255,
                  107,
                  107,
                  107,
                ).withOpacity(0.1),
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color.fromARGB(255, 99, 98, 98).withOpacity(0.3),
                ),
              ),
              child: const Icon(
                Icons.settings,
                color: Color.fromARGB(255, 201, 56, 11),
                size: 22,
              ),
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SettingsScreen(
                    user: _currentUser!,
                    onLogout: _handleLogout,
                  ),
                ),
              );
            },
            tooltip: 'الإعدادات',
          ),
        ],
      ),
    );
  }

  // إضافة دالة تسجيل الخروج
  void _handleLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLoggedIn', false);
    await _authService.signOut();
    setState(() => _currentUser = null);
    showToast("تم تسجيل الخروج بنجاح");
  }

  Widget _buildVipContent() {
    return Container(
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.amber.withOpacity(0.2),
            Colors.amber.withOpacity(0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.amber.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.amber.withOpacity(0.1),
            blurRadius: 15,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.workspace_premium,
                  color: Colors.amber,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'عضوية VIP مفعلة',
                style: TextStyle(
                  color: Colors.amber,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              const Icon(Icons.calendar_today, color: Colors.white, size: 16),
              const SizedBox(width: 8),
              Text(
                'ينتهي الاشتراك في: ${_formatDate(_currentUser?.vipExpiry ?? '')}',
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 15),
          ElevatedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => VipPackagesScreen(
                    userId: int.parse(_currentUser!.id),
                    userEmail: _currentUser!.email,
                    isVip: _currentUser!.isVip,
                    vipExpiry: _currentUser!.vipExpiry,
                  ),
                ),
              ).then((_) => _checkVipStatus());
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: const Text(
              'عرض تفاصيل العضوية',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String date) {
    try {
      final parsedDate = DateTime.parse(date);
      return DateFormat('yyyy-MM-dd').format(parsedDate);
    } catch (e) {
      return date;
    }
  }

  Widget _buildPremiumContent() {
    if (AppConfig.isFreeMode) return const SizedBox.shrink();
    if (_currentUser?.isVip == true) {
      return _buildVipContent();
    } else {
      return _buildSubscribeCard();
    }
  }

  Widget _buildSubscribeCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color.fromARGB(255, 51, 50, 51).withOpacity(0.15),
            const Color.fromARGB(255, 51, 50, 51).withOpacity(0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color.fromARGB(255, 46, 46, 46).withOpacity(0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color.fromARGB(255, 59, 59, 59).withOpacity(0.1),
            blurRadius: 15,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color.fromARGB(255, 66, 66, 66).withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.lock_outline,
                  color: Color.fromARGB(255, 12, 190, 51),
                  size: 24,
                ),
              ),

              const SizedBox(width: 12),
              const Text(
                'محتوى حصري لأعضاء VIP',
                style: TextStyle(
                  color: Color.fromARGB(255, 12, 8, 238),
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'تمتع بتجربة مشاهدة بدون إعلانات ووصول مبكر لأحدث المحتويات مع عضوية VIP',
            style: TextStyle(color: Colors.white70, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => VipPackagesScreen(
                    userId: int.parse(_currentUser!.id),
                    userEmail: _currentUser!.email,
                    isVip: _currentUser!.isVip,
                    vipExpiry: _currentUser!.vipExpiry,
                  ),
                ),
              ).then((_) => _checkVipStatus());
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color.fromARGB(255, 185, 10, 10),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shadowColor: const Color.fromARGB(
                255,
                204,
                202,
                203,
              ).withOpacity(0.5),
              elevation: 5,
            ),
            child: const Text(
              'اشترك الآن',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWalletSection() {
    if (AppConfig.isFreeMode) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.purple.withOpacity(0.1),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.account_balance_wallet_rounded,
                color: Color.fromARGB(255, 216, 101, 7),
                size: 24,
              ),
              SizedBox(width: 10),
              Text(
                'رصيد المحفظة',
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color.fromARGB(
                      255,
                      5,
                      9,
                      252,
                    ).withOpacity(0.3),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(
                      color: const Color.fromARGB(
                        255,
                        14,
                        11,
                        190,
                      ).withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,

                    children: [
                      const Text(
                        'الرصيد الحالي:',
                        style: TextStyle(
                          color: Color.fromARGB(179, 255, 255, 255),
                          fontSize: 16,
                        ),
                      ),
                      Row(
                        children: [
                          Text(
                            _userCoins.toString(),
                            style: const TextStyle(
                              fontSize: 18,
                              color: Color.fromARGB(255, 241, 241, 241),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 5),
                          const Text('🪙', style: TextStyle(fontSize: 18)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          ElevatedButton(
            onPressed: () async {
              final result = await Navigator.push<int>(
                context,
                MaterialPageRoute(
                  builder: (_) => in_app_purchase(
                    userId: int.tryParse(_currentUser!.id) ?? 0,
                    userEmail: _currentUser!.email,
                    currentCoins: _currentUser!.coins,
                  ),
                ),
              );

              if (result != null && mounted) {
                setState(() {
                  _currentUser = _currentUser!.copyWith(coins: result);
                  _userCoins = result;
                });
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color.fromARGB(255, 20, 6, 212),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              minimumSize: const Size(double.infinity, 50),
              shadowColor: const Color.fromARGB(
                255,
                13,
                22,
                153,
              ).withOpacity(0.4),
              elevation: 5,
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add, size: 20),
                SizedBox(width: 8),
                Text(
                  'إعادة تعبئة الرصيد',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItems() {
    final menuItems = [
      // إخفاء "كسب المكافآت" في الوضع المجاني
      if (!AppConfig.isFreeMode)
        {
          'icon': Icons.card_giftcard,
          'title': 'كسب المكافآت',
          'color': Colors.orange,
          'onTap': () async {
            final updatedBalance = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DailyRewardsScreen(
                  userId: int.tryParse(_currentUser!.id) ?? 0,
                  userEmail: _currentUser!.email,
                  currentCoins: _currentUser!.coins,
                ),
              ),
            );

            if (updatedBalance != null && mounted) {
              setState(() {
                _currentUser = _currentUser!.copyWith(coins: updatedBalance);
                _userCoins = updatedBalance;
              });
            }
          },
        },
      {
        'icon': Icons.settings,
        'title': 'الإعدادات',
        'color': Colors.blue,
        'onTap': () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                SettingsScreen(user: _currentUser!, onLogout: _handleLogout),
          ),
        ),
      },
      {
        'icon': Icons.help_center,
        'title': 'المساعدة والدعم',
        'color': Colors.green,
        'onTap': _contactSupport,
      },
      {
        'icon': Icons.star_rate_rounded,
        'title': 'تقييم التطبيق',
        'color': Colors.amber,
        'onTap': _rateApp,
      },
      {
        'icon': Icons.share,
        'title': 'مشاركة التطبيق',
        'color': const Color.fromARGB(255, 83, 1, 235),
        'onTap': _shareApp,
      },
    ];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: List.generate(
          menuItems.length,
          (index) => _buildMenuItem(
            menuItems[index]['icon'] as IconData,
            menuItems[index]['title'] as String,
            menuItems[index]['color'] as Color,
            onTap: menuItems[index]['onTap'] as VoidCallback?,
          ),
        ),
      ),
    );
  }

  Widget _buildMenuItem(
    IconData icon,
    String title,
    Color color, {
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          shape: BoxShape.circle,
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Icon(icon, color: color, size: 22),
      ),
      title: Text(
        title,
        style: const TextStyle(color: Colors.white, fontSize: 16),
      ),
      trailing: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(0.1),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.chevron_left, color: Colors.grey, size: 20),
      ),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }
}

// شاشة الإعدادات المعدلة
class SettingsScreen extends StatelessWidget {
  final User user;
  final VoidCallback onLogout;

  const SettingsScreen({super.key, required this.user, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('الإعدادات', style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ), 
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSettingItem(
            Icons.language,
            'اللغة',
            'العربية',
            onTap: () => _showLanguageDialog(context),
          ),
          _buildSettingItem(
            Icons.security,
            'الخصوصية',
            'إدارة بياناتك',
            onTap: () => _showPrivacyPolicy(context),
          ),
          _buildSettingItem(
            Icons.logout,
            'تسجيل الخروج',
            'الخروج من الحساب',
            onTap: () => _showLogoutDialog(context),
          ),
          _buildSettingItem(
            Icons.delete,
            'حذف الحساب',
            'غير قابل للاسترجاع',
            onTap: () => _confirmDeleteAccount(context),
          ),
          _buildSettingItem(
            Icons.info,
            'عن التطبيق',
            'الإصدار 1.0.0',
            onTap: () => _showAboutApp(context),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingItem(
    IconData icon,
    String title,
    String subtitle, {
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: Colors.white),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      subtitle: Text(subtitle, style: const TextStyle(color: Colors.grey)),
      trailing: const Icon(Icons.chevron_left, color: Colors.grey),
      onTap: onTap,
    );
  }

  void _showLanguageDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('اختر اللغة', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text(
                'العربية',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                // تغيير اللغة إلى العربية
              },
            ),
            ListTile(
              title: const Text(
                'English',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                // تغيير اللغة إلى الإنجليزية
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showPrivacyPolicy(BuildContext context) {
    // فتح سياسة الخصوصية في المتصفح
    launchUrl(
      Uri.parse('https://revo-shorts.dramaxbox.bbs.tr/privacy-policy.php'),
      mode: LaunchMode.externalApplication,
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'تسجيل الخروج',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'هل أنت متأكد من رغبتك في تسجيل الخروج؟',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء', style: TextStyle(color: Colors.white)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              onLogout();
              Navigator.pop(context); // العودة إلى الشاشة السابقة
            },
            child: const Text(
              'تسجيل الخروج',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteAccount(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    String? userId = prefs.getString('user_id');

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف الحساب'),
        content: const Text('هل أنت متأكد من حذف حسابك؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () async {
              // نغلق الـ Dialog فقط
              Navigator.pop(dialogContext);

              final result = await ApiService().deleteUser(int.parse(userId!));

              if (result['status'] == 'success') {
                await prefs.clear();

                // نعرض رسالة نجاح
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم حذف الحساب بنجاح')),
                  );
                }

                // نرجع لصفحة تسجيل الدخول ونمسح كل الصفحات السابقة
                Future.delayed(const Duration(milliseconds: 500), () {
                  Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const LoginPage()),
                    (route) => false,
                  );
                });
              } else {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('حدث خطأ: ${result['message']}')),
                  );
                }
              }
            },
            child: const Text('حذف', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showAboutApp(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('عن التطبيق', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Revo Shorts - تطبيق لمشاهدة أحدث المسلسلات والأفلام العربية والعالمية. إصدار 1.0.0',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('موافق', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

// رسام التموجات للخلفية المتحركة
class WavePainter extends CustomPainter {
  final double value;

  WavePainter(this.value);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.pink.withOpacity(0.15),
          Colors.purple.withOpacity(0.1),
          Colors.blue.withOpacity(0.05),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    final path = Path();
    final waveHeight = 20.0;
    final baseHeight = size.height * 0.7;

    path.moveTo(0, baseHeight);

    for (double i = 0; i <= size.width; i++) {
      final y = baseHeight + sin(value + i * 0.02) * waveHeight;
      path.lineTo(i, y);
    }

    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}