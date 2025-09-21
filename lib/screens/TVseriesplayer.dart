import 'dart:async';
import 'dart:convert';
import 'package:dramix/screens/LoginPage2.dart';
import 'package:dramix/screens/in_app_purchase.dart';
import 'package:dramix/services/ApiEndpoints.dart';
import 'package:dramix/services/auth_service.dart';
import 'package:dramix/services/api_service.dart';
import 'package:dramix/screens/VipPackagesScreen.dart';
import 'package:dramix/utils/app_config.dart';
import 'package:dramix/utils/helpers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:http/http.dart' as http;
import 'package:lottie/lottie.dart';
import 'package:video_player/video_player.dart';
import '../services/video_preloader.dart';
import '../models/WatchHistoryService.dart';
import '../models/WatchedSeries.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/app_localizations.dart';
import '../models/episode.dart';
import '../models/UserModel.dart';
// ...existing import kept above

///import 'package:flutter_windowmanager/flutter_windowmanager.dart';

class TVseriesplayer extends StatefulWidget {
  final List<Episode> episodes;
  final int initialIndex;
  // series metadata (used for watch history / resume)
  final int seriesId;
  final String? seriesTitle;
  final String? seriesImageUrl;
  final Function(int)? onEpisodeChanged;
  final Function(int)? onEpisodeWatched;

  final int freeEpisodesCount = 3;
  final int maxDailyAds = 5; // 5 إعلانات يومياً
  final int episodesPerAd = 2; // كل إعلان يفتح حلقتين
  // هذا المتغير الجديد
  const TVseriesplayer({
    super.key,
    required this.episodes,
    required this.initialIndex,
    required this.seriesId,
    this.seriesTitle,
    this.seriesImageUrl,
    this.onEpisodeChanged,
    this.onEpisodeWatched,
  });

  @override
  State<TVseriesplayer> createState() => _TVseriesplayerState();
}

