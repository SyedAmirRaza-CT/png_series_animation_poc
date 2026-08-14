import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive.dart';
import 'bundle_metadata.dart';

/// Exceptions for AssetBundleManager
class AssetBundleException implements Exception {
  final String message;
  final dynamic originalError;
  AssetBundleException(this.message, [this.originalError]);
  @override
  String toString() => 'AssetBundleException: $message ${originalError ?? ""}';
}

class BundleDownloadException extends AssetBundleException {
  BundleDownloadException(super.message, [super.error]);
}

class BundleExtractionException extends AssetBundleException {
  BundleExtractionException(super.message, [super.error]);
}

class BundleNotFoundException extends AssetBundleException {
  BundleNotFoundException(super.message);
}

class AssetBundleManager {
  static final AssetBundleManager _instance = AssetBundleManager._internal();
  factory AssetBundleManager() => _instance;
  AssetBundleManager._internal();

  static const String _bundlesDirName = 'asset_bundles';
  static const String _filesDirName = 'files';
  static const String _metadataFileName = 'metadata.json';
  static const String _tempDirName = '.temp';

  String? _rootPath;

  /// Gets the root directory for all asset bundles (Permanent Storage)
  Future<String> _getRootDir() async {
    if (_rootPath != null) return _rootPath!;
    // Use getApplicationDocumentsDirectory for "Always there" persistence
    final appDir = await getApplicationDocumentsDirectory();
    _rootPath = p.join(appDir.path, _bundlesDirName);
    final directory = Directory(_rootPath!);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return _rootPath!;
  }

  /// Gets the path for a specific bundle
  Future<String> getBundlePath(String bundleId) async {
    final root = await _getRootDir();
    return p.join(root, bundleId);
  }

  /// Gets the path for the files directory inside a bundle
  Future<String> _getBundleFilesPath(String bundleId) async {
    final bundlePath = await getBundlePath(bundleId);
    return p.join(bundlePath, _filesDirName);
  }

  /// Gets the full path of a file within a bundle
  Future<String> getFilePath(String bundleId, String relativePath) async {
    final filesPath = await _getBundleFilesPath(bundleId);
    return p.join(filesPath, relativePath);
  }

  /// Gets the full path of a folder within a bundle
  Future<String> getFolderPath(String bundleId, String relativePath) async {
    final filesPath = await _getBundleFilesPath(bundleId);
    return p.join(filesPath, relativePath);
  }

  /// Checks if a bundle is downloaded (any version)
  Future<bool> isBundleDownloaded(String bundleId) async {
    final bundlePath = await getBundlePath(bundleId);
    final metadataFile = File(p.join(bundlePath, _metadataFileName));
    return await metadataFile.exists();
  }

  /// Checks if a specific version of a bundle is installed
  Future<bool> isBundleVersionInstalled(String bundleId, int version) async {
    try {
      final metadata = await getBundleMetadata(bundleId);
      return metadata.version == version;
    } catch (_) {
      return false;
    }
  }

  /// Retrieves metadata for a bundle
  Future<BundleMetadata> getBundleMetadata(String bundleId) async {
    final bundlePath = await getBundlePath(bundleId);
    final metadataFile = File(p.join(bundlePath, _metadataFileName));
    if (!await metadataFile.exists()) {
      throw BundleNotFoundException('Metadata not found for bundle: $bundleId');
    }
    final content = await metadataFile.readAsString();
    return BundleMetadata.fromRawJson(content);
  }

  /// Checks if a specific file exists within a bundle
  Future<bool> fileExists(String bundleId, String relativePath) async {
    final path = await getFilePath(bundleId, relativePath);
    return await File(path).exists();
  }

  /// Checks if a specific folder exists within a bundle
  Future<bool> folderExists(String bundleId, String relativePath) async {
    final path = await getFolderPath(bundleId, relativePath);
    return await Directory(path).exists();
  }

  /// Lists files and directories in a bundle sub-path
  Future<List<FileSystemEntity>> listFiles(String bundleId, String relativePath) async {
    final path = await getFolderPath(bundleId, relativePath);
    final dir = Directory(path);
    if (!await dir.exists()) {
      return [];
    }
    return dir.list().toList();
  }

