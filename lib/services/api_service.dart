import 'dart:convert';
import 'package:dramix/services/ApiEndpoints.dart';
import 'package:dramix/services/auth_service.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/series.dart';
import '../models/episode.dart';

class ApiService {
  final AuthService _authService = AuthService();

  Future<Map<String, dynamic>> _authenticatedRequest({
    required String endpoint,
    String method = 'GET',
    Map<String, dynamic>? body,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');

      final headers = {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

      final url = Uri.parse(endpoint);
      http.Response response;

      if (method == 'GET') {
        response = await http.get(url, headers: headers);
      } else if (method == 'POST') {
        response = await http.post(
          url,
          headers: headers,
          body: json.encode(body),
        );
      } else {
        throw Exception('HTTP method not supported');
      }

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else if (response.statusCode == 401) {
        await _authService.isSignedIn();
        throw Exception('انتهت الجلسة، يرجى تسجيل الدخول مرة أخرى');
      } else {
        throw Exception('Request failed: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('API request error: $e');
      rethrow;
    }
  }


Future<Map<String, dynamic>> getAppMode() async {
  try {
    final response = await http.get(Uri.parse('${ApiEndpoints.baseUrl2}/app_config.php'));
    
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      return {'status': 'error', 'message': 'فشل جلب وضع التطبيق'};
    }
  } catch (e) {
    return {'status': 'error', 'message': e.toString()};
  }
}

  Future<Map<String, dynamic>> deleteUser(int userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';

      final response = await http.post(
        Uri.parse(ApiEndpoints.delete_user),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({'user_id': userId}),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        return {'status': 'error', 'message': 'فشل الاتصال بالخادم'};
      }
    } catch (e) {
      return {'status': 'error', 'message': e.toString()};
    }
  }

  // 🪙 Coins
  Future<Map<String, dynamic>> updateUserCoins(
    int userId,
    int coinsToAdd,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');

      final response = await http.post(
        Uri.parse(ApiEndpoints.updateUserCoins),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({'user_id': userId, 'coins_to_add': coinsToAdd}),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        return {'status': 'error', 'message': 'Failed to update coins'};
      }
    } catch (e) {
      return {'status': 'error', 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> getUserCoins() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');

      final response = await http.get(
        Uri.parse(ApiEndpoints.getUserCoins),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        return {'status': 'error', 'message': 'فشل في جلب الكوينز'};
      }
    } catch (e) {
      return {'status': 'error', 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> unlockEpisodeWithCoins(
    int episodeId,
    int coins,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');

      final response = await http.post(
        Uri.parse(ApiEndpoints.unlockEpisodeWithCoins),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({'episode_id': episodeId, 'coins': coins}),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        return {
          'status': 'error',
          'message': 'فشل فتح الحلقة: ${response.statusCode}',
        };
      }
    } catch (e) {
      return {'status': 'error', 'message': e.toString()};
    }
  }

  // ⭐ VIP
  Future<Map<String, dynamic>> checkVipStatus(int userId) async {
    try {
      final response = await http.post(
        Uri.parse(ApiEndpoints.checkVipStatus),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'user_id': userId}),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        return {
          'success': false,
          'message': 'Server returned ${response.statusCode}',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Failed to check VIP status: ${e.toString()}',
      };
    }
  }

  Future<Map<String, dynamic>> updateVipStatus(
    int userId,
    int duration,
    int packageId,
  ) async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.post(
        Uri.parse(ApiEndpoints.updateVipStatus),
        headers: headers,
        body: json.encode({
          'user_id': userId,
          'duration': duration,
          'package_id': packageId,
        }),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        return {
          'status': 'error',
          'message': 'Failed to update VIP status: ${response.statusCode}',
        };
      }
    } catch (e) {
      debugPrint('VIP Update Error: $e');
      return {
        'status': 'error',
        'message': 'Failed to update VIP status: ${e.toString()}',
      };
    }
  }

