import 'dart:async';
import 'package:dramix/main.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dramix/screens/LoginPage2.dart';
import 'package:dramix/screens/TVseriesplayer.dart';
import 'package:dramix/services/auth_service.dart';
import 'package:flutter/material.dart';
//import 'package:flutter_windowmanager/flutter_windowmanager.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../models/series.dart';
import '../services/api_service.dart';
import '../utils/helpers.dart';

class RecommendationsScreen extends StatefulWidget {
  const RecommendationsScreen({super.key});

  @override
  State<RecommendationsScreen> createState() => _RecommendationsScreenState();
}

class _RecommendationsScreenState extends State<RecommendationsScreen>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late Future<List<Series>> _futureSeries;
  final Map<int, VideoPlayerController> _videoControllers = {};
  final Map<int, bool> _isVideoInitialized = {};
  bool _isLoading = true;
  int _currentPageIndex = 0;
  double _playbackSpeed = 1.0;
  late AnimationController _likeAnimationController;
  bool _isLikeLoading = false;
  final Map<int, bool> _likedStatus = {};
  final Map<int, int> _likesCount = {};
  final Map<int, bool> _isVideoPlaying = {};
  final Map<int, Duration?> _videoDurations = {};
  final Map<int, Duration> _videoPositions = {};
  bool _isSeeking = false;
  Duration? _seekPosition;
  DateTime? _lastTapTime;
  bool _firstVideoReady = false;
  final Map<int, bool> _showThumbnail = {};
  bool _showControls = true;
  Timer? _controlsTimer;
  Timer? _initTimer;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // FlutterWindowManager.addFlags(FlutterWindowManager.FLAG_SECURE);
    _likeAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    WakelockPlus.enable();
    _loadSeries();
    checkPackageName();

    _initTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && !_firstVideoReady) {
        setState(() => _firstVideoReady = true);
      }
    });
  }

  @override
  void dispose() {
    _likeAnimationController.dispose();
    for (var controller in _videoControllers.values) {
      controller.dispose();
    }
    _controlsTimer?.cancel();
    _initTimer?.cancel();
    WakelockPlus.disable();
    super.dispose();
  }

  void _startControlsTimer() {
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _showControls = false);
      }
    });
  }

  Future<void> _loadSeries() async {
    final apiService = Provider.of<ApiService>(context, listen: false);
    setState(() => _isLoading = true);

    try {
      _futureSeries = apiService.getRecommendedSeries().then((
        seriesList,
      ) async {
        if (seriesList.isEmpty) return seriesList;

        if (seriesList[0].episodes.isNotEmpty) {
          await _initializeFirstVideo(0, seriesList[0].episodes.first.videoUrl);
        }

        for (int i = 1; i <= 2 && i < seriesList.length; i++) {
          if (seriesList[i].episodes.isNotEmpty) {
            _initializeVideoController(
              i,
              seriesList[i].episodes.first.videoUrl,
            );
          }
        }

        return seriesList;
      });

      await _futureSeries;
    } catch (e) {
      debugPrint('Error loading series: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _initializeFirstVideo(int index, String videoUrl) async {
    final controller = VideoPlayerController.network(videoUrl)
      ..setLooping(false)
      ..setVolume(1.0);

    _videoControllers[index] = controller;
    _isVideoInitialized[index] = false;
    _showThumbnail[index] = true;

    try {
      await controller.initialize().timeout(const Duration(seconds: 5));
      if (mounted) {
        setState(() {
          _isVideoInitialized[index] = true;
          _showThumbnail[index] = false;
          _firstVideoReady = true;
          WakelockPlus.enable();
        });
        controller.play();
      }
    } catch (e) {
      debugPrint('Error initializing first video: $e');
      if (mounted) {
        setState(() => _showThumbnail[index] = true);
      }
    }
  }

  Future<void> _initializeVideoController(int index, String videoUrl) async {
    if (_videoControllers.containsKey(index)) return;

    final controller = VideoPlayerController.network(videoUrl)
      ..setLooping(false)
      ..setVolume(1.0);

    _videoControllers[index] = controller;
    _isVideoInitialized[index] = false;
    _showThumbnail[index] = true;

    try {
      await controller.initialize();
      if (mounted) {
        setState(() {
          _isVideoInitialized[index] = true;
          _showThumbnail[index] = false;
        });
      }
    } catch (e) {
      debugPrint('Error initializing video: $e');
      if (mounted) {
        setState(() => _showThumbnail[index] = true);
      }
    }
  }

  void _preloadAdjacentVideos(int currentIndex, List<Series> seriesList) {
    for (int i = 1; i <= 2; i++) {
      final targetIndex = currentIndex + i;
      if (targetIndex < seriesList.length &&
          seriesList[targetIndex].episodes.isNotEmpty &&
          !_videoControllers.containsKey(targetIndex)) {
        _initializeVideoController(
          targetIndex,
          seriesList[targetIndex].episodes.first.videoUrl,
        );
      }
    }

    for (int i = 0; i < seriesList.length; i++) {
      if ((i < currentIndex - 1 || i > currentIndex + 3) &&
          _videoControllers.containsKey(i)) {
        _disposeVideoController(i);
      }
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$minutes:$seconds";
  }

  void _playCurrentVideo(int index) {
    if (_isVideoInitialized[index] == true) {
      _videoControllers[index]!
        ..setLooping(false)
        ..setVolume(1.0)
        ..setPlaybackSpeed(_playbackSpeed)
        ..play();
      _isVideoPlaying[index] = true;
      setState(() {
        _showControls = true;
        _startControlsTimer();
      });
    }
  }

  void _pauseVideo(int index) {
    if (_isVideoInitialized[index] == true) {
      _videoControllers[index]!.pause();
      _isVideoPlaying[index] = false;
      setState(() {
        _showControls = true;
        _controlsTimer?.cancel();
      });
    }
  }

  void _togglePlayPause(int index) {
    if (_isVideoPlaying[index] == true) {
      _pauseVideo(index);
    } else {
      _playCurrentVideo(index);
    }
  }

  void _seekVideo(int index, Duration position) {
    if (_isVideoInitialized[index] == true) {
      _videoControllers[index]!.seekTo(position);
    }
  }

  void _disposeVideoController(int index) {
    if (_videoControllers.containsKey(index)) {
      _videoControllers[index]!.removeListener(() {});
      _videoControllers[index]!.dispose();
      _videoControllers.remove(index);
      _isVideoInitialized.remove(index);
      _isVideoPlaying.remove(index);
      _videoDurations.remove(index);
      _videoPositions.remove(index);
      _showThumbnail.remove(index);
    }
  }

  void _handlePageChange(
    int index,
    Future<List<Series>> seriesListFuture,
  ) async {
    final seriesList = await seriesListFuture;
    if (index >= seriesList.length) return;

    if (_videoControllers.containsKey(_currentPageIndex)) {
      _pauseVideo(_currentPageIndex);
    }

    setState(() {
      _currentPageIndex = index;
      _showControls = true;
      _startControlsTimer();
    });

    if (seriesList[index].episodes.isNotEmpty) {
      if (!_videoControllers.containsKey(index)) {
        await _initializeVideoController(
          index,
          seriesList[index].episodes.first.videoUrl,
        );
      } else if (_isVideoInitialized[index] == true) {
        _playCurrentVideo(index);
      }
    }

    _preloadAdjacentVideos(index, seriesList);
  }

  Future<void> _toggleLike(int episodeId) async {
    if (_isLikeLoading) return;

    final isSignedIn = await AuthService().isSignedIn();
    if (!isSignedIn) {
      await _showLoginRequiredDialog();
      return;
    }

    setState(() => _isLikeLoading = true);

    try {
      final response = await Provider.of<ApiService>(
        context,
        listen: false,
      ).toggleLike(episodeId, !(_likedStatus[episodeId] ?? false));

      if (response['status'] == 'success' && mounted) {
        setState(() {
          _likedStatus[episodeId] = !(_likedStatus[episodeId] ?? false);
          _likesCount[episodeId] =
              response['likes_count'] ?? _likesCount[episodeId] ?? 0;
        });

        _likeAnimationController.forward(from: 0);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل في تحديث الإعجاب: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLikeLoading = false);
      }
    }
  }

  Future<void> _showLoginRequiredDialog() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('تسجيل الدخول مطلوب'),
        content: const Text('يجب تسجيل الدخول لتتمكن من الإعجاب بالمحتوى'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('لاحقاً'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('تسجيل الدخول'),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (context) => const LoginPage2()),
      );
    }
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
              const Text(
                'إعدادات الفيديو',
                style: TextStyle(
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
                      if (speed != null) {
                        setState(() {
                          _playbackSpeed = speed;
                          for (var controller in _videoControllers.values) {
                            if (_isVideoInitialized[_videoControllers.keys
                                    .toList()[_videoControllers.values
                                    .toList()
                                    .indexOf(controller)]] ==
                                true) {
                              controller.setPlaybackSpeed(speed);
                            }
                          }
                        });
                        Navigator.pop(context);
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.high_quality, color: Colors.white),
                title: const Text(
                  'جودة عالية',
                  style: TextStyle(color: Colors.white),
                ),
                trailing: Switch(
                  value: true,
                  onChanged: (value) {},
                  activeThumbColor: Colors.red,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTikTokProgressBar(int index) {
    final duration = _videoDurations[index] ?? Duration.zero;
    final position = _seekPosition ?? _videoPositions[index] ?? Duration.zero;
    final progress = duration.inMilliseconds > 0
        ? position.inMilliseconds / duration.inMilliseconds
        : 0.0;

    return GestureDetector(
      onHorizontalDragStart: (_) {
        setState(() {
          _isSeeking = true;
          _showControls = true;
          _controlsTimer?.cancel();
        });
      },
      onHorizontalDragUpdate: (details) {
        final box = context.findRenderObject() as RenderBox;
        final x = details.localPosition.dx.clamp(0.0, box.size.width);
        final newPosition = duration * (x / box.size.width);
        setState(() => _seekPosition = newPosition);
      },
      onHorizontalDragEnd: (_) {
        if (_seekPosition != null) {
          _seekVideo(index, _seekPosition!);
        }
        setState(() {
          _isSeeking = false;
          _seekPosition = null;
          _startControlsTimer();
        });
      },
      child: Container(
        height: 30,
        color: Colors.transparent,
        child: Column(
          children: [
            LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.grey.withOpacity(0.3),
              valueColor: AlwaysStoppedAnimation<Color>(
                const Color.fromARGB(255, 241, 1, 1),
              ),
              minHeight: 2,
            ),
            if (_isSeeking && _seekPosition != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  _formatDuration(_seekPosition!),
                  style: const TextStyle(
                    color: Color.fromARGB(255, 247, 246, 246),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.red),
              SizedBox(height: 20),
              Text(
                'جاري تحميل التوصيات...',
                style: TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: FutureBuilder<List<Series>>(
        future: _futureSeries,
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(
              child: Text(
                "لا توجد مسلسلات متاحة",
                style: TextStyle(color: Colors.white),
              ),
            );
          }

          final seriesList = snapshot.data!;

          return GestureDetector(
            onTap: () {
              final now = DateTime.now();
              if (_lastTapTime != null &&
                  now.difference(_lastTapTime!) < Duration(milliseconds: 300)) {
                _togglePlayPause(_currentPageIndex);
              } else {
                setState(() {
                  _showControls = !_showControls;
                  if (_showControls) {
                    _startControlsTimer();
                  } else {
                    _controlsTimer?.cancel();
                  }
                });
              }
              _lastTapTime = now;
            },
            child: PageView.builder(
              scrollDirection: Axis.vertical,
              itemCount: seriesList.length,
              onPageChanged: (index) => _handlePageChange(index, _futureSeries),
              itemBuilder: (context, index) {
                final series = seriesList[index];
                final hasEpisodes = series.episodes.isNotEmpty;
                final isCurrentPage = index == _currentPageIndex;
                final episodeId = hasEpisodes ? series.episodes.first.id : 0;
                final isLiked = _likedStatus[episodeId] ?? false;
                final likesCount = _likesCount[episodeId] ?? 0;
                final isPlaying = _isVideoPlaying[index] ?? false;
                final isInitialized = _isVideoInitialized[index] ?? false;
                final episodeCount = series.episodes.length;

                return Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_videoControllers.containsKey(index))
                      Padding(
                        padding: const EdgeInsets.only(
                          top: 0,
                          bottom: 22,
                        ), // ارتفاع عن الأسفل
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: ClipRRect(
                            borderRadius: const BorderRadius.only(
                              bottomLeft: Radius.circular(10),
                              bottomRight: Radius.circular(10),
                            ),
                            child: SizedBox(
                              width: MediaQuery.of(context).size.width,
                              height: MediaQuery.of(context).size.height,
                              child: Stack(
                                children: [
                                  if (_showThumbnail[index] == true &&
                                      series.imageUrl.isNotEmpty)
                                    CachedNetworkImage(
                                      imageUrl: series.imageUrl,
                                      width: double.infinity,
                                      height: double.infinity,
                                      fit: BoxFit.cover,
                                      placeholder: (context, url) =>
                                          Container(color: Colors.grey[900]),
                                      errorWidget: (context, url, error) =>
                                          Container(color: Colors.grey[900]),
                                    ),
                                  if (isInitialized)
                                    AspectRatio(
                                      aspectRatio: _videoControllers[index]!
                                          .value
                                          .aspectRatio,
                                      child: VideoPlayer(
                                        _videoControllers[index]!,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      )
                    else if (series.imageUrl.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: CachedNetworkImage(
                            imageUrl: series.imageUrl,
                            width: double.infinity,
                            height: double.infinity,
                            fit: BoxFit.cover,
                            placeholder: (context, url) =>
                                Container(color: Colors.grey[900]),
                            errorWidget: (context, url, error) =>
                                Container(color: Colors.grey[900]),
                          ),
                        ),
                      ),

                    if (isCurrentPage && _showControls)
                      Positioned(
                        bottom: 10,
                        left: 0,
                        right: 0,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                          child: _buildTikTokProgressBar(index),
                        ),
                      ),

                    if (isCurrentPage && isInitialized && _showControls)
                      Center(
                        child: GestureDetector(
                          onTap: () => _togglePlayPause(index),
                          child: AnimatedOpacity(
                            opacity: _showControls ? 1.0 : 0.0,
                            duration: const Duration(milliseconds: 200),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.5),
                                shape: BoxShape.circle,
                              ),
                              padding: const EdgeInsets.all(20),
                              child: Icon(
                                isPlaying ? Icons.pause : Icons.play_arrow,
                                size: 50,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),

                    if (index == 0 && !_firstVideoReady)
                      const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(
                              color: Colors.red,
                              strokeWidth: 2,
                            ),
                            SizedBox(height: 20),
                            Text(
                              'جاري تحميل الفيديو...',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),

                    Positioned(
                      bottom: 20,
                      left: 16,
                      right: 16,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            series.title,
                            style: const TextStyle(
                              fontSize: 20,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),

                    Positioned(
                      bottom: 60,
                      right: 30,
                      left: 100,
                      child: GestureDetector(
                        onTap: () async {
                          if (hasEpisodes) {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => TVseriesplayer(
                                  episodes: series.episodes,
                                  initialIndex: 0,
                                  seriesId: series.id,
                                  seriesTitle: series.title,
                                  seriesImageUrl: series.imageUrl,
                                ),
                              ),
                            );
                            if (mounted) setState(() {});
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          decoration: BoxDecoration(
                            color: Colors.grey.withOpacity(0.8),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Center(
                            child: Text(
                              'شاهد الآن',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    Positioned(
                      bottom: 170,
                      left: 12,
                      child: Column(
                        children: [
                          GestureDetector(
                            onTap: () => hasEpisodes
                                ? _toggleLike(series.episodes.first.id)
                                : null,
                            child: _isLikeLoading && hasEpisodes
                                ? const SizedBox(
                                    width: 50,
                                    height: 50,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : ScaleTransition(
                                    scale: Tween<double>(begin: 0.8, end: 1.2)
                                        .animate(
                                          CurvedAnimation(
                                            parent: _likeAnimationController,
                                            curve: Curves.easeOut,
                                          ),
                                        ),
                                    child: Image.asset(
                                      isLiked
                                          ? 'assets/images/icon_item_video_like.webp'
                                          : 'assets/images/icon_item_video_like_none.webp',
                                      width: 50,
                                      height: 50,
                                    ),
                                  ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            formatNumber(likesCount, arabic: true),
                            style: const TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    ),

                    Positioned(
                      bottom: 100,
                      left: 12,
                      child: GestureDetector(
                        onTap: () async {
                          if (hasEpisodes) {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => TVseriesplayer(
                                  episodes: series.episodes,
                                  initialIndex: 0,
                                  seriesId: series.id,
                                  seriesTitle: series.title,
                                  seriesImageUrl: series.imageUrl,
                                ),
                              ),
                            );
                            if (mounted) setState(() {});
                          }
                        },
                        child: Column(
                          children: [
                            Image.asset(
                              'assets/images/icon_hall_chapter.webp',
                              width: 45,
                              height: 45,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$episodeCount حلقات',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    Positioned(
                      bottom: 20,
                      left: 8,
                      child: GestureDetector(
                        onTap: _showSettingsSheet,
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
                                width: 45,
                                height: 45,
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'المزيد',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }
}
