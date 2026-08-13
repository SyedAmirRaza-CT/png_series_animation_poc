import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

class ImageCacheManager {
  static final ImageCacheManager _instance = ImageCacheManager._internal();
  factory ImageCacheManager() => _instance;
  ImageCacheManager._internal();

  String? _storagePath;

  Future<String> _getStoragePath() async {
    if (_storagePath != null) return _storagePath!;
    final appDir = await getApplicationSupportDirectory();
    _storagePath = '${appDir.path}/png_series_storage';
    final directory = Directory(_storagePath!);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return _storagePath!;
  }

  Future<File?> getCachedFile(String url) async {
    try {
      final storagePath = await _getStoragePath();
      final urlHash = md5.convert(utf8.encode(url)).toString();
      final extension = url.split('.').last.split('?').first;
      final localFile = File('$storagePath/$urlHash.$extension');

      if (await localFile.exists()) {
        return localFile;
      }

      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        await localFile.writeAsBytes(response.bodyBytes);
        return localFile;
      }
    } catch (e) {
      debugPrint('ImageCacheManager: Error processing $url: $e');
    }
    return null;
  }

  Future<void> clearCache() async {
    try {
      final storagePath = await _getStoragePath();
      final directory = Directory(storagePath);
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
      _storagePath = null;
    } catch (e) {
      debugPrint('ImageCacheManager: Error clearing cache: $e');
    }
  }
}
