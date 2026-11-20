import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/notebook.dart';

class NotebookStore {
  static const _storageKey = 'folio_local_notebooks_v1';

  static Future<List<Notebook>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return [];

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((item) => Notebook.fromJson(item as Map<String, dynamic>))
          .toList();
    } on FormatException {
      return [];
    } on TypeError {
      return [];
    }
  }

  static Future<void> save(List<Notebook> notebooks) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode(notebooks.map((notebook) => notebook.toJson()).toList()),
    );
  }
}