  /// Downloads and installs an asset bundle
  Future<void> downloadBundle({
    required String bundleId,
    required String url,
    required int version,
    void Function(int received, int total)? onProgress,
  }) async {
    debugPrint('AssetBundleManager: Starting download for $bundleId from $url');
    // 1. Check if already installed
    if (await isBundleVersionInstalled(bundleId, version)) {
      debugPrint('AssetBundleManager: Bundle $bundleId v$version already installed.');
      return;
    }

    final rootDir = await _getRootDir();
    debugPrint('AssetBundleManager: Root directory: $rootDir');
    
    final tempDir = Directory(p.join(rootDir, _tempDirName));
    if (!await tempDir.exists()) {
      await tempDir.create(recursive: true);
    }

    final tempZipFile = File(p.join(tempDir.path, '${bundleId}_$version.zip'));
    final extractionDir = Directory(p.join(tempDir.path, '${bundleId}_${version}_extract'));

    try {
      // 2. Download ZIP
      debugPrint('AssetBundleManager: Downloading ZIP to ${tempZipFile.path}...');
      await _downloadFile(url, tempZipFile, onProgress);
      debugPrint('AssetBundleManager: Download complete. Size: ${await tempZipFile.length()} bytes');

      // 3. Extract ZIP to temp location
      debugPrint('AssetBundleManager: Extracting ZIP to ${extractionDir.path}...');
      if (await extractionDir.exists()) {
        await extractionDir.delete(recursive: true);
      }
      await extractionDir.create(recursive: true);

      await _extractZip(tempZipFile, extractionDir);
      debugPrint('AssetBundleManager: Extraction complete.');

      // 4. Create metadata
      debugPrint('AssetBundleManager: Saving metadata...');
      final metadata = BundleMetadata(
        bundleId: bundleId,
        version: version,
        downloadedAt: DateTime.now(),
        sourceUrl: url,
        size: await tempZipFile.length(),
      );
      final metadataFile = File(p.join(extractionDir.path, _metadataFileName));
      await metadataFile.writeAsString(metadata.toRawJson());

      // 5. Atomic-ish Swap
      debugPrint('AssetBundleManager: Finalizing installation...');
      final finalBundlePath = await getBundlePath(bundleId);
      final backupPath = p.join(rootDir, '${bundleId}_old');

      if (await Directory(finalBundlePath).exists()) {
        final oldBackup = Directory(backupPath);
        if (await oldBackup.exists()) await oldBackup.delete(recursive: true);
        await Directory(finalBundlePath).rename(backupPath);
      }

      await extractionDir.rename(finalBundlePath);

      // 6. Cleanup backup and temp zip
      if (await Directory(backupPath).exists()) {
        await Directory(backupPath).delete(recursive: true);
      }
      if (await tempZipFile.exists()) {
        await tempZipFile.delete();
      }

      debugPrint('AssetBundleManager: Successfully installed $bundleId v$version');
    } catch (e, stack) {
      debugPrint('AssetBundleManager: ERROR during installation: $e');
      debugPrint(stack.toString());
      // Cleanup on failure
      if (await extractionDir.exists()) await extractionDir.delete(recursive: true);
      if (await tempZipFile.exists()) await tempZipFile.delete();
      
      throw BundleDownloadException('Failed to install bundle $bundleId', e);
    }
  }