class _TVseriesplayerState extends State<TVseriesplayer>
    with TickerProviderStateMixin {
  late PageController _pageController;
  String _currentSeriesId = '';
  late int currentIndex;
  VideoPlayerController? _controller;
  bool _showPlayIcon = true;
  double _playbackSpeed = 1.0;
  late Episode currentEpisode;
  bool _isLoadingNextEpisode = false;
  bool _showControls = true;
  late DateTime _controlsHideTime;
  bool isPlaying = false;
  RewardedAd? _rewardedAd;
  late AnimationController _likeAnimationController;
  Map<int, DateTime> _unlockedEpisodes = {};
  int _adsWatchedToday = 0;
  bool _isAdShowing = false;
  bool _shouldBlockNavigation = false;
  bool _isEpisodeLockedDialogShown = false;
  bool _isLiked = false;
  int _likeCount = 0;
  bool _isLikeLoading = false;
  int _viewCount = 0;
  Timer? _hideControlsTimer;
  Timer? _progressTimer;
  final Map<int, VideoPlayerController> _preloadedControllers = {};
  late final VideoPreloader _videoPreloader;
  final WatchHistoryService _watchHistoryService = WatchHistoryService();
  Timer? _autosaveTimer;
  int _userCoins = 0;
  bool _isSwiping = false;
  bool _showUnlockToast = false;
  Timer? _toastTimer;
  User? _currentUser;
  final bool _isSeeking = false;
  bool _showLoadingIndicator = false;
  // ignore: unused_field
  final double _seekPosition = 0.0;

  bool _isDragging = false;
  double _dragPosition = 0.0;
  // token to guard async controller initialization against rapid swaps
  int _controllerInitToken = 0;
  String? _rewardedAdUnitId;
  final List<String> _rewardedAdUnitIds = [];
  int _currentAdUnitIndex = 0;
  final int _episodesPerAdUnit = 5; // عدد الحلقات لكل شفرة إعلانية
  int _episodeCounter = 0;
  @override
  void initState() {
    super.initState();
    currentIndex = widget.initialIndex;
    //FlutterWindowManager.addFlags(FlutterWindowManager.FLAG_SECURE);
    currentEpisode = widget.episodes[currentIndex];
    _pageController = PageController(initialPage: currentIndex);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // moved ad loading to after app config is loaded
    });
    _loadInitialData().then((_) async {
      // load app config (including free_mode_ads) and wait for it to be available
      await AppConfig.loadAppConfig();

      // Load ad units and rewarded ads only if server config allows ads in free mode
      if (!(AppConfig.isFreeMode && !AppConfig.freeModeAdsEnabled)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _loadAllRewardedAdUnits();
        });
        _loadRewardedAd();
        _fetchRewardedAdUnitId("rewarded3");
      }
      _initializeVideoController();
      _loadEpisodeStats();
      _preloadAdjacentVideos();
      _loadAdWatchData();

      _loadUnlockedEpisodes();
    });

    _videoPreloader = VideoPreloader();

    // start periodic autosave to persist resume position
    _autosaveTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _persistWatchProgress();
    });

    _controlsHideTime = DateTime.now();
    _likeAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    // These calls were moved to run after app config load above
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        systemNavigationBarColor: Colors.black,
        systemNavigationBarIconBrightness: Brightness.light,
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );

    currentIndex = widget.initialIndex;
    currentEpisode = widget.episodes[currentIndex];
    _currentSeriesId = currentEpisode.id.toString();
  }

  Future<void> _persistWatchProgress() async {
    try {
      if (_controller == null || !_controller!.value.isInitialized) return;
      final position = _controller!.value.position;
      final progress = _controller!.value.duration.inMilliseconds > 0
          ? position.inMilliseconds / _controller!.value.duration.inMilliseconds
          : 0.0;

      final watched = WatchedSeries(
        seriesId: widget.seriesId,
        title: widget.seriesTitle ?? '',
        imageUrl: widget.seriesImageUrl ?? '',
        thumbnailUrl: '',
        lastWatchedEpisode: currentEpisode.episodeNumber,
        totalEpisodes: widget.episodes.length,
        lastWatchedAt: DateTime.now(),
        progress: progress.clamp(0.0, 1.0),
        lastPosition: position,
      );

      await _watchHistoryService.saveWatchedSeries(watched);
    } catch (e) {
      debugPrint('Persist watch progress failed: $e');
    }
  }

  // أضف هذه الدوال الجديدة
  Future<void> _loadAllRewardedAdUnits() async {
    try {
      // قائمة المفاتيح للشفرات الست
      final List<String> adKeys = [
        'rewarded1',
        'rewarded2',
        'rewarded3',
        'rewarded4',
        'rewarded5',
        'rewarded6',
      ];

      // جلب جميع الشفرات
      for (final key in adKeys) {
        final response = await http.get(
          Uri.parse('${ApiEndpoints.getAdMob}?key=$key'),
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final adUnitId = data['ad_unit_id']?.toString();

          if (adUnitId != null && adUnitId.isNotEmpty) {
            _rewardedAdUnitIds.add(adUnitId);
          }
        }
      }

      if (_rewardedAdUnitIds.isNotEmpty && mounted) {
        setState(() {
          _rewardedAdUnitId = _rewardedAdUnitIds.first;
        });

        // Only start loading rewarded ads if ads are allowed by server
        if (!(AppConfig.isFreeMode && !AppConfig.freeModeAdsEnabled)) {
          _loadRewardedAd();
        }

        debugPrint('تم تحميل ${_rewardedAdUnitIds.length} شفرات إعلانية');
      }
    } catch (e) {
      debugPrint('Error loading ad units: $e');
    }
  }

  void _rotateAdUnit() {
    if (_rewardedAdUnitIds.isEmpty || _rewardedAdUnitIds.length <= 1) return;

    _episodeCounter++;

    // إذا وصلنا لعدد الحلقات المحدد لكل شفرة، ننتقل للشفرة التالية
    if (_episodeCounter >= _episodesPerAdUnit) {
      _episodeCounter = 0;
      _currentAdUnitIndex =
          (_currentAdUnitIndex + 1) % _rewardedAdUnitIds.length;
      _rewardedAdUnitId = _rewardedAdUnitIds[_currentAdUnitIndex];
    }

    _loadRewardedAd();
  }

  // عدل دالة _loadRewardedAd لتستخدم النظام الجديد
  void _loadRewardedAd() {
    // If free mode with ads disabled by server, do not attempt to load ads
    if (AppConfig.isFreeMode && !AppConfig.freeModeAdsEnabled) return;

    if (_rewardedAdUnitId == null || _rewardedAdUnitId!.isEmpty) {
      // إذا لم توجد شفرات، جرب شفرة افتراضية (rewarded3) كاحتياطي
      if (_rewardedAdUnitIds.isEmpty) {
        _fetchRewardedAdUnitId("rewarded3");
      }
      return;
    }

    RewardedAd.load(
      adUnitId: _rewardedAdUnitId!,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (RewardedAd ad) {
          setState(() {
            _rewardedAd = ad;
          });
        },
        onAdFailedToLoad: (LoadAdError error) {
          debugPrint('Failed to load ad: ${error.message}');

          // إذا فشل تحميل الإعلان، جرب الشفرة التالية
          if (_rewardedAdUnitIds.length > 1) {
            _currentAdUnitIndex =
                (_currentAdUnitIndex + 1) % _rewardedAdUnitIds.length;
            _rewardedAdUnitId = _rewardedAdUnitIds[_currentAdUnitIndex];
            _loadRewardedAd();
          } else if (_rewardedAdUnitIds.isEmpty) {
            // إذا لم توجد شفرات، جرب شفرة افتراضية
            _fetchRewardedAdUnitId("rewarded3");
          }
        },
      ),
    );
  }

  Future<void> _fetchRewardedAdUnitId(String keyName) async {
    // If free mode with ads disabled by server, do not fetch ad unit ids
    if (AppConfig.isFreeMode && !AppConfig.freeModeAdsEnabled) return;

    try {
      final response = await http.get(
        Uri.parse('${ApiEndpoints.getAdMob}?key=$keyName'),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _rewardedAdUnitId = data['ad_unit_id'].toString();
        });

        // Only try to load ad if server allows ads
        if (!(AppConfig.isFreeMode && !AppConfig.freeModeAdsEnabled)) {
          _loadRewardedAd();
        }
      }
    } catch (e) {
      debugPrint('Error fetching ad unit ID: $e');
    }
  }

  Future<void> _loadInitialData() async {
    await _loadUserData();
    await _loadUserCoins();
    await _checkVipStatus();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final isLoggedIn = prefs.getBool('isLoggedIn') ?? false;

    if (isLoggedIn) {
      final user = await AuthService().getCurrentUser();
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

  Future<void> _loadUserCoins() async {
    try {
      if (!mounted) return;

      final isSignedIn = await AuthService().isSignedIn();
      if (!isSignedIn) return;

      final response = await ApiService().getUserCoins();
      if (response['status'] == 'success' && mounted) {
        setState(() {
          _userCoins = response['coins'] ?? 0;
        });
      }
    } catch (e) {
      debugPrint('Error loading coins: $e');
    }
  }

  Future<void> _preloadAdjacentVideos() async {
    // Keep a small window of preloaded controllers: previous, next 1-3
    final preloadRange = [
      currentIndex - 1,
      currentIndex + 1,
      currentIndex + 2,
      currentIndex + 3,
    ];

    for (final index in preloadRange) {
      if (index >= 0 &&
          index < widget.episodes.length &&
          !_preloadedControllers.containsKey(index)) {
        final episode = widget.episodes[index];
        try {
          debugPrint(
            'TVseriesplayer: preload start index=$index url=${episode.videoUrl}',
          );
          final controller = await _videoPreloader.createController(
            episode.videoUrl,
          );
          debugPrint(
            'TVseriesplayer: preload created controller for index=$index',
          );
          _preloadedControllers[index] = controller;
          // controller already initialized by preloader (best-effort). keep default looping=false
          controller.setLooping(false);
        } catch (e) {
          // ignore preload failures but log for diagnostics
          debugPrint('TVseriesplayer: Preload failed for index $index: $e');
        }
      }
    }

    // Dispose controllers that are far from the current index to save memory
    _disposeFarControllers();
  }

  void _disposeFarControllers() {
    final keys = _preloadedControllers.keys.toList();
    for (final k in keys) {
      if (k < currentIndex - 2 || k > currentIndex + 4) {
        try {
          final c = _preloadedControllers.remove(k);
          if (c != null) {
            c.removeListener(_videoListener);
            c.dispose();
          }
        } catch (e) {
          debugPrint('Error disposing controller $k: $e');
        }
      }
    }
  }

  void _startProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
      if (_controller != null &&
          _controller!.value.isInitialized &&
          mounted &&
          !_isSeeking) {
        setState(() {});
      }
    });
  }

  Future<void> _loadEpisodeStats() async {
    try {
      final stats = await ApiService().getEpisodeStats(currentEpisode.id);
      if (stats['status'] == 'success' && mounted) {
        setState(() {
          _likeCount = stats['likes_count'] ?? 0;
          _isLiked = stats['is_liked'] ?? false;
          _viewCount = stats['views_count'] ?? 0;
          currentEpisode.likeCount = _likeCount;
          currentEpisode.isLiked = _isLiked;
          currentEpisode.viewCount = _viewCount;
        });
      }
    } catch (e) {
      debugPrint('Error loading episode stats: $e');
    }
  }

  Future<void> _sendViewToServer() async {
    try {
      final response = await ApiService().recordView(currentEpisode.id);
      if (mounted && response['status'] == 'success') {
        setState(() {
          _viewCount = response['views_count'] ?? _viewCount;
          currentEpisode.viewCount = _viewCount;
        });
      }
    } catch (e) {
      debugPrint('Failed to send view: $e');
    }
  }

  Future<void> _toggleLike() async {
    if (_isLikeLoading) return;

    final isSignedIn = await AuthService().isSignedIn();
    if (!isSignedIn) {
      await _showLoginRequiredDialog();
      return;
    }

    setState(() => _isLikeLoading = true);

    try {
      final response = await ApiService().toggleLike(
        currentEpisode.id,
        !_isLiked,
      );

      // Normalize possible shapes: our ApiService returns {'status': 'success' ...} or {'status':'error','message':...}
      final status = response['status']?.toString().toLowerCase();

      if (status == 'success' && mounted) {
        setState(() {
          _isLiked = !_isLiked;
          _likeCount = response['likes_count'] ?? _likeCount;
          currentEpisode.likeCount = _likeCount;
          currentEpisode.isLiked = _isLiked;
        });
        _likeAnimationController.forward(from: 0);
      } else {
        // Not success - present friendly message and log details for debugging
        final msg =
            response['message']?.toString() ??
            'فشل تحديث الاعجاب. حاول مرة أخرى.';
        debugPrint('toggleLike failed response: $response');
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(msg)));
        }
      }
    } catch (e) {
      debugPrint('Exception in _toggleLike: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'حدث خطأ أثناء تحديث الإعجاب. تأكد من اتصال الإنترنت.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLikeLoading = false);
      }
    }
  }

  Future<void> _showLoginRequiredDialog({
    String? message,
    String? actionText,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Login required'),
        content: Text(message ?? 'You must be logged in to like the content.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Later'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(actionText ?? 'Log in'),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      final loginSuccess = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (context) => const LoginPage2()),
      );

      if (loginSuccess == true && mounted) {
        if (message?.contains('coin') ?? false) {
          await _loadUserCoins();
        } else {
          await _toggleLike();
        }
      }
    }
  }

  Future<void> _initializeVideoController() async {
    // Increment token to mark a fresh init attempt. Any earlier async init should ignore its result.
    final int initToken = ++_controllerInitToken;

    if (_controller != null) {
      _controller!.removeListener(_videoListener);
      try {
        await _controller!.dispose();
      } catch (_) {}
    }

    setState(() {
      _showLoadingIndicator = true;
    });

    if (_preloadedControllers.containsKey(currentIndex)) {
      debugPrint(
        'TVseriesplayer: using preloaded controller for currentIndex=$currentIndex',
      );
      _controller = _preloadedControllers[currentIndex];
      _preloadedControllers.remove(currentIndex);
    } else {
      // create controller using preloader (will return file-based controller if cached)
      try {
        debugPrint(
          'TVseriesplayer: creating controller via preloader for url=${currentEpisode.videoUrl}',
        );
        _controller = await _videoPreloader.createController(
          currentEpisode.videoUrl,
        );
      } catch (e) {
        debugPrint('Failed to create controller via preloader: $e');
        _controller = VideoPlayerController.networkUrl(
          Uri.parse(currentEpisode.videoUrl),
        );
      }
    }

    try {
      // initialize; if a newer init started meanwhile, abort applying this controller
      await _controller!.initialize();
      debugPrint(
        'TVseriesplayer: initialize completed for token=$initToken currentToken=$_controllerInitToken',
      );
      if (initToken != _controllerInitToken) {
        // A newer init started: discard this controller
        try {
          _controller?.removeListener(_videoListener);
          await _controller?.dispose();
        } catch (_) {}
        return;
      }
      _controller!
        ..setLooping(false)
        ..play();

      // إضافة الـ listener هنا
      _controller!.addListener(_videoListener);

      setState(() {
        isPlaying = true;
        _showPlayIcon = false;
        _showLoadingIndicator = false;
      });

      WakelockPlus.enable();
      _sendViewToServer();
      _startProgressTimer();
      _preloadAdjacentVideos();
      debugPrint('TVseriesplayer: controller applied for index=$currentIndex');
    } catch (e) {
      debugPrint('Error initializing video controller: $e');
      if (mounted) {
        setState(() {
          _showLoadingIndicator = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('An error occurred while playing the video.'),
          ),
        );
      }
    }
  }

  void _videoListener() {
    if (_controller == null || !_controller!.value.isInitialized || !mounted) {
      return;
    }

    // تحديث حالة التشغيل
    if (_controller!.value.isPlaying != isPlaying) {
      setState(() {
        isPlaying = _controller!.value.isPlaying;
        _showPlayIcon = !isPlaying;
      });
    }

    // تحديث التقدم إذا لم يكن المستخدم يسحب
    if (!_isSeeking) {
      setState(() {});
    }

    // معالجة نهاية الحلقة
    if (_controller!.value.isCompleted &&
        !_isLoadingNextEpisode &&
        !_isAdShowing &&
        !_isSwiping) {
      _handleEpisodeEnd();
    }

    // إخفاء عناصر التحكم بعد 3 ثوان
    if (_showControls &&
        DateTime.now().difference(_controlsHideTime).inSeconds > 20) {
      setState(() => _showControls = false);
    }
  }

  void _handleEpisodeEnd() async {
    if (AppConfig.isFreeMode) {
      // If free mode and ads are disabled via server flag, skip ad and navigate directly
      if (!AppConfig.freeModeAdsEnabled) {
        await _navigateToEpisode(currentIndex + 1);
        return;
      }
      // When ads are enabled in free mode, show ad to unlock next episode
      _watchAdToUnlockEpisode(widget.episodes[currentIndex + 1]);
      return;
    }
    if (_controller == null || currentIndex + 1 >= widget.episodes.length) {
      _controller?.pause();
      return;
    }

    if (mounted) setState(() => _isLoadingNextEpisode = true);

    widget.onEpisodeWatched?.call(currentEpisode.id);
    final nextEpisode = widget.episodes[currentIndex + 1];
    if (AppConfig.isFreeMode) {
      await _navigateToEpisode(currentIndex + 1);
      if (mounted) setState(() => _isLoadingNextEpisode = false);
      return;
    }
    if (_currentUser?.isVip != true &&
        _isEpisodePaid(nextEpisode) &&
        !_isEpisodeUnlocked(nextEpisode)) {
      // إذا كان لدى المستخدم رصيد كافي، اخصم تلقائياً
      if (_userCoins >= currentEpisode.priceCoins) {
        await _unlockWithCoins(nextEpisode);
        // بعد فتح الحلقة، انتقل إليها
        await _navigateToEpisode(currentIndex + 1);
      }
      // إذا لم يكن لديه رصيد، اعرض الديالوق
      else {
        _controller?.pause();
        if (mounted && !_isEpisodeLockedDialogShown) {
          _showPaymentDialog(nextEpisode);
        }
      }
    } else {
      await _navigateToEpisode(currentIndex + 1);
    }

    if (mounted) setState(() => _isLoadingNextEpisode = false);
  }

  Future<void> _navigateToEpisode(int index) async {
    if (!mounted || index < 0 || index >= widget.episodes.length) return;
    // mark a new swap/initialization attempt; this invalidates previous async inits
    final int navInitToken = ++_controllerInitToken;

    setState(() {
      _isSwiping = true;
    });

    await _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );

    // If we have a preloaded controller for the target index, use it to swap instantly.
    final preloaded = _preloadedControllers.remove(index);
    if (preloaded != null) {
      try {
        final swapStart = DateTime.now();
        // Pause and detach listener from old controller but don't dispose until new one is ready
        final old = _controller;
        if (old != null) {
          old.removeListener(_videoListener);
          old.pause();
        }

        _controller = preloaded;
        _controller!.addListener(_videoListener);
        if (_controller!.value.isInitialized) {
          _controller!
            ..setLooping(false)
            ..play();
        } else {
          debugPrint(
            'TVseriesplayer: initializing preloaded controller for index=$index',
          );
          await _controller!.initialize();
          // if a newer navigate/init started, abort applying this controller
          if (navInitToken != _controllerInitToken) {
            try {
              _controller?.removeListener(_videoListener);
              await _controller?.dispose();
            } catch (_) {}
            return;
          }
          _controller!
            ..setLooping(false)
            ..play();
        }

        setState(() {
          currentIndex = index;
          currentEpisode = widget.episodes[index];
          isPlaying = true;
          _showPlayIcon = false;
          _showLoadingIndicator = false;
        });

        final swapEnd = DateTime.now();
        debugPrint(
          'TVseriesplayer: swapped to index $index using preloaded controller in ${swapEnd.difference(swapStart).inMilliseconds}ms (navToken=$navInitToken currentToken=$_controllerInitToken)',
        );

        // Now dispose the old controller if it exists
        if (old != null) {
          try {
            old.removeListener(_videoListener);
            await old.dispose();
          } catch (e) {
            debugPrint('Error disposing old controller: $e');
          }
        }

        _sendViewToServer();
        _startProgressTimer();
        _preloadAdjacentVideos();
        _loadEpisodeStats();
        // save watch progress after switching episodes
        _persistWatchProgress();
      } catch (e) {
        debugPrint('Error switching to preloaded controller: $e');
        // fallback to normal init
        if (_controller != null) {
          try {
            _controller!.removeListener(_videoListener);
            await _controller!.dispose();
          } catch (_) {}
        }
        currentIndex = index;
        currentEpisode = widget.episodes[index];
        await _initializeVideoController();
        await _loadEpisodeStats();
      }
    } else {
      // No preloaded controller, fallback to original flow
      setState(() {
        currentIndex = index;
        currentEpisode = widget.episodes[index];
        _showLoadingIndicator = true;
      });

      if (_controller != null) {
        _controller!.removeListener(_videoListener);
        await _controller!.dispose();
      }

      await _initializeVideoController();
      await _loadEpisodeStats();
    }

    setState(() {
      _isSwiping = false;
    });

    widget.onEpisodeChanged?.call(index);
  }

  bool _isEpisodePaid(Episode episode) {
    if (AppConfig.isFreeMode) return false;
    if (_currentUser?.isVip == true) return false;
    return episode.episodeNumber > widget.freeEpisodesCount;
  }

  bool _isEpisodeUnlocked(Episode episode) {
    if (!_isEpisodePaid(episode)) return true;

    final unlockedTime = _unlockedEpisodes[episode.id];
    return unlockedTime != null && unlockedTime.isAfter(DateTime.now());
  }

  void _showPaymentDialog(Episode episode) {
    if (AppConfig.isFreeMode) {
      _navigateToEpisode(widget.episodes.indexOf(episode));
      return;
    }
    setState(() {
      _shouldBlockNavigation = true;
      _isEpisodeLockedDialogShown = true;
    });

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black87,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.grey[900],
            borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Colors.grey[800]!, width: 1),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.lock, color: Colors.white, size: 30),
                    const SizedBox(width: 10),
                    Text(
                      'حلقة ${episode.episodeNumber} مدفوع',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 15,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'رصيدك الحالي:',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                    Row(
                      children: [
                        const Icon(
                          Icons.monetization_on,
                          color: Colors.amber,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '$_userCoins',
                          style: const TextStyle(
                            color: Colors.amber,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (_currentUser?.isVip != true)
                _buildPaymentOption(
                  icon: Icons.star,
                  title: 'اشترك في VIP',
                  subtitle: 'فتح جميع الحلقات بشكل دائم',
                  buttonText: 'عرض الحزم',
                  color: Colors.green,
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => VipPackagesScreen(
                          userId: int.parse(_currentUser!.id),
                          userEmail: _currentUser!.email,

                          isVip: _currentUser?.isVip ?? false,
                          vipExpiry: _currentUser?.vipExpiry,
                        ),
                      ),
                    ).then((_) => _checkVipStatus());
                  },
                ),
              (_adsWatchedToday < widget.maxDailyAds)
                  ? _buildPaymentOption(
                      icon: Icons.video_library,
                      title: 'شاهد إعلان لفتح حلقتين',
                      subtitle:
                          'الإعلانات اليوم ($_adsWatchedToday/${widget.maxDailyAds})',
                      buttonText: 'شاهد إعلان',
                      color: Colors.red,
                      onTap: () {
                        Navigator.pop(context);
                        // If ads are disabled for free mode on server, skip the ad and unlock/navigate directly
                        if (AppConfig.isFreeMode &&
                            !AppConfig.freeModeAdsEnabled) {
                          final nextIndex = widget.episodes.indexOf(episode);
                          if (nextIndex != -1) {
                            _navigateToEpisode(nextIndex);
                          }
                        } else {
                          _watchAdToUnlockEpisode(episode);
                        }
                      },
                    )
                  : Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 15,
                        vertical: 10,
                      ),
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: Colors.grey[850],
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.lock, color: Colors.white),
                              const SizedBox(width: 15),
                              const Expanded(
                                child: Text(
                                  'انتهت محاولات اليوم',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 15),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey[800],
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.timer,
                                  color: Colors.white,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'يعود بعد 24 ساعة',
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
              _buildPaymentOption(
                icon: Icons.monetization_on,
                title: 'فتح الحلقة باستخدام العملات المعدنية',
                subtitle:
                    'تكلفة الحلقة: ${currentEpisode.priceCoins} عملات معدنية',
                buttonText: _userCoins >= currentEpisode.priceCoins
                    ? 'استخدم العملات المعدنية'
                    : 'اكسب المزيد من العملات المعدنية',
                color: _userCoins >= currentEpisode.priceCoins
                    ? Colors.amber
                    : Colors.grey,
                onTap: () {
                  Navigator.pop(context);
                  if (_userCoins >= currentEpisode.priceCoins) {
                    _unlockWithCoins(episode);
                  } else {
                    _loadUserCoins();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => in_app_purchase(
                          userId: int.tryParse(_currentUser!.id) ?? 0,
                          userEmail: _currentUser!.email,
                          currentCoins: _currentUser!.coins,
                        ),
                      ),
                    ).then((result) {
                      if (result != null && mounted) {
                        setState(() {
                          _currentUser = _currentUser!.copyWith(coins: result);
                          _userCoins = result;
                        });
                      }
                    });
                  }
                },
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _shouldBlockNavigation = false;
                    _isEpisodeLockedDialogShown = false;
                  });
                  Navigator.pop(context);
                },
                child: const Text(
                  'يلغي',
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    ).then((_) {
      if (mounted) {
        setState(() {
          _shouldBlockNavigation = false;
          _isEpisodeLockedDialogShown = false;
        });
      }
    });
  }

  Widget _buildPaymentOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required String buttonText,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.grey[850],
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.white),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      style: TextStyle(color: Colors.grey[400], fontSize: 14),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: onTap,
              child: Text(
                buttonText,
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveUnlockedEpisodeLocally(int episodeId) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final unlockUntil = now.add(const Duration(days: 7));

    // مفتاح خاص بالمسلسل الحالي
    final unlockedKey = 'unlocked_episodes_$_currentSeriesId';

    final unlockedEpisodesJson = prefs.getString(unlockedKey) ?? '{}';
    final unlockedEpisodes = Map<String, dynamic>.from(
      json.decode(unlockedEpisodesJson),
    );

    unlockedEpisodes[episodeId.toString()] = unlockUntil.toIso8601String();

    await prefs.setString(unlockedKey, json.encode(unlockedEpisodes));

    setState(() {
      _unlockedEpisodes[episodeId] = unlockUntil;
      widget.episodes.firstWhere((e) => e.id == episodeId).isLocked = false;
    });
  }

  Future<void> _loadUnlockedEpisodes() async {
    final prefs = await SharedPreferences.getInstance();

    // مفتاح خاص بالمسلسل الحالي
    final unlockedKey = 'unlocked_episodes_$_currentSeriesId';

    final unlockedEpisodesJson = prefs.getString(unlockedKey) ?? '{}';
    final unlockedEpisodesData = Map<String, dynamic>.from(
      json.decode(unlockedEpisodesJson),
    );

    final now = DateTime.now();
    final validEpisodes = <int, DateTime>{};

    unlockedEpisodesData.forEach((episodeId, untilString) {
      final until = DateTime.parse(untilString);
      if (until.isAfter(now)) {
        validEpisodes[int.parse(episodeId)] = until;
      }
    });

    setState(() {
      _unlockedEpisodes = validEpisodes;
    });

    for (var episode in widget.episodes) {
      if (_unlockedEpisodes.containsKey(episode.id)) {
        episode.isLocked = false;
      }
    }
  }

  Future<void> _loadAdWatchData() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();

    // مفتاح خاص بالمسلسل الحالي
    final adsKey = 'ads_watched_today_$_currentSeriesId';
    final dateKey = 'last_ad_watch_date_$_currentSeriesId';

    _adsWatchedToday = prefs.getInt(adsKey) ?? 0;
    final lastAdWatchDateString = prefs.getString(dateKey);
    DateTime? lastAdWatchDate = lastAdWatchDateString != null
        ? DateTime.parse(lastAdWatchDateString)
        : null;

    if (lastAdWatchDate != null &&
        now.difference(lastAdWatchDate).inHours >= 24) {
      await prefs.setInt(adsKey, 0);
      await prefs.setString(dateKey, now.toString());
      setState(() {
        _adsWatchedToday = 0;
      });
    } else {
      setState(() {
        _adsWatchedToday = prefs.getInt(adsKey) ?? 0;
      });
    }
  }

  Future<void> _unlockWithCoins(Episode episode) async {
    final isSignedIn = await AuthService().isSignedIn();
    if (!isSignedIn) {
      await _showLoginRequiredDialog(
        message: 'يجب عليك تسجيل الدخول لاستخدام العملات المعدنية',
        actionText: 'تسجيل الدخول',
      );
      return;
    }

    try {
      final response = await ApiService().unlockEpisodeWithCoins(
        episode.id,
        currentEpisode.priceCoins,
      );

      if (response['status'] == 'success' && mounted) {
        await _saveUnlockedEpisodeLocally(episode.id);

        setState(() {
          _userCoins = response['new_balance'] ?? _userCoins;
          _unlockedEpisodes[episode.id] = DateTime.now().add(Duration(days: 2));
        });

        _showUnlockedMessage();

        final nextIndex = widget.episodes.indexWhere((e) => e.id == episode.id);
        if (nextIndex != -1) {
          await _pageController.animateToPage(
            nextIndex,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );

          if (mounted) {
            setState(() {
              currentIndex = nextIndex;
              currentEpisode = widget.episodes[nextIndex];
              _controller?.removeListener(_videoListener);
              _controller?.dispose();
            });
            await _initializeVideoController();
            _loadEpisodeStats();
            // save after initializing
            _persistWatchProgress();
          }
        }
      } else {
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(response['message'] ?? 'Failed to open loop')),
        );
      }
    } catch (e) {
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('An error occurred: ${e.toString()}')),
      );
    }
  }

  // ignore: unused_element
  void _loadRewardedAd33() {
    if (_rewardedAdUnitId == null) return;

    RewardedAd.load(
      adUnitId: _rewardedAdUnitId!,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (RewardedAd ad) {
          setState(() {
            _rewardedAd = ad;
          });
        },
        onAdFailedToLoad: (LoadAdError error) {
          _loadRewardedAd();
        },
      ),
    );
  }

  void _watchAdToUnlockEpisode(Episode episode) async {
    if (_rewardedAd == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('جاري تحميل الإعلان، يرجى الانتظار...')),
      );
      _loadRewardedAd();
      return;
    }

    setState(() {
      _isAdShowing = true;
      _controller?.pause();
      isPlaying = false;
      _showPlayIcon = true;
    });

    _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        setState(() => _isAdShowing = false);
        _rotateAdUnit(); // تدوير الشفرات بعد انتهاء الإعلان

        // ✅ الكود الجديد: إذا كان الوضع مجاني، انتقل مباشرة بعد الإعلان
        if (AppConfig.isFreeMode) {
          final nextIndex = widget.episodes.indexOf(episode);
          if (nextIndex != -1) {
            _navigateToEpisode(nextIndex);
          }
        } else {
          _handleAdCompletedSuccessfully(episode);
        }
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        setState(() => _isAdShowing = false);
        _rotateAdUnit();

        // ✅ الكود الجديد: إذا فشل الإعلان في الوضع المجاني، انتقل anyway
        if (AppConfig.isFreeMode) {
          final nextIndex = widget.episodes.indexOf(episode);
          if (nextIndex != -1) {
            _navigateToEpisode(nextIndex);
          }
        }
      },
    );

    _rewardedAd!.show(onUserEarnedReward: (ad, reward) {});
  }

  String _formatDuration(Duration position) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    final minutes = twoDigits(position.inMinutes.remainder(60));
    final seconds = twoDigits(position.inSeconds.remainder(60));
    return "$minutes:$seconds";
  }

  Future<void> _handleAdCompletedSuccessfully(Episode episode) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();

    // مفتاح خاص بالمسلسل الحالي
    final adsKey = 'ads_watched_today_$_currentSeriesId';
    final dateKey = 'last_ad_watch_date_$_currentSeriesId';

    final newAdsWatched = _adsWatchedToday + 1;
    await prefs.setInt(adsKey, newAdsWatched);
    await prefs.setString(dateKey, now.toString());

    // فتح حلقتين لكل إعلان
    final currentEpisodeIndex = widget.episodes.indexOf(episode);
    final episodesToUnlock = <Episode>[];

    for (int i = 0; i < widget.episodesPerAd; i++) {
      if (currentEpisodeIndex + i < widget.episodes.length) {
        episodesToUnlock.add(widget.episodes[currentEpisodeIndex + i]);
      }
    }

    for (final ep in episodesToUnlock) {
      await _saveUnlockedEpisodeLocally(ep.id);
    }

    if (mounted) {
      setState(() {
        _adsWatchedToday = newAdsWatched;
        for (final ep in episodesToUnlock) {
          _unlockedEpisodes[ep.id] = now.add(const Duration(days: 7));
        }
      });

      _showUnlockedMessage();

      final nextIndex = widget.episodes.indexOf(episode);
      if (nextIndex != -1) {
        await _navigateToEpisode(nextIndex);
      }
    }
  }

  void _showUnlockedMessage() {
    if (!mounted) return;

    setState(() {
      _showUnlockToast = true;
    });

    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _showUnlockToast = false;
        });
      }
    });
  }

  void _handleScreenTap() {
    if (_controller == null || _isAdShowing) return;

    if (_showPlayIcon) {
      _controller!.play();
      setState(() {
        _showPlayIcon = false;
        isPlaying = true;
      });
    } else {
      _controller!.pause();
      setState(() {
        _showPlayIcon = true;
        isPlaying = false;
      });
    }

    setState(() {
      _showControls = true;
    });

    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _showControls = false);
      }
    });
  }

  void _showEpisodesGrid() {
    if (_isAdShowing) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please finish the ad first')),
      );
      return;
    }

    final episodesPerPage = 30;
    final totalPages = (widget.episodes.length / episodesPerPage).ceil();
    final pageController = PageController();
    int currentTabIndex = 0;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            padding: const EdgeInsets.all(16),
            height: MediaQuery.of(context).size.height * 0.7,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'الحلقات',
                      style: TextStyle(color: Colors.white, fontSize: 20),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 40,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: totalPages,
                    itemBuilder: (context, index) {
                      final start = index * episodesPerPage + 1;
                      final end = ((index + 1) * episodesPerPage).clamp(
                        1,
                        widget.episodes.length,
                      );
                      return GestureDetector(
                        onTap: () {
                          pageController.animateToPage(
                            index,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                          setModalState(() => currentTabIndex = index);
                        },
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: currentTabIndex == index
                                ? const Color.fromARGB(60, 48, 47, 47)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Center(
                            child: Text(
                              '$start-$end',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: PageView.builder(
                    controller: pageController,
                    onPageChanged: (index) {
                      setModalState(() => currentTabIndex = index);
                    },
                    itemCount: totalPages,
                    itemBuilder: (context, pageIndex) {
                      final start = pageIndex * episodesPerPage;
                      final end = ((pageIndex + 1) * episodesPerPage).clamp(
                        0,
                        widget.episodes.length,
                      );
                      final episodesPage = widget.episodes.sublist(start, end);

                      return GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 5,
                              mainAxisSpacing: 10,
                              crossAxisSpacing: 10,
                              childAspectRatio: 1,
                            ),
                        itemCount: episodesPage.length,
                        itemBuilder: (context, index) {
                          final episode = episodesPage[index];
                          final isCurrent = episode.id == currentEpisode.id;
                          final isLocked =
                              _currentUser?.isVip != true &&
                              _isEpisodePaid(episode) &&
                              !_isEpisodeUnlocked(episode);

                          return GestureDetector(
                            onTap: () {
                              // إذا كان الوضع مجاني
                              if (AppConfig.isFreeMode) {
                                if (!AppConfig.freeModeAdsEnabled) {
                                  // تخطي الإعلانات وفتح الحلقة مباشرة
                                  _navigateToEpisode(
                                    widget.episodes.indexOf(episode),
                                  );
                                  Navigator.pop(context);
                                } else {
                                  if (AppConfig.isFreeMode &&
                                      !AppConfig.freeModeAdsEnabled) {
                                    final nextIndex = widget.episodes.indexOf(
                                      episode,
                                    );
                                    if (nextIndex != -1) {
                                      _navigateToEpisode(nextIndex);
                                    }
                                  } else {
                                    _watchAdToUnlockEpisode(episode);
                                  }
                                  Navigator.pop(context);
                                }
                              } else if (isLocked) {
                                Navigator.pop(context);
                                _showPaymentDialog(episode);
                              } else {
                                _navigateToEpisode(
                                  widget.episodes.indexOf(episode),
                                );
                                Navigator.pop(context);
                              }
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                color: isCurrent
                                    ? Colors.red
                                    : (isLocked
                                          ? Colors.grey[800]
                                          : Colors.grey[900]),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Stack(
                                children: [
                                  Center(
                                    child: Text(
                                      '${episode.episodeNumber}',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: isCurrent
                                            ? FontWeight.bold
                                            : null,
                                      ),
                                    ),
                                  ),
                                  if (isCurrent)
                                    Positioned(
                                      bottom: 4,
                                      left: 4,
                                      right: 4,
                                      child: Image.asset(
                                        'assets/images/s.webp',
                                        height: 15,
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                  if (_currentUser?.isVip == true)
                                    const Positioned(
                                      top: 4,
                                      right: 4,
                                      child: Icon(
                                        Icons.verified,
                                        color: Colors.amber,
                                        size: 16,
                                      ),
                                    )
                                  else if (isLocked)
                                    const Positioned(
                                      top: 4,
                                      right: 4,
                                      child: Icon(
                                        Icons.lock,
                                        color: Colors.white,
                                        size: 16,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showSettingsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                AppLocalizations.of(context)!.videoSettings,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'سرعة الفيديو',
                    style: TextStyle(color: Colors.white),
                  ),
                  DropdownButton<double>(
                    dropdownColor: Colors.black,
                    value: _playbackSpeed,
                    items: const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
                        .map<DropdownMenuItem<double>>(
                          (speed) => DropdownMenuItem(
                            value: speed,
                            child: Text(
                              "${speed}x",
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (speed) {
                      if (speed != null &&
                          _controller != null &&
                          !_isAdShowing) {
                        setState(() {
                          _playbackSpeed = speed;
                          _controller!.setPlaybackSpeed(speed);
                        });
                        Navigator.pop(context);
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildProgressBar() {
    return Positioned(
      bottom: 106,
      left: 16,
      right: 16,
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final barWidth = constraints.maxWidth;
              final duration = _controller!.value.duration;
              final position = _controller!.value.position;

              // نسبة التشغيل الحالية
              final playedFraction = duration.inMilliseconds > 0
                  ? position.inMilliseconds / duration.inMilliseconds
                  : 0.0;

              // أثناء السحب نستخدم موقع اليد بدل النسبة الحقيقية
              final fraction = _isDragging
                  ? _dragPosition / barWidth
                  : playedFraction;

              final previewPosition = Duration(
                milliseconds:
                    (fraction.clamp(0.0, 1.0) * duration.inMilliseconds)
                        .toInt(),
              );

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) {
                  final dx = details.localPosition.dx.clamp(0, barWidth);
                  final newPosition = Duration(
                    milliseconds: (dx / barWidth * duration.inMilliseconds)
                        .toInt(),
                  );
                  _controller!.seekTo(newPosition);
                },
                onHorizontalDragStart: (details) {
                  _isDragging = true;
                  _dragPosition = details.localPosition.dx;
                },
                onHorizontalDragUpdate: (details) {
                  _dragPosition = details.localPosition.dx.clamp(0, barWidth);
                  setState(() {}); // لتحديث الوقت المنبثق والجزء المشاهد
                },
                onHorizontalDragEnd: (details) {
                  final newPosition = Duration(
                    milliseconds:
                        (_dragPosition / barWidth * duration.inMilliseconds)
                            .toInt(),
                  );
                  _controller!.seekTo(newPosition);
                  _isDragging = false;
                  setState(() {});
                },
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    // الخلفية
                    Container(
                      height: 10,
                      decoration: BoxDecoration(
                        color: const Color.fromARGB(
                          255,
                          177,
                          45,
                          45,
                        ).withOpacity(0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),

                    // الجزء المشاهد
                    FractionallySizedBox(
                      widthFactor: fraction.clamp(0.0, 1.0),
                      child: Container(
                        height: 10,
                        decoration: BoxDecoration(
                          color: const Color.fromARGB(255, 236, 73, 127),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),

                    // المؤشر الدائري
                    Positioned(
                      left: (fraction.clamp(0.0, 1.0) * barWidth) - 8,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),

                    // الوقت المنبثق أثناء السحب
                    if (_isDragging)
                      Positioned(
                        left: (fraction.clamp(0.0, 1.0) * barWidth) - 25,
                        bottom: 20,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 4,
                            horizontal: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _formatDuration(previewPosition),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),

          // الوقت الكلي والمشاهد
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatDuration(_controller!.value.position),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
                Text(
                  _formatDuration(_controller!.value.duration),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_isAdShowing) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please finish the ad first')),
          );
          return false;
        }
        return true;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          onTap: _handleScreenTap,
          child: Stack(
            children: [
              NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (notification is ScrollStartNotification) {
                    setState(() => _isSwiping = true);
                  } else if (notification is ScrollEndNotification) {
                    setState(() => _isSwiping = false);
                  }
                  return false;
                },
                child: PageView.builder(
                  controller: _pageController,
                  scrollDirection: Axis.vertical,
                  itemCount: widget.episodes.length,
                  onPageChanged: (index) async {
                    // If app is in free mode, decide based on server flag whether to show ad or navigate directly
                    if (AppConfig.isFreeMode &&
                        !_isAdShowing &&
                        !_shouldBlockNavigation) {
                      if (!AppConfig.freeModeAdsEnabled) {
                        // Ads disabled in free mode -> navigate directly
                        setState(() {
                          currentIndex = index;
                          currentEpisode = widget.episodes[index];
                          _controller?.removeListener(_videoListener);
                          _controller?.dispose();
                          _showLoadingIndicator = true;
                        });
                        await _initializeVideoController();
                        _loadEpisodeStats();
                        widget.onEpisodeChanged?.call(index);
                        return;
                      } else {
                        // Ads enabled in free mode -> show ad to unlock
                        _watchAdToUnlockEpisode(widget.episodes[index]);
                        return;
                      }
                    }

                    if (!mounted ||
                        index == currentIndex ||
                        index >= widget.episodes.length ||
                        _isAdShowing ||
                        _shouldBlockNavigation) {
                      if (_shouldBlockNavigation || _isAdShowing) {
                        _pageController.jumpToPage(currentIndex);
                      }
                      return;
                    }

                    final nextEpisode = widget.episodes[index];

                    // Handle paid/unlocked logic first (same as before)
                    if (AppConfig.isFreeMode) {
                      // If the admin disabled ads in free mode, skip ad flow and navigate directly
                      if (!AppConfig.freeModeAdsEnabled) {
                        setState(() {
                          currentIndex = index;
                          currentEpisode = nextEpisode;
                          _controller?.removeListener(_videoListener);
                          _controller?.dispose();
                          _showLoadingIndicator = true;
                        });
                        await _initializeVideoController();
                        _loadEpisodeStats();
                        widget.onEpisodeChanged?.call(index);
                        return;
                      }

                      setState(() {
                        currentIndex = index;
                        currentEpisode = nextEpisode;
                        _controller?.removeListener(_videoListener);
                        _controller?.dispose();
                        _showLoadingIndicator = true;
                      });
                      await _initializeVideoController();
                      _loadEpisodeStats();
                      widget.onEpisodeChanged?.call(index);
                      return;
                    }

                    if (_currentUser?.isVip != true &&
                        _isEpisodePaid(nextEpisode) &&
                        !_isEpisodeUnlocked(nextEpisode)) {
                      if (_userCoins >= currentEpisode.priceCoins) {
                        await _unlockWithCoins(nextEpisode);
                        // switch to episode using navigate helper which prefers preloaded controllers
                        await _navigateToEpisode(index);
                      } else {
                        _pageController.jumpToPage(currentIndex);
                        if (!_isEpisodeLockedDialogShown) {
                          _showPaymentDialog(nextEpisode);
                        }
                      }
                      return;
                    }

                    // If we have a preloaded controller we can swap immediately
                    final preloaded = _preloadedControllers.remove(index);
                    if (preloaded != null) {
                      final swapStart = DateTime.now();
                      final old = _controller;
                      if (old != null) {
                        old.removeListener(_videoListener);
                        old.pause();
                      }

                      _controller = preloaded;
                      _controller!.addListener(_videoListener);
                      if (_controller!.value.isInitialized) {
                        _controller!
                          ..setLooping(false)
                          ..play();
                      } else {
                        setState(() => _showLoadingIndicator = true);
                        try {
                          await _controller!.initialize();
                          _controller!
                            ..setLooping(false)
                            ..play();
                        } catch (e) {
                          debugPrint('Failed to init preloaded controller: $e');
                        }
                        setState(() => _showLoadingIndicator = false);
                      }

                      setState(() {
                        currentIndex = index;
                        currentEpisode = nextEpisode;
                        isPlaying = true;
                        _showPlayIcon = false;
                      });

                      final swapEnd = DateTime.now();
                      debugPrint(
                        'TVseriesplayer: onPageChanged swapped to $index with preloaded controller in ${swapEnd.difference(swapStart).inMilliseconds}ms',
                      );

                      // dispose old after new is running
                      if (old != null) {
                        try {
                          old.removeListener(_videoListener);
                          await old.dispose();
                        } catch (e) {
                          debugPrint('Error disposing old controller: $e');
                        }
                      }

                      _sendViewToServer();
                      _startProgressTimer();
                      _preloadAdjacentVideos();
                      _loadEpisodeStats();
                      widget.onEpisodeChanged?.call(index);
                      return;
                    }

                    // fallback to normal behavior
                    setState(() {
                      currentIndex = index;
                      currentEpisode = nextEpisode;
                      _controller?.removeListener(_videoListener);
                      _controller?.dispose();
                      _showLoadingIndicator = true;
                    });
                    await _initializeVideoController();
                    _loadEpisodeStats();
                    widget.onEpisodeChanged?.call(index);
                  },

                  itemBuilder: (context, index) {
                    // Precompute video area widget to avoid placing try/catch inside children list
                    Widget videoArea;
                    try {
                      if (_controller != null &&
                          _controller!.value.isInitialized) {
                        videoArea = Positioned.fill(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 40),
                            child: ClipRRect(
                              borderRadius: const BorderRadius.only(
                                bottomLeft: Radius.circular(25),
                                bottomRight: Radius.circular(25),
                              ),
                              child: AspectRatio(
                                aspectRatio: _controller!.value.aspectRatio,
                                child: VideoPlayer(_controller!),
                              ),
                            ),
                          ),
                        );
                      } else {
                        videoArea = Center(
                          child: Lottie.asset(
                            'assets/animations/load-house.json', // الأنيميشن الأخضر
                            width: 5050,
                            height: 100,
                            fit: BoxFit.contain,
                          ),
                        );
                      }
                    } catch (e, st) {
                      debugPrint('Video build exception: $e\n$st');
                      videoArea = Positioned.fill(
                        child: Container(
                          color: Colors.black,
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(
                                  Icons.error,
                                  color: Colors.white,
                                  size: 40,
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'حدث خطأ أثناء تشغيل الفيديو. حاول مرة أخرى.',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }

                    return Stack(
                      children: [
                        videoArea,

                        if (_controller != null &&
                            _controller!.value.isInitialized)
                          buildProgressBar(),

                        if (_showLoadingIndicator)
                          Center(
                            child: Lottie.asset(
                              'assets/animations/load-house.json', // ضع هنا مسار ملف Lottie لللودنج
                              width: 100,
                              height: 100,
                              fit: BoxFit.contain,
                            ),
                          ),

                        //if (_showControls)
                        //   Positioned(
                        ///  bottom: 200,
                        // /// right: 20,
                        ///  child: AppConfig.isFreeMode
                        /// ? Container(
                        ///   padding: const EdgeInsets.symmetric(
                        ///  horizontal: 12,
                        //   vertical: 6,
                        //),
                        //  decoration: BoxDecoration(
                        //  color: Colors.green.withOpacity(0.8),
                        // borderRadius: BorderRadius.circular(20),
                        // ),
                        // child: const Row(
                        //  children: [
                        //    Icon(
                        //    Icons.lock_open,
                        //   color: Colors.white,
                        // size: 16,
                        //  ),
                        // SizedBox(width: 4),
                        ////  Text(
                        //    'وضع مجاني',
                        //    style: TextStyle(
                        //    color: Colors.white,
                        //      fontSize: 12,
                        //  fontWeight: FontWeight.bold,
                        //    ),
                        //  ),
                        //  ],
                        // ),
                        //)
                        // : Container(),
                        //),

                        //if (_showControls)
                        Positioned(
                          bottom: 170,
                          right: 20,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                currentEpisode.title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                                textDirection: TextDirection.rtl,
                              ),
                              if (_currentUser?.isVip == true)
                                Container(
                                  margin: const EdgeInsets.only(top: 5),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: Colors.green),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.verified,
                                        color: Colors.green,
                                        size: 14,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'VIP',
                                        style: const TextStyle(
                                          color: Colors.green,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),

                        Positioned(
                          bottom: 50,
                          left: 8,

                          right: 8,
                          child: Directionality(
                            textDirection: TextDirection.rtl,
                            child: GestureDetector(
                              onTap: _isAdShowing ? null : _showEpisodesGrid,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: const Color.fromARGB(
                                    255,
                                    34,
                                    34,
                                    34,
                                  ).withOpacity(0.5),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                  horizontal: 20,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  children: [
                                    Image.asset(
                                      'assets/images/icon_hall_chapter.webp',
                                      width: 24,
                                      height: 24,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${currentEpisode.episodeNumber} / ${widget.episodes.length}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const Spacer(),
                                    Image.asset(
                                      'assets/images/icon_gery_press_up.png',
                                      width: 24,
                                      height: 24,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (_showPlayIcon)
                          Center(
                            child: GestureDetector(
                              onTap: _handleScreenTap,
                              child: Image.asset(
                                'assets/images/icon_play_new_36.png',
                                width: 70,
                                height: 70,
                              ),
                            ),
                          ),
                        // if (_showControls)
                        Positioned(
                          bottom: 270,
                          left: 3,
                          child: GestureDetector(
                            onTap: _isAdShowing ? null : _toggleLike,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Column(
                                children: [
                                  _isLikeLoading
                                      ? const SizedBox(
                                          width: 55,
                                          height: 55,
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : ScaleTransition(
                                          scale:
                                              Tween<double>(
                                                begin: 0.8,
                                                end: 1.2,
                                              ).animate(
                                                CurvedAnimation(
                                                  parent:
                                                      _likeAnimationController,
                                                  curve: Curves.easeOut,
                                                ),
                                              ),
                                          child: Image.asset(
                                            _isLiked
                                                ? 'assets/images/icon_item_video_like.webp'
                                                : 'assets/images/icon_item_video_like_none.webp',
                                            width: 55,
                                            height: 55,
                                          ),
                                        ),
                                  const SizedBox(height: 4),
                                  Text(
                                    formatNumber(_likeCount, arabic: true),
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // if (_showControls)
                        Positioned(
                          bottom: 200,
                          left: 3,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Column(
                              children: [
                                Image.asset(
                                  'assets/images/icon_open_eye.png',
                                  width: 55,
                                  height: 55,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  formatNumber(_viewCount, arabic: true),
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                        ),
                        //if (_showControls)
                        Positioned(
                          bottom: 150,
                          left: 8,
                          child: GestureDetector(
                            onTap: _isAdShowing ? null : _showSettingsSheet,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Image.asset(
                                    'assets/images/ic_video_more.png',
                                    width: 50,
                                    height: 50,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (_showUnlockToast)
                          Positioned(
                            bottom: MediaQuery.of(context).size.height * 0.4,
                            left: 0,
                            right: 0,
                            child: IgnorePointer(
                              child: AnimatedOpacity(
                                opacity: _showUnlockToast ? 1.0 : 0.0,
                                duration: const Duration(milliseconds: 300),
                                child: Center(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 24,
                                      vertical: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color.fromARGB(
                                        255,
                                        63,
                                        63,
                                        63,
                                      ),
                                      borderRadius: BorderRadius.circular(20),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.3),
                                          blurRadius: 10,
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.check_circle,
                                          color: Colors.white,
                                          size: 24,
                                        ),
                                        const SizedBox(width: 8),
                                        const Text(
                                          'تم فتح الحلقة بنجاح',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    // إزالة الـ listener أولاً
    _controller?.removeListener(_videoListener);
    _controller?.dispose();
    _pageController.dispose();
    _likeAnimationController.dispose();
    _hideControlsTimer?.cancel();
    _progressTimer?.cancel();
    _autosaveTimer?.cancel();
    // persist final state
    _persistWatchProgress();
    WakelockPlus.disable();
    _toastTimer?.cancel();

    for (var controller in _preloadedControllers.values) {
      controller.dispose();
    }
    _preloadedControllers.clear();

    super.dispose();
  }
}