  // 📺 Series & Episodes
  Future<List<Series>> getAllSeries() async {
    final response = await http.get(Uri.parse(ApiEndpoints.getAllSeries));

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return (data['data'] as List)
          .map((json) => Series.fromJson(json))
          .toList();
    } else {
      throw Exception('Failed to load series');
    }
  }

  Future<List<Episode>> getEpisodesBySeries(int seriesId) async {
    try {
      final response = await http.get(
        Uri.parse("${ApiEndpoints.getEpisodesBySeries}?series_id=$seriesId"),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['status'] == 'success') {
          return (data['data'] as List)
              .map((json) => Episode.fromJson(json))
              .toList();
        } else {
          throw Exception('API Error: ${data['message']}');
        }
      } else {
        throw Exception('HTTP Error: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error in getEpisodesBySeries: $e');
      throw Exception('Failed to load episodes: $e');
    }
  }

  Future<List<Series>> getRecommendedSeries() async {
    final response = await http.get(Uri.parse(ApiEndpoints.getRecommendations));

    if (response.statusCode == 200) {
      final data = json.decode(response.body);

      if (data['status'] == 'success' && data['data'] is List) {
        return (data['data'] as List)
            .map((json) => Series.fromJson(json))
            .toList();
      } else {
        return [];
      }
    } else {
      throw Exception('Failed to load recommendations: ${response.statusCode}');
    }
  }

  // 👁️‍🗨️ Views & Likes
  Future<Map<String, dynamic>> getEpisodeStats(int episodeId) async {
    try {
      final response = await http.get(
        Uri.parse("${ApiEndpoints.viewsLikesApi}?episode_id=$episodeId"),
      );
      return json.decode(response.body);
    } catch (e) {
      debugPrint('Error in getEpisodeStats: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> recordView(int episodeId) async {
    try {
      final response = await http.post(
        Uri.parse(ApiEndpoints.viewsLikesApi),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'episode_id': episodeId,
          'action': 'view',
          'uid': 'anonymous',
        }),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return {'status': 'error', 'message': 'Failed to record view'};
    } catch (e) {
      debugPrint('Error recording view: $e');
      return {'status': 'error', 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> toggleLike(int episodeId, bool like) async {
    try {
      return await _authenticatedRequest(
        endpoint: ApiEndpoints.viewsLikesApi,
        method: 'POST',
        body: {
          'episode_id': episodeId,
          'action': like ? 'like' : 'unlike',
          'uid': (await SharedPreferences.getInstance()).getString('uid') ?? '',
        },
      );
    } catch (e) {
      debugPrint('Error in toggleLike: $e');
      rethrow;
    }
  }

  Future<List<dynamic>> getCoinPackages() async {
    try {
      final response = await http
          .get(
            Uri.parse(ApiEndpoints.getCoinPackages),
            headers: {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return data['data'];
        } else {
          throw Exception('فشل في تحميل الباقات');
        }
      } else {
        throw Exception('فشل في الاتصال بالسيرفر: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint("Error in getCoinPackages: $e");
      rethrow;
    }
  }

  // 🛠️ Helpers
  Future<Map<String, String>> _getAuthHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<Map<String, dynamic>> getAdWatchData(String userId) async {
    try {
      final response = await http.post(
        Uri.parse(ApiEndpoints.getAdWatchData),
        body: json.encode({'user_id': userId}),
        headers: {'Content-Type': 'application/json'},
      );

      return json.decode(response.body);
    } catch (e) {
      return {'status': 'error', 'message': e.toString()};
    }
  }

  // تحديث بيانات مشاهدة الإعلانات على السيرفر
  Future<Map<String, dynamic>> updateAdWatchCount(
    String userId,
    int adsWatched,
    String lastWatchDate,
  ) async {
    try {
      final response = await http.post(
        Uri.parse(ApiEndpoints.updateAdWatchCount),
        body: json.encode({
          'user_id': userId,
          'ads_watched': adsWatched,
          'last_watch_date': lastWatchDate,
        }),
        headers: {'Content-Type': 'application/json'},
      );

      return json.decode(response.body);
    } catch (e) {
      return {'status': 'error', 'message': e.toString()};
    }
  }

  // في ApiService
  Future<Map<String, dynamic>> getUnlockedEpisodes(String userId) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiEndpoints.baseUrl}ads/get_unlocked_episodes.php'),
        body: json.encode({'user_id': userId}),
        headers: {'Content-Type': 'application/json'},
      );
      return json.decode(response.body);
    } catch (e) {
      return {'status': 'error', 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> unlockEpisodeServer(
    String userId,
    int episodeId,
    int durationDays,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiEndpoints.baseUrl}ads/unlock_episode.php'),
        body: json.encode({
          'user_id': userId,
          'episode_id': episodeId,
          'duration': durationDays,
        }),
        headers: {'Content-Type': 'application/json'},
      );
      return json.decode(response.body);
    } catch (e) {
      return {'status': 'error', 'message': e.toString()};
    }
  }
}
