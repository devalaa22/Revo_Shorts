import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/video_preloader.dart';
import 'package:dramix/models/WatchHistoryService.dart';
import 'package:dramix/models/WatchedSeries.dart';
import 'package:dramix/screens/TVseriesplayer.dart';
import 'package:dramix/utils/fcm_notification_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import '../models/series.dart';
import '../services/api_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Series> _allSeries = [];
  List<Series> _displayedSeries = [];
  List<Series> featuredSeries = [];
  final TextEditingController searchController = TextEditingController();
  bool isSearching = false;
  bool isNavigating = false;
  bool isLoading = false;
  bool isLoadingMore = false;
  final PageController _pageController = PageController(viewportFraction: 0.85);
  int _currentPage = 0;
  Timer? _autoScrollTimer;
  final String _layoutMode = '3-up';
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _refreshKey = GlobalKey();
  late final VideoPreloader _videoPreloader;

  // Pagination variables
  int _currentPageNumber = 1;
  final int _itemsPerPage = 12;
  bool _hasMoreData = true;

  @override
  void initState() {
    super.initState();
    _videoPreloader = VideoPreloader();
    _loadInitialData();
    _startAutoScroll();
    NotificationService.init();
    _scrollController.addListener(_scrollListener);

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint("🔗 فتح من الإشعار: ${message.data}");
    });
  }

  void _scrollListener() {
    if (_scrollController.position.pixels ==
            _scrollController.position.maxScrollExtent &&
        !isLoadingMore &&
        _hasMoreData &&
        !isSearching) {
      _loadMoreData();
    }
  }

  Future<void> _loadInitialData() async {
    if (isLoading) return;

    setState(() {
      isLoading = true;
      _currentPageNumber = 1;
      _hasMoreData = true;
    });

    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final series = await apiService.getAllSeries();

      if (mounted) {
        setState(() {
          _allSeries = series;
          _displayedSeries = _paginateSeries(series, _currentPageNumber);
          featuredSeries = series.where((s) => s.isFeatured).toList();
          if (featuredSeries.isEmpty && series.isNotEmpty) {
            featuredSeries = series.length > 5
                ? series.sublist(0, 5)
                : List.from(series);
          }
          isLoading = false;
          _hasMoreData = series.length > _currentPageNumber * _itemsPerPage;
        });
        // Precache images for faster UI
        try {
          for (final s in featuredSeries) {
            precacheImage(
              CachedNetworkImageProvider(
                _getOptimizedImageUrl(s.imageUrl, isSlider: true),
              ),
              context,
            );
          }
          for (final s in _displayedSeries) {
            precacheImage(
              CachedNetworkImageProvider(_getOptimizedImageUrl(s.imageUrl)),
              context,
            );
          }
        } catch (e) {
          debugPrint('Image precache failed: $e');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load data: ${e.toString()}')),
        );
      }
    }
  }

  List<Series> _paginateSeries(List<Series> series, int page) {
    final startIndex = (page - 1) * _itemsPerPage;
    if (startIndex >= series.length) return [];

    final endIndex = startIndex + _itemsPerPage;
    return series.sublist(
      startIndex,
      endIndex > series.length ? series.length : endIndex,
    );
  }

  Future<void> _loadMoreData() async {
    if (isLoadingMore || !_hasMoreData) return;

    setState(() => isLoadingMore = true);

    await Future.delayed(const Duration(milliseconds: 500));

    try {
      final nextPage = _currentPageNumber + 1;
      final newItems = _paginateSeries(_allSeries, nextPage);

      if (newItems.isEmpty) {
        setState(() {
          _hasMoreData = false;
          isLoadingMore = false;
        });
        return;
      }

      setState(() {
        _displayedSeries.addAll(newItems);
        _currentPageNumber = nextPage;
        isLoadingMore = false;
        _hasMoreData = _allSeries.length > _displayedSeries.length;
      });
    } catch (e) {
      setState(() => isLoadingMore = false);
      debugPrint('Error loading more data: $e');
    }
  }

  Future<void> _refreshData() async {
    setState(() {
      isLoading = true;
      _currentPageNumber = 1;
      _hasMoreData = true;
    });

    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final series = await apiService.getAllSeries();

      if (mounted) {
        setState(() {
          _allSeries = series;
          _displayedSeries = _paginateSeries(series, _currentPageNumber);
          featuredSeries = series.where((s) => s.isFeatured).toList();
          if (featuredSeries.isEmpty && series.isNotEmpty) {
            featuredSeries = series.length > 5
                ? series.sublist(0, 5)
                : List.from(series);
          }
          isLoading = false;
          _hasMoreData = series.length > _displayedSeries.length;
        });
      }
    } catch (e) {
      if (mounted) setState(() => isLoading = false);
      debugPrint('Error refreshing data: $e');
    }
  }

  void _startAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (mounted && featuredSeries.isNotEmpty) {
        int nextPage = _currentPage + 1;
        if (nextPage >= featuredSeries.length) nextPage = 0;
        _pageController.animateToPage(
          nextPage,
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  void _onSearch(String query) {
    setState(() {
      isSearching = query.isNotEmpty;
      if (isSearching) {
        _displayedSeries = _allSeries
            .where((s) => s.title.toLowerCase().contains(query.toLowerCase()))
            .toList();
      } else {
        _displayedSeries = _paginateSeries(_allSeries, _currentPageNumber);
        _hasMoreData = _allSeries.length > _displayedSeries.length;
      }
    });
  }

  Future<void> _navigateToSeriesPlayer(Series series) async {
    if (isNavigating) return;
    setState(() => isNavigating = true);
    await _saveToWatchHistory(series);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => WillPopScope(
        onWillPop: () async => false,
        child: Center(
          child: Container(
            width: 75,
            height: 75,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.8),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Lottie.asset(
              'assets/animations/load-house.json',
              width: 75,
              height: 75,
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );

    try {
      final episodes = await Provider.of<ApiService>(
        context,
        listen: false,
      ).getEpisodesBySeries(series.id);

      if (!mounted) return;

      // Prefetch first episode video to cache; wait briefly (max 1.2s) so player can often open from file
      if (episodes.isNotEmpty) {
        final firstUrl = episodes.first.videoUrl;
        try {
          final fileFuture = _videoPreloader.fetchToCache(firstUrl);
          final file = await fileFuture.timeout(
            const Duration(milliseconds: 1200),
            onTimeout: () => null,
          );
          if (file != null) {
            debugPrint(
              'HomeScreen: prefetched video for series ${series.id} -> ${file.path}',
            );
          } else {
            // didn't finish in time; let background fetch continue
            fileFuture
                .then((f) {
                  debugPrint(
                    'HomeScreen: background prefetch done for series ${series.id} -> ${f?.path}',
                  );
                  return f;
                })
                .catchError((e) {
                  debugPrint('HomeScreen: background prefetch failed: $e');
                  return null;
                });
          }
        } catch (e) {
          debugPrint('HomeScreen: prefetch video failed: $e');
        }
      }

      Navigator.of(context, rootNavigator: true).pop();

      if (episodes.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No episodes available for this series'),
          ),
        );
        return;
      }

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TVseriesplayer(
            episodes: episodes,
            initialIndex: 0,
            seriesId: series.id,
            seriesTitle: series.title,
            seriesImageUrl: series.imageUrl,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        // Ensure loader dialog is closed and show error
        try {
          Navigator.of(context, rootNavigator: true).pop();
        } catch (_) {}
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Error loading episodes')));
      }
    } finally {
      if (mounted) setState(() => isNavigating = false);
    }
  }

  Future<void> _saveToWatchHistory(Series series) async {
    try {
      final watchHistoryService = WatchHistoryService();

      final existing = await watchHistoryService.getWatchHistory();
      final found = existing.firstWhere(
        (w) => w.seriesId == series.id,
        orElse: () => WatchedSeries(
          seriesId: -1,
          title: '',
          imageUrl: '',
          thumbnailUrl: '',
          lastWatchedEpisode: 0,
          totalEpisodes: 0,
          lastWatchedAt: DateTime.fromMillisecondsSinceEpoch(0),
          progress: 0.0,
          lastPosition: Duration.zero,
        ),
      );

      if (found.seriesId == -1) {
        // no existing history - add a placeholder entry so it appears in My List
        final watchedSeries = WatchedSeries(
          seriesId: series.id,
          title: series.title,
          imageUrl: series.imageUrl,
          thumbnailUrl: '',
          lastWatchedEpisode: 1,
          totalEpisodes: series.episodeCount,
          lastWatchedAt: DateTime.now(),
          progress: 0.0,
          lastPosition: Duration.zero,
        );
        await watchHistoryService.saveWatchedSeries(watchedSeries);
      } else {
        // update timestamp only to bring it to top without resetting progress
        final updated = WatchedSeries(
          seriesId: found.seriesId,
          title: found.title.isNotEmpty ? found.title : series.title,
          imageUrl: found.imageUrl.isNotEmpty
              ? found.imageUrl
              : series.imageUrl,
          thumbnailUrl: found.thumbnailUrl,
          lastWatchedEpisode: found.lastWatchedEpisode,
          totalEpisodes: found.totalEpisodes > 0
              ? found.totalEpisodes
              : series.episodeCount,
          lastWatchedAt: DateTime.now(),
          progress: found.progress,
          lastPosition: found.lastPosition,
        );
        await watchHistoryService.saveWatchedSeries(updated);
      }
    } catch (e) {
      debugPrint('Error saving to watch history: $e');
    }
  }

  Widget _buildShimmerEffect() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[800]!,
      highlightColor: Colors.grey[700]!,
      child: Column(
        children: [
          SizedBox(
            height: 400,
            child: PageView.builder(
              itemCount: 3,
              itemBuilder: (context, index) {
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            itemCount: 6,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 0.7,
            ),
            itemBuilder: (context, index) {
              return Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(15),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildNoContentWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.movie_filter,
            size: 80,
            color: Colors.white.withOpacity(0.5),
          ),
          const SizedBox(height: 20),
          Text(
            isSearching ? 'No results found' : 'No content available',
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 10),
          if (!isSearching)
            TextButton(
              onPressed: _refreshData,
              child: const Text(
                'Refresh',
                style: TextStyle(color: Colors.blue),
              ),
            ),
        ],
      ),
    );
  }

  String _getOptimizedImageUrl(
    String originalUrl, {
    bool isSlider = false,
    int? width,
    int? quality,
  }) {
    final defaultWidth = isSlider ? 600 : 400;
    final w = width ?? defaultWidth;
    final q = quality ?? (isSlider ? 80 : 70);
    if (originalUrl.contains('?')) {
      return '$originalUrl&width=$w&quality=$q';
    }
    return '$originalUrl?width=$w&quality=$q';
  }

  int _desiredImageWidth(BuildContext context, {bool isSlider = false}) {
    final mq = MediaQuery.of(context);
    final dpr = mq.devicePixelRatio;
    final screenW = mq.size.width;
    if (isSlider) {
      final logicalWidth = screenW * 0.85; // matches viewportFraction
      return (logicalWidth * dpr).clamp(400, 2000).toInt();
    }
    final columns = _layoutMode == '3-up' ? 3 : (_layoutMode == '2-up' ? 2 : 1);
    // approximate paddings used around grid
    final horizontalPadding = 24.0 + (columns - 1) * 12.0;
    final logicalWidth = (screenW - horizontalPadding) / columns;
    return (logicalWidth * dpr).clamp(320, 1600).toInt();
  }

  Widget _buildFeaturedSliderItem(Series series, int index) {
    return GestureDetector(
      onTap: () => _navigateToSeriesPlayer(series),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(25),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 20,
              spreadRadius: 2,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(25),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CachedNetworkImage(
                imageUrl: _getOptimizedImageUrl(
                  series.imageUrl,
                  isSlider: true,
                ),
                fit: BoxFit.cover,
                placeholder: (context, url) =>
                    Container(color: Colors.grey[900]),
                errorWidget: (context, url, error) => Container(
                  color: Colors.grey[900],
                  child: const Icon(Icons.error, color: Colors.white),
                ),
              ),

              if (series.isFeatured)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color.fromARGB(255, 255, 5, 5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'رائج',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withOpacity(0.9),
                      Colors.transparent,
                      Colors.transparent,
                      Colors.black.withOpacity(0.3),
                    ],
                    stops: const [0.0, 0.4, 0.7, 1.0],
                  ),
                ),
              ),

              Positioned(
                bottom: 20,
                left: 20,
                right: 20,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      series.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        shadows: [
                          Shadow(
                            blurRadius: 10,
                            color: Colors.black,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _buildInfoChip(
                          Icons.play_circle_fill,
                          '${series.episodeCount} حلقة',
                        ),
                        const SizedBox(width: 8),
                        _buildInfoChip(
                          Icons.visibility,
                          '${_formatNumber(series.totalViews)} مشاهدة',
                        ),
                        const SizedBox(width: 8),
                        _buildInfoChip(
                          Icons.favorite,
                          '${_formatNumber(series.totalLikes)} إعجاب',
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color.fromARGB(255, 255, 8, 8),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(
                        child: Text(
                          'مشاهدة الآن',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 14),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(color: Colors.white, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildSeriesGridItem(Series series) {
    return GestureDetector(
      onTap: () => _navigateToSeriesPlayer(series),
      child: Container(
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: const Color(0xFF1A1A1A),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Series Image
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
              child: Stack(
                children: [
                  // Request a higher-res thumbnail for larger layouts to avoid pixelation
                  CachedNetworkImage(
                    imageUrl: _getOptimizedImageUrl(
                      series.imageUrl,
                      isSlider: false,
                      width: _desiredImageWidth(context, isSlider: false),
                      quality: 80,
                    ),
                    width: double.infinity,
                    height: 180,
                    fit: BoxFit.cover,
                    fadeInDuration: const Duration(milliseconds: 300),
                    placeholder: (context, url) => SizedBox(
                      height: 180,
                      child: Shimmer.fromColors(
                        baseColor: Colors.grey[850]!,
                        highlightColor: Colors.grey[800]!,
                        child: Container(color: Colors.grey[900]),
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                      color: Colors.grey[900],
                      height: 180,
                      child: const Icon(Icons.error, color: Colors.white),
                    ),
                  ),

                  // Gradient overlay
                  Container(
                    height: 180,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withOpacity(0.7),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),

                  // Featured badge
                  if (series.isFeatured)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.pink,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'مميز',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Series Info
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    series.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign:
                        TextAlign.center, // 🔥 مهم يخلي الأسطر كلها بالوسط
                  ),

                  const SizedBox(height: 8),

                  // Stats Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildStatItem(
                        Icons.play_circle,
                        '${series.episodeCount}',
                      ),
                      _buildStatItem(
                        Icons.visibility,
                        _formatNumber(series.totalViews),
                      ),
                      _buildStatItem(
                        Icons.favorite,
                        _formatNumber(series.totalLikes),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String value) {
    return Row(
      children: [
        Icon(icon, color: Colors.grey, size: 14),
        const SizedBox(width: 4),
        Text(value, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      ],
    );
  }

  String _formatNumber(int number) {
    if (number >= 1000000) {
      return '${(number / 1000000).toStringAsFixed(1)}M';
    } else if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(1)}K';
    }
    return number.toString();
  }

  Widget _buildLoadingMoreIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24.0),
      child: Center(
        child: CircularProgressIndicator(color: Colors.pink, strokeWidth: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final seriesList = isSearching ? _displayedSeries : _displayedSeries;

    return Scaffold(
      backgroundColor: Colors.black,
      body: NotificationListener<ScrollNotification>(
        onNotification: (scrollNotification) {
          if (scrollNotification is ScrollEndNotification) {
            _startAutoScroll();
          } else if (scrollNotification is ScrollUpdateNotification) {
            _autoScrollTimer?.cancel();
          }
          return false;
        },
        child: RefreshIndicator(
          key: _refreshKey,
          onRefresh: _refreshData,
          color: Colors.pink,
          backgroundColor: Colors.black,
          displacement: 40,
          child: CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // App Bar with search
              SliverAppBar(
                backgroundColor: Colors.black,
                pinned: true,
                floating: true,
                expandedHeight: 0,
                toolbarHeight: 70,
                title: Container(
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(25),
                    border: Border.all(color: Colors.white.withOpacity(0.2)),
                  ),
                  child: TextField(
                    controller: searchController,
                    onChanged: _onSearch,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search, color: Colors.white54),
                      hintText: 'ابحث عن مسلسل...',
                      hintStyle: TextStyle(color: Colors.white54),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ),

              // Featured Slider Section
              SliverToBoxAdapter(
                child: isLoading
                    ? _buildShimmerEffect()
                    : featuredSeries.isNotEmpty
                    ? Column(
                        children: [
                          const SizedBox(height: 10),
                          SizedBox(
                            height: 400,
                            child: PageView.builder(
                              controller: _pageController,
                              itemCount: featuredSeries.length,
                              onPageChanged: (index) {
                                setState(() => _currentPage = index);
                              },
                              itemBuilder: (context, index) {
                                return _buildFeaturedSliderItem(
                                  featuredSeries[index],
                                  index,
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 15),
                          SmoothPageIndicator(
                            controller: _pageController,
                            count: featuredSeries.length,
                            effect: const ExpandingDotsEffect(
                              dotHeight: 8,
                              dotWidth: 8,
                              activeDotColor: Colors.pink,
                              dotColor: Colors.white54,
                              expansionFactor: 3,
                            ),
                          ),
                          const SizedBox(height: 25),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 20),
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: Text(
                                'المسلسلات المميزة',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 15),
                        ],
                      )
                    : Container(),
              ),

              // All Series Grid
              SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 0.65,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index < seriesList.length) {
                      return _buildSeriesGridItem(seriesList[index]);
                    } else if (_hasMoreData && !isSearching) {
                      return _buildLoadingMoreIndicator();
                    } else {
                      return Container();
                    }
                  },
                  childCount:
                      seriesList.length +
                      (_hasMoreData && !isSearching ? 1 : 0),
                ),
              ),

              if (seriesList.isEmpty && !isLoading)
                SliverFillRemaining(child: _buildNoContentWidget()),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _pageController.dispose();
    _scrollController.dispose();
    searchController.dispose();
    super.dispose();
  }
}
