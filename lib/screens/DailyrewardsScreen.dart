import 'dart:async';
import 'dart:convert';
import 'package:dramix/services/ApiEndpoints.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dramix/services/api_service.dart';
import '../services/auth_service.dart';

class DailyRewardsScreen extends StatefulWidget {
  final int userId;
  final String userEmail;
  final int currentCoins;
  final Function(int)? onCoinsUpdated;

  const DailyRewardsScreen({
    super.key,
    required this.userId,
    required this.userEmail,
    required this.currentCoins,
    this.onCoinsUpdated,
  });

  @override
  _DailyRewardsScreenState createState() => _DailyRewardsScreenState();
}

class _DailyRewardsScreenState extends State<DailyRewardsScreen> {
  List<dynamic> packages = [];
  bool isLoading = true;
  int _userCoins = 0;
  RewardedAd? _rewardedAd;
  bool _isAdLoaded = false;
  String? _rewardedAdUnitId;
  int _selectedPackageIndex = -1;
  Map<int, int> _completedAds = {};
  Map<int, DateTime> _completionTimes = {};
  final Map<int, Timer> _timers = {};
  final Map<int, Duration> _remainingTimes = {};
  late SharedPreferences _prefs;
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
   /// FlutterWindowManager.addFlags(FlutterWindowManager.FLAG_SECURE);
    _initSharedPreferences().then((_) {
      _initLoad();
      _fetchRewardedAdUnitId("rewarded1");
      _loadRewardedAd();
    });
  }

  Future<void> _initSharedPreferences() async {
    _prefs = await SharedPreferences.getInstance();
    _loadSavedData();
  }

  void _loadSavedData() {
    final completedAdsJson = _prefs.getString('completed_ads');
    if (completedAdsJson != null) {
      _completedAds = Map<int, int>.from(
        json.decode(completedAdsJson).map((k, v) => MapEntry(int.parse(k), v)),
      );
    }

    final completionTimesJson = _prefs.getString('completion_times');
    if (completionTimesJson != null) {
      final Map<String, dynamic> timesMap = json.decode(completionTimesJson);
      _completionTimes = timesMap.map(
        (key, value) => MapEntry(int.parse(key), DateTime.parse(value)),
      );

      // بدء التايمرات للباقات المقفلة
      _completionTimes.forEach((packageId, completionTime) {
        final now = DateTime.now();
        final resetTime = completionTime.add(Duration(hours: 24));
        if (now.isBefore(resetTime)) {
          _remainingTimes[packageId] = resetTime.difference(now);
          _startTimer(packageId);
        } else {
          // إذا انتهى الوقت، إزالة الباقة من القفل
          _completionTimes.remove(packageId);
          _completedAds.remove(packageId);
          _remainingTimes.remove(packageId);
        }
      });
    }

    _userCoins = _prefs.getInt('user_coins') ?? widget.currentCoins;
  }

  Future<void> _saveData() async {
    await _prefs.setString('completed_ads', json.encode(_completedAds));
    await _prefs.setString(
      'completion_times',
      json.encode(
        _completionTimes.map(
          (k, v) => MapEntry(k.toString(), v.toIso8601String()),
        ),
      ),
    );
    await _prefs.setInt('user_coins', _userCoins);
  }

  @override
  void dispose() {
    _timers.forEach((_, timer) => timer.cancel());
    _rewardedAd?.dispose();
    super.dispose();
  }

  void _startTimer(int packageId) {
    _timers[packageId]?.cancel();

    final completionTime = _completionTimes[packageId]!;
    final resetTime = completionTime.add(Duration(hours: 24));
    final remaining = resetTime.difference(DateTime.now());

    _remainingTimes[packageId] = remaining;

    _timers[packageId] = Timer.periodic(Duration(seconds: 1), (timer) {
      if (_remainingTimes[packageId]!.inSeconds <= 0) {
        timer.cancel();

        // إعادة تحميل البيانات من السيرفر بعد انتهاء المهلة
        _fetchPackages().then((_) {
          setState(() {
            _remainingTimes.remove(packageId);
            _completionTimes.remove(packageId);
            _completedAds.remove(packageId);
          });

          // ✅ إعادة حفظ البيانات بعد انتهاء المهلة
          _saveData();
        });

        return;
      }

      setState(() {
        _remainingTimes[packageId] = Duration(
          seconds: _remainingTimes[packageId]!.inSeconds - 1,
        );
      });
    });
  }

  Future<void> _fetchRewardedAdUnitId(String keyName) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiEndpoints.getAdMob}?key=$keyName'),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _rewardedAdUnitId = data['ad_unit_id'].toString();
          _loadRewardedAd();
        });
      }
    } catch (e) {
      debugPrint('Error fetching ad unit ID: $e');
    }
  }

  void _loadRewardedAd() {
    if (_rewardedAdUnitId == null) return;

    RewardedAd.load(
      adUnitId: _rewardedAdUnitId!,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (RewardedAd ad) {
          setState(() {
            _rewardedAd = ad;
            _isAdLoaded = true;
          });
        },
        onAdFailedToLoad: (LoadAdError error) {
          setState(() => _isAdLoaded = false);
          _loadRewardedAd();
        },
      ),
    );
  }

  void _showRewardedAd(int packageIndex) async {
    if (!_isAdLoaded || _rewardedAd == null) {
      _showErrorMessage('الإعلان غير جاهز حالياً، يرجى المحاولة لاحقاً');
      return;
    }

    final package = packages[packageIndex];
    final packageId = package['id'];

    // التحقق إذا كانت الباقة مقفلة
    if (_completionTimes.containsKey(packageId)) {
      _showErrorMessage('المهمة مقفلة لمدة 24 ساعة بعد الإكمال');
      return;
    }

    setState(() => _selectedPackageIndex = packageIndex);

    bool adCompleted = false;

    _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _loadRewardedAd();

        if (!adCompleted) {
          setState(() {
            _isUpdating = false;
            _selectedPackageIndex = -1;
          });
          _showErrorMessage('لم تكمل مشاهدة الإعلان');
        }
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _loadRewardedAd();
        setState(() {
          _isUpdating = false;
          _selectedPackageIndex = -1;
        });
        _showErrorMessage('فشل عرض الإعلان');
      },
    );

    _rewardedAd!.show(
      onUserEarnedReward: (ad, reward) {
        adCompleted = true;
        _grantCoinsAfterAd(packageIndex);
      },
    );
  }

  Future<void> _grantCoinsAfterAd(int packageIndex) async {
    final package = packages[packageIndex];
    final packageId = package['id'];
    final coinAmount = safeParse(package['coin_amount']);
    final requiredAds = safeParse(package['required_ads']);
    final coinsPerAd = coinAmount ~/ requiredAds;

    setState(() => _isUpdating = true);

    try {
      final response = await http.post(
        Uri.parse(ApiEndpoints.updateDailyGift),
        body: json.encode({
          'user_id': widget.userId,
          'gift_id': packageId,
          'coins': coinsPerAd, // إرسال النقاط لكل إعلان
        }),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          setState(() {
            _completedAds[packageId] = data['completed_ads'];
            _userCoins = data['new_balance'];
          });

          if (data['is_completed']) {
            final serverTime = DateTime.parse(data['server_time']).toUtc();
            _completionTimes[packageId] = serverTime;
            _startTimer(packageId);

            _showSuccessMessage(
              '🎉 مبروك! أكملت المهمة وحصلت على $coinAmount نقطة',
            );
          } else {
            _showSuccessMessage('+$coinsPerAd نقطة! تابع للإكمال 🚀');
          }

          await _saveData();
          widget.onCoinsUpdated?.call(_userCoins);
        } else {
          throw Exception(data['message']);
        }
      }
    } finally {
      setState(() {
        _isUpdating = false;
        _selectedPackageIndex = -1;
      });
    }
  }

  Future<void> _initLoad() async {
    await Future.wait([_loadUserCoins(), _fetchPackages()]);
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

  Future<void> _fetchPackages() async {
    try {
      final res = await http.get(
        Uri.parse('${ApiEndpoints.getDailyGifts}?user_id=${widget.userId}'),
      );

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (data['success'] == true && mounted) {
          setState(() {
            packages = data['data'];

            for (var package in packages) {
              final packageId = package['id'];
              final serverCompleted = safeParse(package['user_completed']);
              final serverCompletionTime = package['completion_time'] != null
                  ? DateTime.parse(package['completion_time']).toUtc()
                  : null;

              if (serverCompletionTime != null) {
                final now = DateTime.now().toUtc();
                final resetTime = serverCompletionTime.add(Duration(hours: 24));

                if (now.isBefore(resetTime)) {
                  // المهمة لا تزال مقفلة
                  _completionTimes[packageId] = serverCompletionTime;
                  _completedAds[packageId] = serverCompleted;
                  _remainingTimes[packageId] = resetTime.difference(now);
                  _startTimer(packageId);
                } else {
                  // انتهت المهلة، السيرفر سيعيد التعيين تلقائياً
                  _completionTimes.remove(packageId);
                  _remainingTimes.remove(packageId);
                  _completedAds.remove(packageId);
                }
              } else {
                // لا يوجد وقت إكمال، المهمة غير مكتملة أو تمت إعادتها
                _completionTimes.remove(packageId);
                _remainingTimes.remove(packageId);
                _completedAds[packageId] = serverCompleted;
              }
            }

            isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching packages: $e');
      setState(() => isLoading = false);
    }
  }

  int safeParse(dynamic value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  String _getRemainingTime(int packageId) {
    if (_remainingTimes.containsKey(packageId)) {
      final remaining = _remainingTimes[packageId]!;
      final hours = remaining.inHours;
      final minutes = remaining.inMinutes.remainder(60);
      final seconds = remaining.inSeconds.remainder(60);

      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '';
  }

  void _showSuccessMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        margin: EdgeInsets.all(20),
      ),
    );
  }

  void _showErrorMessage(String error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error, style: TextStyle(fontSize: 16)),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        margin: EdgeInsets.all(20),
      ),
    );
  }

  Widget _buildProgressIndicator(int completed, int total, bool isCompleted) {
    return Column(
      children: [
        LinearProgressIndicator(
          value: total > 0 ? (completed / total).clamp(0.0, 1.0) : 0.0,
          backgroundColor: Colors.grey[800],
          color: isCompleted ? Colors.green : Colors.amber,
          minHeight: 8,
          borderRadius: BorderRadius.circular(10),
        ),
        SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '$completed / $total',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            Text(
              '${(completed / total * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                color: isCompleted ? Colors.green : Colors.amber,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF0A0A0A),
      body: isLoading
          ? Center(
              child: CircularProgressIndicator(
                color: Color.fromARGB(255, 0, 0, 0),
              ),
            )
          : Column(
              children: [
                // Header with coins
                Container(
                  padding: const EdgeInsets.only(
                    top: 60,
                    left: 20,
                    right: 20,
                    bottom: 20,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color.fromARGB(255, 0, 0, 0),
                        Color.fromARGB(255, 17, 17, 17),
                      ],
                    ),
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(20),
                      bottomRight: Radius.circular(20),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'المكافآت اليومية',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'احصل على نقاط مجانية كل يوم',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.monetization_on,
                              color: Colors.amber,
                              size: 20,
                            ),
                            SizedBox(width: 8),
                            Text(
                              '$_userCoins',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: ListView(
                    padding: EdgeInsets.all(16),
                    children: [
                      Text(
                        'مهام اليوم',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 16),
                      ...packages.map((package) {
                        final packageId = package['id'];
                        final requiredAds = safeParse(package['required_ads']);
                        final completedAds = _completedAds[packageId] ?? 0;
                        final isCompleted = completedAds >= requiredAds;
                        final isLocked = _completionTimes.containsKey(
                          packageId,
                        );
                        final coinsPerAd =
                            safeParse(package['coin_amount']) ~/ requiredAds;
                        final totalCoins = safeParse(package['coin_amount']);

                        return Container(
                          margin: EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: Color(0xFF1A1A1A),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.3),
                                blurRadius: 10,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Stack(
                            children: [
                              // Premium badge
                              if (safeParse(package['is_popular']) == 1)
                                Positioned(
                                  top: 16,
                                  right: 16,
                                  child: Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [Colors.amber, Colors.orange],
                                      ),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      'مميز',
                                      style: TextStyle(
                                        color: Colors.black,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),

                              Padding(
                                padding: EdgeInsets.all(20),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          width: 50,
                                          height: 50,
                                          decoration: BoxDecoration(
                                            color: Colors.amber.withOpacity(
                                              0.2,
                                            ),
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: Colors.amber,
                                              width: 2,
                                            ),
                                          ),
                                          child: Center(
                                            child: Text(
                                              '${package['coin_amount']}',
                                              style: TextStyle(
                                                color: Colors.amber,
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ),
                                        SizedBox(width: 16),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'مهمة ${package['name'] ?? 'اليوم'}',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              SizedBox(height: 4),
                                              Text(
                                                'شاهد $requiredAds إعلاناً لتحصل على $totalCoins نقطة',
                                                style: TextStyle(
                                                  color: Colors.white70,
                                                  fontSize: 14,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),

                                    SizedBox(height: 16),
                                    _buildProgressIndicator(
                                      completedAds,
                                      requiredAds,
                                      isCompleted,
                                    ),

                                    SizedBox(height: 16),
                                    if (isLocked)
                                      Container(
                                        padding: EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          border: Border.all(
                                            color: Colors.orange,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.lock_clock,
                                              color: Colors.orange,
                                              size: 20,
                                            ),
                                            SizedBox(width: 8),
                                            Text(
                                              'ستتجدد بعد: ${_getRemainingTime(packageId)}',
                                              style: TextStyle(
                                                color: Colors.orange,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    else
                                      ElevatedButton(
                                        onPressed:
                                            _isUpdating ||
                                                _selectedPackageIndex != -1
                                            ? null
                                            : () => _showRewardedAd(
                                                packages.indexOf(package),
                                              ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: isCompleted
                                              ? Colors.green
                                              : Color.fromARGB(255, 0, 0, 0),
                                          foregroundColor: Colors.white,
                                          minimumSize: Size(
                                            double.infinity,
                                            50,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          elevation: 5,
                                        ),
                                        child:
                                            _isUpdating &&
                                                _selectedPackageIndex ==
                                                    packages.indexOf(package)
                                            ? CircularProgressIndicator(
                                                color: Colors.white,
                                              )
                                            : Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  Icon(
                                                    isCompleted
                                                        ? Icons.check_circle
                                                        : Icons
                                                              .play_circle_fill,
                                                    size: 20,
                                                  ),
                                                  SizedBox(width: 8),
                                                  Text(
                                                    isCompleted
                                                        ? 'مكتمل'
                                                        : 'شاهد الإعلان (+$coinsPerAd)',
                                                    style: TextStyle(
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
