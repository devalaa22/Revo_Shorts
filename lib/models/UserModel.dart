class User {
  final String id;
  final String name;
  final String email;
  final String? photoUrl;
  final int coins;
  final bool isVip;
  final String? vipExpiry;

  User({
    required this.id,
    required this.name,
    required this.email,
    this.photoUrl,
    required this.coins,
    this.isVip = false,
    this.vipExpiry,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      photoUrl: json['photo_url']?.toString(),
      coins: int.tryParse(json['coins']?.toString() ?? '0') ?? 0,
      isVip: json['is_vip'] == true || json['is_vip'] == 1,
      vipExpiry: json['vip_expiry']?.toString(),
    );
  }

  User copyWith({
    String? id,
    String? name,
    String? email,
    String? photoUrl,
    int? coins,
    bool? isVip,
    String? vipExpiry,
  }) {
    return User(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      photoUrl: photoUrl ?? this.photoUrl,
      coins: coins ?? this.coins,
      isVip: isVip ?? this.isVip,
      vipExpiry: vipExpiry ?? this.vipExpiry,
    );
  }
}
