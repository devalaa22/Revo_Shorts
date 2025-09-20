// models/WatchHistoryService.dart
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/WatchedSeries.dart';

class WatchHistoryService {
  static const String _watchHistoryKey = 'user_watch_history';

  Future<void> saveWatchedSeries(WatchedSeries series) async {
    final prefs = await SharedPreferences.getInstance();
    final history = await getWatchHistory();

    // إزالة المسلسل إذا كان موجوداً مسبقاً
    history.removeWhere((s) => s.seriesId == series.seriesId);

    // إضافة المسلسل الجديد
    history.add(series);

    // حفظ فقط آخر 50 مسلسلاً
    if (history.length > 50) {
      history.sort((a, b) => b.lastWatchedAt.compareTo(a.lastWatchedAt));
      history.removeRange(50, history.length);
    }

    final historyJson = history.map((s) => s.toJson()).toList();
    await prefs.setString(_watchHistoryKey, json.encode(historyJson));
  }

  Future<List<WatchedSeries>> getWatchHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = prefs.getString(_watchHistoryKey);

    if (historyJson == null) return [];

    try {
      final List<dynamic> historyList = json.decode(historyJson);
      return historyList.map((json) => WatchedSeries.fromJson(json)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> removeFromHistory(int seriesId) async {
    final prefs = await SharedPreferences.getInstance();
    final history = await getWatchHistory();

    history.removeWhere((s) => s.seriesId == seriesId);

    final historyJson = history.map((s) => s.toJson()).toList();
    await prefs.setString(_watchHistoryKey, json.encode(historyJson));
  }

  Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_watchHistoryKey);
  }
}
