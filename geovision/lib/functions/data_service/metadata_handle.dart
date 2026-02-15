import 'dart:io';
import 'package:geolocator/geolocator.dart';
import 'file_handle.dart';
import 'metadata_class.dart';
import 'metadata_exif.dart';
import 'metadata_geojson.dart';


class MetadataService {

  // --- GEOJSON / DATABASE OPS ---
  static Future<void> rebuildProjectData(String projectName, {String projectType = 'classification'}) {
    return MetadataGeoJson.rebuildProjectData(projectName, projectType: projectType);
  }

  static Future<void> saveToCsv({
    required String projectName,
    required String imagePath,
    required Position? position,
    String? className,
    String projectType = 'classification',
    DateTime? customTime,
  }) {
    return MetadataGeoJson.saveToCsv(
        projectName: projectName,
        imagePath: imagePath,
        position: position,
        className: className,
        projectType: projectType,
        customTime: customTime
    );
  }

  static Future<List<Map<String, dynamic>>> readCsvData(String projectName) {
    return MetadataGeoJson.readCsvData(projectName);
  }

  static Future<void> removeEntry(String projectName, String filename) {
    return MetadataGeoJson.removeEntry(projectName, filename);
  }

  static Future<void> updateClassInCsv({required String projectName, required String imagePath, required String newClassName}) {
    return MetadataGeoJson.updateClassInCsv(projectName: projectName, imagePath: imagePath, newClassName: newClassName);
  }

  static Future<void> updateImageMetadata({
    required String projectName,
    required String imagePath,
    required double lat,
    required double lng,
    required DateTime time,
    String projectType = 'classification',
  }) {
    return MetadataGeoJson.updateImageMetadata(projectName: projectName, imagePath: imagePath, lat: lat, lng: lng, time: time, projectType: projectType);
  }

  // --- EXIF OPS ---
  static Future<void> embedMetadata({
    required String filePath,
    required double lat,
    required double lng,
    String? className,
    DateTime? time,
    bool updateClassOnly = false,
  }) {
    return MetadataExif.embedMetadata(filePath: filePath, lat: lat, lng: lng, className: className, time: time, updateClassOnly: updateClassOnly);
  }

  // --- CLASS / LABEL MANAGEMENT ---
  static Future<void> addClassDefinition(String projectName, String className, int colorValue) {
    return MetadataClasses.addClassDefinition(projectName, className, colorValue);
  }

  static Future<void> addLabelDefinition(String projectName, String className, int colorValue) {
    return MetadataClasses.addLabelDefinition(projectName, className, colorValue);
  }

  static Future<List<Map<String, dynamic>>> getClasses(String projectName) {
    return MetadataClasses.getClasses(projectName);
  }

  static Future<List<Map<String, dynamic>>> getLabels(String projectName) {
    return MetadataClasses.getLabels(projectName);
  }

  static Future<void> deleteClass(String projectName, String className) {
    return MetadataClasses.deleteClass(projectName, className);
  }

  static Future<void> deleteLabel(String projectName, String className) {
    return MetadataClasses.deleteLabel(projectName, className);
  }

  static Future<void> updateClass(String projectName, String oldName, String newName, int newColor) {
    return MetadataClasses.updateClass(projectName, oldName, newName, newColor);
  }

  static Future<void> updateLabel(String projectName, String oldName, String newName, int newColor) {
    return MetadataClasses.updateLabel(projectName, oldName, newName, newColor);
  }

  // --- FILE OPS ---
  static Future<void> deleteImage({required String projectName, required String imagePath, String projectType = 'classification'}) {
    return MetadataFiles.deleteImage(projectName: projectName, imagePath: imagePath, projectType: projectType);
  }

  static Future<int> getLatestIndex(Directory projectDir, String projectName, String className, {String projectType = 'classification'}) {
    return MetadataFiles.getLatestIndex(projectDir, projectName, className, projectType: projectType);
  }

  static Future<String> generateNextFileName(Directory projectDir, String projectName, String className, {String projectType = 'classification', Set<String>? existingNames}) {
    return MetadataFiles.generateNextFileName(projectDir, projectName, className, projectType: projectType, existingNames: existingNames);
  }

  static Future<String?> tagImage(String projectName, String oldImagePath, String newClassName, {String projectType = 'classification'}) {
    return MetadataFiles.tagImage(projectName, oldImagePath, newClassName, projectType: projectType);
  }
}