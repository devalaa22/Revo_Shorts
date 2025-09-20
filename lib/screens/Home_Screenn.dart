// main_navigation_screen.dart
import 'dart:convert';
import 'package:dramix/l10n/app_localizations.dart';
import 'package:dramix/main.dart';
import 'package:dramix/models/UserModel.dart';
import 'package:dramix/screens/DailyrewardsScreen.dart';
import 'package:dramix/screens/MyListScreen.dart';
import 'package:dramix/services/api_service.dart';
import 'package:dramix/services/auth_service.dart';
import 'package:dramix/utils/app_config.dart';
import 'package:flutter/material.dart';
import '../utils/PermissionService.dart';
import 'home_screen.dart';
import 'recommendations_screen.dart';
import 'profile_screen.dart';
import 'login_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  _MainNavigationScreenState createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  final AuthService _authService = AuthService();
  int _currentIndex = 0;
  bool _isLoggedIn = false;

  User? _currentUser;
  int _userCoins = 0;
  int _watchlistCount = 0;

  List<Widget> _screens = [];

  final List<String> _normalIcons = [
    'assets/icons/ic_store_normal.png',
    'assets/icons/ic_foru_normal.png',
    'assets/icons/ic_gift_select.png',
    'assets/images/icon_item_video_collect_40.png',
    'assets/icons/ic_mine_normal.png',
  ];

  final List<String> _selectedIcons = [
    'assets/icons/ic_store_select.png',
    'assets/icons/ic_foru_select.png',
    'assets/icons/ic_gift_select.png',
    'assets/images/icon_item_video_collect_none_40.png',
    'assets/icons/ic_mine_select.png',
  ];

  late List<String> _labels;

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
    _requestPermissions();
    _loadInitialData();
    _startCoinEmission();
    _loadWatchlistCount();
    
    checkPackageName();
    AppConfig.loadAppMode().then((_) {
      _initializeScreens();
    });
  }

  void _initializeScreens() {
    if (_currentUser != null) {
      setState(() {
        _screens = [
          const HomeScreen(),
          const RecommendationsScreen(key: PageStorageKey('recommendations')),
          if (!AppConfig.isFreeMode)
            DailyRewardsScreen(
              userId: int.parse(_currentUser!.id),
              userEmail: _currentUser!.email,
              currentCoins: _currentUser!.coins,
            )
          else
            Container(), // شاشة فارغة في الوضع المجاني
          const MyListScreen(),
          const ProfileScreen(),
        ];
      });
    } else {
      setState(() {
        _screens = [
          const HomeScreen(),
          const RecommendationsScreen(key: PageStorageKey('recommendations')),
          if (!AppConfig.isFreeMode)
            const Center(child: Text('يجب تسجيل الدخول أولاً'))
          else
            Container(), // شاشة فارغة في الوضع المجاني
          const MyListScreen(),
          const ProfileScreen(),
        ];
      });
    }
  }

  Future<void> _loadWatchlistCount() async {
    final prefs = await SharedPreferences.getInstance();
    final watchHistory = prefs.getString('user_watch_history');

    if (watchHistory != null) {
      try {
        final List<dynamic> historyList = json.decode(watchHistory);
        setState(() {
          _watchlistCount = historyList.length;
        });
      } catch (e) {
        setState(() {
          _watchlistCount = 0;
        });
      }
    }
  }

  void _startCoinEmission() {
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() {});
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            setState(() {});
            _startCoinEmission();
          }
        });
      }
    });
  }

  Future<void> _loadInitialData() async {
    await _loadUserData();
    await _loadUserCoins();
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
        _userCoins = _currentUser!.coins;
      });
      _initializeScreens();
    }
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

  Future<void> _checkLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
    if (!isLoggedIn) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
    } else {
      setState(() {
        _isLoggedIn = true;
      });
    }
  }

  void _requestPermissions() async {
    final permissionService = PermissionService();
    await permissionService.requestLocationPermission();
    await permissionService.requestStoragePermission();
    await permissionService.requestNotificationPermission();
    await permissionService.requestMediaPermission();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final localizations = AppLocalizations.of(context)!;
    _labels = [
      localizations.home,
      localizations.discover,
      'المكافآت',
      'قائمتي',
      localizations.profile,
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoggedIn) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_screens.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.only(top: 8),
          height: 65,
          decoration: const BoxDecoration(color: Color.fromARGB(255, 0, 0, 0)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(
              AppConfig.isFreeMode ? 4 : 5, // عدد الأيقونات المعروضة
              (index) {
                // تحديد الفهرس الحقيقي بناءً على وضع التطبيق
                int realIndex = index;
                if (AppConfig.isFreeMode && index >= 2) {
                  realIndex = index + 1; // نتخطى الفهرس 2 (المكافآت) في الوضع المجاني
                }

                final isSelected = _currentIndex == realIndex;
                
                // تحديد أيقونة الفهرس الصحيحة
                int iconIndex = realIndex;
                if (AppConfig.isFreeMode && index >= 2) {
                  iconIndex = index + 1; // نتخطى الفهرس 2 (المكافآت) في الوضع المجاني
                }

                return InkWell(
                  onTap: () {
                    setState(() => _currentIndex = realIndex);
                    
                    if (realIndex == 3) { // قائمتي
                      _loadWatchlistCount();
                    }
                    
                    if (realIndex == 2 && !AppConfig.isFreeMode) { // المكافآت
                      _loadUserCoins();
                    }
                  },
                  splashColor: Colors.transparent,
                  highlightColor: Colors.transparent,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Stack(
                          children: [
                            Image.asset(
                              isSelected
                                  ? _selectedIcons[iconIndex]
                                  : _normalIcons[iconIndex],
                              width: 30,
                              height: 30,
                              color: isSelected ? null : Colors.grey[500],
                            ),
                            if (realIndex == 3 && _watchlistCount > 0) // قائمتي
                              Positioned(
                                right: 0,
                                top: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    color: Colors.blue,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  constraints: const BoxConstraints(
                                    minWidth: 14,
                                    minHeight: 14,
                                  ),
                                  child: Text(
                                    _watchlistCount > 99 ? '99+' : _watchlistCount.toString(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                            if (realIndex == 2 && _userCoins > 0 && !AppConfig.isFreeMode) // المكافآت
                              Positioned(
                                right: 0,
                                top: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    color: Colors.red,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  constraints: const BoxConstraints(
                                    minWidth: 14,
                                    minHeight: 14,
                                  ),
                                  child: Text(
                                    _userCoins.toString(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _labels[realIndex],
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                          color: isSelected ? Colors.white : Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}