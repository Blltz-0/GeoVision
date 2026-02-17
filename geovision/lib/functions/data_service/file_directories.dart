import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class FileDirectories{
  static Future<void> saveLock = Future.value();

  static Future<File> getGeoJsonFile(String projectName) async {
    final appDir = await getApplicationDocumentsDirectory();
    return File('${appDir.path}/projects/$projectName/project_data.geojson');
  }

  static Future<Directory> getProjectImageDir(String projectName) async {
    final appDir = await getApplicationDocumentsDirectory();
    return Directory('${appDir.path}/projects/$projectName/images');
  }

  static Future<File> getClassFile(String projectName) async {
    final appDir = await getApplicationDocumentsDirectory();
    return File('${appDir.path}/projects/$projectName/classes.json');
  }

  static Future<File> getLabelFile(String projectName) async {
    final appDir = await getApplicationDocumentsDirectory();
    return File('${appDir.path}/projects/$projectName/labels.json');
  }

  static Future<File> getUploadHistoryFile(String projectName) async {
    final appDir = await getApplicationDocumentsDirectory();
    return File('${appDir.path}/projects/$projectName/upload_history.json');
  }
}