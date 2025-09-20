// models/WatchedSeries.dart
class WatchedSeries {
  final int seriesId;
  final String title;
  final String imageUrl;
  final String thumbnailUrl;
  final int lastWatchedEpisode;
  final int totalEpisodes;
  final DateTime lastWatchedAt;
  final double progress;
  final Duration lastPosition;

  WatchedSeries({
    required this.seriesId,
    required this.title,
    required this.imageUrl,
    required this.thumbnailUrl,
    required this.lastWatchedEpisode,
    required this.totalEpisodes,
    required this.lastWatchedAt,
    required this.progress,
    required this.lastPosition,
  });

  Map<String, dynamic> toJson() {
    return {
      'series_id': seriesId,
      'title': title,
      'image_url': imageUrl,
      'thumbnail_url': thumbnailUrl,
      'last_watched_episode': lastWatchedEpisode,
      'total_episodes': totalEpisodes,
      'last_watched_at': lastWatchedAt.toIso8601String(),
      'progress': progress,
      'last_position': lastPosition.inMilliseconds,
    };
  }

  factory WatchedSeries.fromJson(Map<String, dynamic> json) {
    return WatchedSeries(
      seriesId: json['series_id'],
      title: json['title'],
      imageUrl: json['image_url'],
      thumbnailUrl: json['thumbnail_url'] ?? '',
      lastWatchedEpisode: json['last_watched_episode'],
      totalEpisodes: json['total_episodes'],
      lastWatchedAt: DateTime.parse(json['last_watched_at']),
      progress: json['progress']?.toDouble() ?? 0.0,
      lastPosition: Duration(milliseconds: json['last_position'] ?? 0),
    );
  }
}
