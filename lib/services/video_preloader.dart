import 'dart:io';
import 'package:flutter/foundation.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:video_player/video_player.dart';

class VideoPreloader {
  final BaseCacheManager _cacheManager;

  VideoPreloader({BaseCacheManager? cacheManager})
    : _cacheManager = cacheManager ?? DefaultCacheManager();

  /// Returns a File if cached (or after download), or null on failure.
  Future<File?> fetchToCache(String url) async {
    try {
      final start = DateTime.now();
      final fileInfo = await _cacheManager.getFileFromCache(url);
      if (fileInfo != null && fileInfo.file.existsSync()) {
        final took = DateTime.now().difference(start).inMilliseconds;
        debugPrint('VideoPreloader: cache HIT for $url (took ${took}ms)');
        return fileInfo.file;
      }

      debugPrint('VideoPreloader: cache MISS for $url, downloading...');
      final fetched = await _cacheManager.getSingleFile(url);
      final took = DateTime.now().difference(start).inMilliseconds;
      debugPrint(
        'VideoPreloader: downloaded $url -> ${fetched.path} (took ${took}ms)',
      );
      return fetched;
    } catch (e) {
      debugPrint('VideoPreloader: failed to fetch $url -> $e');
      return null;
    }
  }

  /// Create a VideoPlayerController from cached file (or from network if cache miss).
  Future<VideoPlayerController> createController(String url) async {
    final start = DateTime.now();
    try {
      final file = await fetchToCache(url);
      VideoPlayerController controller;
      if (file != null) {
        debugPrint('VideoPreloader: creating controller.file for $url');
        controller = VideoPlayerController.file(file);
      } else {
        debugPrint('VideoPreloader: creating controller.network for $url');
        controller = VideoPlayerController.networkUrl(Uri.parse(url));
      }

      // Try to initialize here so callers receive an initialized controller.
      // Guard against very slow network by using a timeout.
      final initStart = DateTime.now();
      await controller.initialize().timeout(
        const Duration(seconds: 10),
        onTimeout: () async {
          debugPrint('VideoPreloader: initialize timeout for $url');
          // Do not leave controller uninitialized; dispose and rethrow
          try {
            await controller.dispose();
          } catch (_) {}
          throw Exception('VideoPreloader: initialize timeout');
        },
      );

      final took = DateTime.now().difference(start).inMilliseconds;
      final initTook = DateTime.now().difference(initStart).inMilliseconds;
      debugPrint(
        'VideoPreloader: initialized controller for $url (total ${took}ms, init ${initTook}ms)',
      );

      // ensure looping default is false for episode playback
      controller.setLooping(false);
      return controller;
    } catch (e) {
      debugPrint(
        'VideoPreloader: failed to create/initialize controller for $url -> $e',
      );
      rethrow;
    }
  }

  /// Optional: clear cache for a specific url or all
  Future<void> removeFromCache(String url) async {
    try {
      await _cacheManager.removeFile(url);
    } catch (e) {
      debugPrint('VideoPreloader: removeFromCache failed for $url -> $e');
    }
  }

  Future<void> clearAll() async {
    try {
      await _cacheManager.emptyCache();
    } catch (e) {
      debugPrint('VideoPreloader: clearAll failed -> $e');
    }
  }
}
