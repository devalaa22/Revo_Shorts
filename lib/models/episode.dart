class Episode {
  final int id;
  final String title;
  final int episodeNumber;
  final String videoUrl;
  final int  priceCoins;
  bool isLocked;
  int likeCount;
  int viewCount;
  String? thumbnailPath;
  bool isLiked; // حالة الإعجاب
  Episode({
    required this.id,
    required this.title,
    required this.episodeNumber,
    required this.videoUrl,
    required this.isLocked,
    this.likeCount = 0,
    this.viewCount = 0,
    this.thumbnailPath,
    this.isLiked = false,
    required this.priceCoins,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'episode_number': episodeNumber,
      'videoUrl': videoUrl,
      'isLocked': isLocked,
      'like_count': likeCount,
      'view_count': viewCount,
      'thumbnailPath': thumbnailPath,
       'priceCoins': priceCoins,
      'isLiked': isLiked,
    };
  }

  factory Episode.fromJson(Map<String, dynamic> json) {
    return Episode(
      id: int.parse(json['id'].toString()),
      title: json['title'] ?? 'Episode ${json['episode_number']}',
      episodeNumber: int.tryParse(json['episode_number'].toString()) ?? 0,
      priceCoins: int.tryParse(json['priceCoins'].toString()) ?? 0,
      videoUrl: json['videoUrl'] ?? json['video_path'] ?? '',
      isLocked: json['isLocked'] == true || json['isLocked'] == 'true',
      likeCount: int.tryParse(json['like_count'].toString()) ?? 0,
      viewCount: int.tryParse(json['view_count'].toString()) ?? 0,
      thumbnailPath: json['thumbnailPath'],
      isLiked: json['isLiked'] ?? false,
    );
  }
}
