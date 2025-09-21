// screens/MyListScreen.dart
import 'package:dramix/main.dart';
import 'package:dramix/models/WatchHistoryService.dart';
import 'package:dramix/screens/TVseriesplayer.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../models/WatchedSeries.dart';
import '../services/api_service.dart';
import 'package:provider/provider.dart';

class MyListScreen extends StatefulWidget {
  const MyListScreen({super.key});

  @override
  State<MyListScreen> createState() => _MyListScreenState();
}

class _MyListScreenState extends State<MyListScreen> {
  final WatchHistoryService _watchHistoryService = WatchHistoryService();
  List<WatchedSeries> _watchedSeries = [];
  bool _isLoading = true;
  // no ad-control flags here by user request

  @override
  void initState() {
    super.initState();
    checkPackageName();
    _loadWatchHistory();
  }

  // ad control removed as requested

  Future<void> _loadWatchHistory() async {
    setState(() => _isLoading = true);
    try {
      final history = await _watchHistoryService.getWatchHistory();
      history.sort((a, b) => b.lastWatchedAt.compareTo(a.lastWatchedAt));
      setState(() {
        _watchedSeries = history;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _removeSeries(int seriesId) async {
    await _watchHistoryService.removeFromHistory(seriesId);
    await _loadWatchHistory();
  }

  Future<void> _continueWatching(WatchedSeries series) async {
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final episodes = await apiService.getEpisodesBySeries(series.seriesId);

      if (episodes.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('لا توجد حلقات متاحة')));
        return;
      }

      int initialIndex = 0;
      for (int i = 0; i < episodes.length; i++) {
        if (episodes[i].episodeNumber == series.lastWatchedEpisode) {
          initialIndex = i;
          break;
        }
      }

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TVseriesplayer(
            episodes: episodes,
            initialIndex: initialIndex,
            seriesId: series.seriesId,
            seriesTitle: series.title,
            seriesImageUrl: series.imageUrl,
          ),
        ),
      );

      await _loadWatchHistory();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ في تحميل المسلسل: ${e.toString()}')),
      );
    }
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history, size: 80, color: Colors.grey[600]),
          const SizedBox(height: 20),
          const Text(
            'لا توجد مسلسلات في قائمتك',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'المسلسلات التي تشاهدها ستظهر هنا تلقائياً',
            style: TextStyle(color: Colors.grey, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatDate(DateTime date) {
    return DateFormat('MMM dd').format(date);
  }

  Widget _buildSeriesGridItem(WatchedSeries series) {
    // modern card with overlay resume button and progress
    return Card(
      color: const Color(0xFF141414),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 6,
      child: InkWell(
        onTap: () => _continueWatching(series),
        onLongPress: () => _showDeleteDialog(series.seriesId),
        borderRadius: BorderRadius.circular(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 6,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(14),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                      imageUrl: series.thumbnailUrl.isNotEmpty
                          ? series.thumbnailUrl
                          : series.imageUrl,
                      fit: BoxFit.cover,
                      placeholder: (c, u) => Container(color: Colors.grey[900]),
                      errorWidget: (c, u, e) => Container(
                        color: Colors.grey[900],
                        child: const Icon(Icons.movie, color: Colors.white),
                      ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            Colors.black.withOpacity(0.6),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                    // (play button removed — tap card to open series)
                    // small progress bar
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: LinearProgressIndicator(
                        value: series.progress.clamp(0.0, 1.0),
                        backgroundColor: Colors.black.withOpacity(0.4),
                        valueColor: const AlwaysStoppedAnimation(
                          Color(0xFFFF078F),
                        ),
                        minHeight: 4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      series.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.movie,
                              size: 14,
                              color: Colors.grey,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'حلقة ${series.lastWatchedEpisode}',
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        Text(
                          '/${series.totalEpisodes}',
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (series.lastPosition.inSeconds > 0) ...[
                          const Icon(
                            Icons.access_time,
                            size: 12,
                            color: Color(0xFFFF078F),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _formatDuration(series.lastPosition),
                            style: const TextStyle(
                              color: Color(0xFFFF078F),
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                        const Spacer(),
                        Text(
                          _formatDate(series.lastWatchedAt),
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteDialog(int seriesId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'إزالة من القائمة',
          style: TextStyle(color: Colors.white, fontSize: 18),
        ),
        content: const Text(
          'هل تريد إزالة هذا المسلسل من قائمتك؟',
          style: TextStyle(color: Colors.grey, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء', style: TextStyle(color: Colors.white)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _removeSeries(seriesId);
            },
            child: const Text('إزالة', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _clearAllHistory() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'مسح كل المحتوى',
          style: TextStyle(color: Colors.white, fontSize: 18),
        ),
        content: const Text(
          'هل تريد مسح كل المسلسلات من قائمتك؟',
          style: TextStyle(color: Colors.grey, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء', style: TextStyle(color: Colors.white)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('مسح الكل', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _watchHistoryService.clearHistory();
      await _loadWatchHistory();
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final crossAxisCount = screenWidth > 600 ? 3 : 2;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text(
          'قائمتي',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_watchedSeries.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep, size: 24),
              onPressed: _clearAllHistory,
              tooltip: 'مسح الكل',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: Color(0xFFFF078F),
                strokeWidth: 3,
              ),
            )
          : _watchedSeries.isEmpty
          ? _buildEmptyState()
          : Column(
              children: [
                // no ad banner — tapping an item opens the series directly
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _loadWatchHistory,
                    color: const Color(0xFFFF078F),
                    backgroundColor: Colors.black,
                    child: GridView.builder(
                      padding: const EdgeInsets.all(8),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 12,
                        childAspectRatio: 0.65, // تم تعديل النسبة
                      ),
                      itemCount: _watchedSeries.length,
                      itemBuilder: (context, index) {
                        return _buildSeriesGridItem(_watchedSeries[index]);
                      },
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  // ads control removed per user request
}
