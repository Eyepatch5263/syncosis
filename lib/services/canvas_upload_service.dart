import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class CanvasUploadService {
  static const _apiBase = 'https://syncosis-server-b075827ce03d.herokuapp.com';

  /// Uploads [bytes] to Cloudinary via the server and returns the CDN URL.
  static Future<String> upload({
    required Uint8List bytes,
    required String filename,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_apiBase/api/canvas/upload'),
    )..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));

    final streamed = await request.send().timeout(const Duration(seconds: 60));
    final body = await streamed.stream.bytesToString();

    if (streamed.statusCode != 200) {
      final err = (jsonDecode(body) as Map<String, dynamic>)['error'] as String?;
      throw Exception(err ?? 'Upload failed');
    }

    return (jsonDecode(body) as Map<String, dynamic>)['url'] as String;
  }
}
