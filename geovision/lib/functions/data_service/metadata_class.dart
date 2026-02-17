import 'dart:convert';
import 'file_directories.dart';
import 'metadata_geojson.dart';

class MetadataClasses {
  // --- CLASS MANAGEMENT ---
  static Future<void> addClassDefinition(String projectName, String className, int colorValue) async {
    final file = await FileDirectories.getClassFile(projectName);
    List<dynamic> classes = (await file.exists()) ? jsonDecode(await file.readAsString()) : [];
    if (!classes.any((c) => c['name'] == className)) {
      classes.add({'name': className, 'color': colorValue});
      await file.writeAsString(jsonEncode(classes));
    }
  }

  static Future<void> addLabelDefinition(String projectName, String className, int colorValue) async {
    final file = await FileDirectories.getLabelFile(projectName);
    List<dynamic> classes = (await file.exists()) ? jsonDecode(await file.readAsString()) : [];
    if (!classes.any((c) => c['name'] == className)) {
      classes.add({'name': className, 'color': colorValue});
      await file.writeAsString(jsonEncode(classes));
    }
  }

  static Future<List<Map<String, dynamic>>> getClasses(String projectName) async {
    final file = await FileDirectories.getClassFile(projectName);
    return (await file.exists()) ? List<Map<String, dynamic>>.from(jsonDecode(await file.readAsString())) : [];
  }

  static Future<List<Map<String, dynamic>>> getLabels(String projectName) async {
    final file = await FileDirectories.getLabelFile(projectName);
    return (await file.exists()) ? List<Map<String, dynamic>>.from(jsonDecode(await file.readAsString())) : [];
  }

  static Future<void> deleteClass(String projectName, String className) async {
    final classFile = await FileDirectories.getClassFile(projectName);

    if (await classFile.exists()) {
      List<dynamic> jsonList = jsonDecode(await classFile.readAsString());
      jsonList.removeWhere((c) => c['name'] == className);
      await classFile.writeAsString(jsonEncode(jsonList));
    }
    await MetadataGeoJson.bulkUpdateCsvClass(projectName, className, "Unclassified");
  }

  static Future<void> deleteLabel(String projectName, String className) async {
    final classFile = await FileDirectories.getLabelFile(projectName);

    if (await classFile.exists()) {
      List<dynamic> jsonList = jsonDecode(await classFile.readAsString());
      jsonList.removeWhere((c) => c['name'] == className);
      await classFile.writeAsString(jsonEncode(jsonList));
    }
    await MetadataGeoJson.bulkUpdateCsvClass(projectName, className, "Unclassified");
  }

  static Future<void> updateClass(String projectName, String oldName, String newName, int newColor) async {
    final classFile = await FileDirectories.getClassFile(projectName);

    if (await classFile.exists()) {
      List<dynamic> jsonList = jsonDecode(await classFile.readAsString());
      for (var c in jsonList) {
        if (c['name'] == oldName) {
          c['name'] = newName;
          c['color'] = newColor;
        }
      }
      await classFile.writeAsString(jsonEncode(jsonList));
    }
    if (oldName != newName) {
      await MetadataGeoJson.bulkUpdateCsvClass(projectName, oldName, newName);
    }
  }

  static Future<void> updateLabel(String projectName, String oldName, String newName, int newColor) async {
    final classFile = await FileDirectories.getLabelFile(projectName);

    if (await classFile.exists()) {
      List<dynamic> jsonList = jsonDecode(await classFile.readAsString());
      for (var c in jsonList) {
        if (c['name'] == oldName) {
          c['name'] = newName;
          c['color'] = newColor;
        }
      }
      await classFile.writeAsString(jsonEncode(jsonList));
    }
    if (oldName != newName) {
      await MetadataGeoJson.bulkUpdateCsvClass(projectName, oldName, newName);
    }
  }
}