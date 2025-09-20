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

  @override
  void initState() {
    super.initState();
    checkPackageName();
    _loadWatchHistory();
  }

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
          builder: (_) =>
              TVseriesplayer(episodes: episodes, initialIndex: initialIndex),
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
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.grey[800]!, width: 1),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _continueWatching(series),
          borderRadius: BorderRadius.circular(16),
          onLongPress: () => _showDeleteDialog(series.seriesId),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // صورة المسلسل
              AspectRatio(
                aspectRatio: 0.68,
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                  child: Container(
                    color: Colors.grey[900],
                    child: Stack(
                      children: [
                        // صورة الخلفية
                        CachedNetworkImage(
                          imageUrl: series.thumbnailUrl.isNotEmpty
                              ? series.thumbnailUrl
                              : series.imageUrl,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          placeholder: (context, url) => Container(
                            color: Colors.grey[900],
                            child: const Center(
                              child: CircularProgressIndicator(
                                color: Color(0xFFFF078F),
                                strokeWidth: 2,
                              ),
                            ),
                          ),
                          errorWidget: (context, url, error) => Container(
                            color: Colors.grey[900],
                            child: const Icon(
                              Icons.movie,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),

                        // تدرج لوني للخلفية
                        Container(
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

                        // شريط التقدم في الأسفل
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: Container(
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.grey[800],
                              borderRadius: const BorderRadius.vertical(
                                bottom: Radius.circular(16),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: (series.progress * 100).round(),
                                  child: Container(
                                    decoration: const BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          Color(0xFFFF078F),
                                          Color(0xFFD6006F),
                                        ],
                                      ),
                                      borderRadius: BorderRadius.vertical(
                                        bottom: Radius.circular(16),
                                      ),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 100 - (series.progress * 100).round(),
                                  child: const SizedBox(),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // النسبة المئوية في الزاوية
                        Positioned(
                          top: 8,
                          left: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.8),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${(series.progress * 100).toStringAsFixed(0)}%',
                              style: const TextStyle(
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
                ),
              ),

              // معلومات المسلسل
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,

                  children: [
                    // عنوان المسلسل
                    Text(
                      series.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),

                    const SizedBox(height: 8),

                    // معلومات الحلقة
                    Row(
                      children: [
                        // رقم الحلقة
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.movie,
                              size: 14,
                              color: Colors.grey,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'الحلقة ${series.lastWatchedEpisode}',
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),

                        const Spacer(),

                        // عدد الحلقات
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

                    // وقت التوقف و التاريخ
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (series.lastPosition.inSeconds > 0)
                          Row(
                            children: [
                              const Icon(
                                Icons.access_time,
                                size: 12,
                                color: Color(0xFFFF078F),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'التوقف: ${_formatDuration(series.lastPosition)}',
                                style: const TextStyle(
                                  color: Color(0xFFFF078F),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),

                        const SizedBox(height: 4),

                        Row(
                          children: [
                            const Icon(
                              Icons.calendar_today,
                              size: 12,
                              color: Colors.grey,
                            ),
                            const SizedBox(width: 4),
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
                  ],
                ),
              ),
            ],
          ),
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
          : RefreshIndicator(
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
    );
  }
}
