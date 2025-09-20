import 'package:dramix/models/episode.dart';

class Series {
  final int id;
  final String title;
  final String imageUrl;
  final int episodeCount;
  final bool isFeatured;
  final List<Episode> episodes;
  final int totalViews; // إضافة حقل المشاهدات الإجمالية
  final int totalLikes; // إضافة حقل الإعجابات الإجمالية

  Series({
    required this.id,
    required this.title,
    required this.imageUrl,
    required this.episodeCount,
    this.isFeatured = false,
    required this.episodes,
    required this.totalViews, // مطلوب الآن
    required this.totalLikes, // مطلوب الآن
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'imageUrl': imageUrl,
      'episode_count': episodeCount,
      'is_featured': isFeatured,
      'total_views': totalViews,
      'total_likes': totalLikes,
      'episodes': episodes.map((e) => e.toJson()).toList(),
    };
  }

factory Series.fromJson(Map<String, dynamic> json) {
  var episodesList = json['episodes'] ?? [];
  List<Episode> episodesFromJson = [];
  if (episodesList is List) {
    episodesFromJson = episodesList.map((e) => Episode.fromJson(e)).toList();
  }

  return Series(
    id: int.parse((json['id'] ?? json['series_id']).toString()),
    title: json['title'] ?? 'No Title',
    imageUrl: json['imageUrl'] ?? json['imageName'] ?? '',
    episodeCount: int.tryParse(json['episode_count'].toString()) ?? episodesFromJson.length,
   isFeatured: json['isFeatured'] ?? false,

    totalViews: int.tryParse(json['total_views'].toString()) ?? 0,
    totalLikes: int.tryParse(json['total_likes'].toString()) ?? 0,
    episodes: episodesFromJson,
  );
}


  static Series empty() {
    return Series(
      id: 0,
      title: '',
      imageUrl: '',
      episodeCount: 0,
      episodes: [],
      totalViews: 0,
      totalLikes: 0,
    );
  }
}