  /// Downloads a file with progress tracking
  Future<void> _downloadFile(
    String url,
    File file,
    void Function(int received, int total)? onProgress,
  ) async {
    final client = http.Client();
    try {
      // Use http.Request but we need to handle redirects manually if using client.send
      // OR just use a package/method that handles it.
      // Since we need progress, we use a custom request but we must enable following redirects.
      
      var currentUrl = url;
      http.StreamedResponse? response;

      // Handle up to 5 redirects manually to support GitHub/Cloudinary redirects
      for (int i = 0; i < 5; i++) {
        final request = http.Request('GET', Uri.parse(currentUrl));
        request.headers['User-Agent'] = 'Flutter-AssetBundleManager';
        request.followRedirects = false; // We check manually to log
        
        response = await client.send(request);
        debugPrint('AssetBundleManager: HTTP Status: ${response.statusCode} for $currentUrl');

        if (response.statusCode >= 300 && response.statusCode < 400) {
          final location = response.headers['location'];
          if (location != null) {
            currentUrl = Uri.parse(currentUrl).resolve(location).toString();
            debugPrint('AssetBundleManager: Redirecting to $currentUrl');
            continue;
          }
        }
        break;
      }

      if (response == null || response.statusCode != 200) {
        throw BundleDownloadException('HTTP Error: ${response?.statusCode ?? "Unknown"}');
      }

      final total = response.contentLength ?? -1;
      int received = 0;
      int lastLogPercent = -1;

      final sink = file.openWrite();
      
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        
        // Progress logging (limit to every 10% or if total is unknown)
        if (total > 0) {
          int percent = ((received / total) * 100).floor();
          if (percent > lastLogPercent) {
            lastLogPercent = percent;
            debugPrint('AssetBundleManager: Download Progress: $percent% ($received/$total)');
          }
        } else if (received % (1024 * 500) == 0) { // Log every 500KB if total unknown
           debugPrint('AssetBundleManager: Download Progress: $received bytes (Total unknown)');
        }

        if (onProgress != null) {
          onProgress(received, total);
        }
      }
      
      await sink.close();
    } catch (e) {
      debugPrint('AssetBundleManager: Download Stream Error: $e');
      throw BundleDownloadException('Network failure during download', e);
    } finally {
      client.close();
    }
  }

  /// Extracts a ZIP file to a destination directory with security and memory efficiency
  Future<void> _extractZip(File zipFile, Directory destination) async {
    try {
      // Use InputFileStream to avoid loading the entire ZIP into memory (OOM prevention)
      final inputStream = InputFileStream(zipFile.path);
      final archive = ZipDecoder().decodeStream(inputStream);

      final destPath = destination.absolute.path;
      final filesDir = p.join(destPath, _filesDirName);
      await Directory(filesDir).create(recursive: true);

      for (final file in archive) {
        final filename = file.name;
        
        // Security: Prevent Zip Slip (Path Traversal)
        final targetPath = p.normalize(p.join(filesDir, filename));
        if (!p.isWithin(filesDir, targetPath)) {
          debugPrint('AssetBundleManager: SECURITY WARNING - Skipping invalid ZIP path: $filename');
          continue;
        }

        if (file.isFile) {
          final outFile = File(targetPath);
          await outFile.create(recursive: true);
          
          // Stream the content to the file
          final outputStream = OutputFileStream(outFile.path);
          file.writeContent(outputStream);
          await outputStream.close();
        } else {
          await Directory(targetPath).create(recursive: true);
        }
      }
      await inputStream.close();
    } catch (e) {
      throw BundleExtractionException('Failed to extract ZIP', e);
    }
  }

  /// Helper to get all image paths in a bundle recursively
  Future<List<String>> getAllImages(String bundleId) async {
    final filesPath = await _getBundleFilesPath(bundleId);
    final dir = Directory(filesPath);
    if (!await dir.exists()) return [];

    return dir
        .list(recursive: true)
        .where((entity) =>
            entity is File &&
            (entity.path.toLowerCase().endsWith('.png') ||
                entity.path.toLowerCase().endsWith('.jpg') ||
                entity.path.toLowerCase().endsWith('.jpeg') ||
                entity.path.toLowerCase().endsWith('.webp')))
        .map((entity) => entity.path)
        .toList();
  }

  /// Helper to get all audio paths in a bundle recursively
  Future<List<String>> getAllAudio(String bundleId) async {
    final filesPath = await _getBundleFilesPath(bundleId);
    final dir = Directory(filesPath);
    if (!await dir.exists()) return [];

    return dir
        .list(recursive: true)
        .where((entity) =>
            entity is File &&
            (entity.path.toLowerCase().endsWith('.mp3') ||
                entity.path.toLowerCase().endsWith('.wav') ||
                entity.path.toLowerCase().endsWith('.m4a') ||
                entity.path.toLowerCase().endsWith('.aac') ||
                entity.path.toLowerCase().endsWith('.ogg')))
        .map((entity) => entity.path)
        .toList();
  }

  /// Helper to get all video paths in a bundle recursively
  Future<List<String>> getAllVideo(String bundleId) async {
    final filesPath = await _getBundleFilesPath(bundleId);
    final dir = Directory(filesPath);
    if (!await dir.exists()) return [];

    return dir
        .list(recursive: true)
        .where((entity) =>
            entity is File &&
            (entity.path.toLowerCase().endsWith('.mp4') ||
                entity.path.toLowerCase().endsWith('.mov') ||
                entity.path.toLowerCase().endsWith('.mkv') ||
                entity.path.toLowerCase().endsWith('.webm')))
        .map((entity) => entity.path)
        .toList();
  }

  /// Helper to get all subtitle/json paths in a bundle recursively
  Future<List<String>> getAllSubtitles(String bundleId) async {
    final filesPath = await _getBundleFilesPath(bundleId);
    final dir = Directory(filesPath);
    if (!await dir.exists()) return [];

    return dir
        .list(recursive: true)
        .where((entity) =>
            entity is File && entity.path.toLowerCase().endsWith('.json') && !entity.path.endsWith('metadata.json'))
        .map((entity) => entity.path)
        .toList();
  }

  /// Reads a subtitle/JSON file from the bundle
  Future<Map<String, dynamic>> getJsonFile(String bundleId, String relativePath) async {
    final path = await getFilePath(bundleId, relativePath);
    final file = File(path);
    if (!await file.exists()) {
      throw AssetBundleException('JSON file not found: $path');
    }
    final content = await file.readAsString();
    return json.decode(content);
  }

  /// Deletes an entire bundle and its metadata
  Future<void> deleteBundle(String bundleId) async {
    final path = await getBundlePath(bundleId);
    final dir = Directory(path);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  /// Deletes a specific file within a bundle
  Future<void> deleteFile(String bundleId, String relativePath) async {
    final path = await getFilePath(bundleId, relativePath);
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Deletes a specific folder within a bundle
  Future<void> deleteFolder(String bundleId, String relativePath) async {
    final path = await getFolderPath(bundleId, relativePath);
    final dir = Directory(path);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  /// Clears all bundles and temporary files
  Future<void> clearAll() async {
    final root = await _getRootDir();
    final dir = Directory(root);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    _rootPath = null;
  }
}
