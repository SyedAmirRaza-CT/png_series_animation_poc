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

  Future<File?> getCachedFile(String url) async {
    final appDir = await getApplicationSupportDirectory();
    final pngCacheDir = Directory('${appDir.path}/png_series_storage');
    if (!await pngCacheDir.exists()) {
      await pngCacheDir.create(recursive: true);
    }

    final urlHash = md5.convert(utf8.encode(url)).toString();
    final extension = url.split('.').last.split('?').first;
    final localFile = File('${pngCacheDir.path}/$urlHash.$extension');

    if (await localFile.exists()) {
      return localFile;
    }

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        await localFile.writeAsBytes(response.bodyBytes);
        return localFile;
      }
    } catch (e) {
      debugPrint('Error downloading image $url: $e');
    }
    return null;
  }

  Future<void> clearCache() async {
    final appDir = await getApplicationSupportDirectory();
    final pngCacheDir = Directory('${appDir.path}/png_series_storage');
    if (await pngCacheDir.exists()) {
      await pngCacheDir.delete(recursive: true);
    }
  }
}
