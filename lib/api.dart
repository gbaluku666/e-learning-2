import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;

import 'config.dart';
import 'store.dart';

class ApiException implements Exception {
  final String message;
  final String code;
  ApiException(this.message, [this.code = '']);
  @override
  String toString() => message;
}

class Api {
  static String? token;
  static Future<bool> Function()? onAuth;
  static void Function()? onVoucher;

  /// GET-based JSON call to the Apps Script backend. When [cache] is true the
  /// response is stored on the device and used if the network is unavailable
  /// (or still fresh for [ttl] seconds, which avoids repeated API calls).
  static Future<dynamic> call(String action,
      {Map<String, dynamic> p = const {},
      bool cache = false,
      int ttl = 0,
      bool retried = false}) async {
    final key = '$action|${jsonEncode(p)}';
    if (cache && ttl > 0 && Store.cache.containsKey(key)) {
      final t = Store.cache.get('$key|t');
      if (t is int && DateTime.now().millisecondsSinceEpoch - t < ttl * 1000) {
        return jsonDecode(Store.cache.get(key));
      }
    }
    Map j;
    try {
      final uri = Uri.parse(kApiUrl).replace(queryParameters: {
        'action': action,
        'payload': jsonEncode({...p, 'token': token}),
      });
      final r = await http.get(uri).timeout(const Duration(seconds: 45));
      j = jsonDecode(r.body) as Map;
    } catch (_) {
      if (cache && Store.cache.containsKey(key)) {
        return jsonDecode(Store.cache.get(key));
      }
      throw ApiException('No internet connection');
    }
    if (j['ok'] == true) {
      if (cache) {
        Store.cache.put(key, jsonEncode(j['data']));
        Store.cache.put('$key|t', DateTime.now().millisecondsSinceEpoch);
      }
      return j['data'];
    }
    final code = (j['code'] ?? '').toString();
    if (code == 'AUTH' && !retried && onAuth != null) {
      if (await onAuth!()) {
        return call(action, p: p, cache: cache, ttl: ttl, retried: true);
      }
    }
    if (code == 'VOUCHER') onVoucher?.call();
    throw ApiException((j['error'] ?? 'Error').toString(), code);
  }
}

/// Downloads topic files and keeps them inside the app (Hive), never in the
/// phone's public storage.
class FileService {
  static bool has(String id) => Store.files.containsKey(id);

  static Future<Uint8List> fetch(Map topic, {bool save = false, String unitName = ''}) async {
    final id = topic['id'] as String;
    if (has(id)) return (await Store.files.get(id)) as Uint8List;
    final r = await Api.call('getFile', p: {'topicId': id});
    var bytes = base64Decode(r['b64'] as String);
    if (r['gz'] == true) bytes = Uint8List.fromList(GZipDecoder().decodeBytes(bytes));
    if (save) {
      await Store.files.put(id, bytes);
      await Store.meta.put(id, {
        'id': id,
        'title': topic['title'],
        'fileName': topic['fileName'],
        'ext': topic['ext'],
        'size': bytes.length,
        'unit': unitName,
      });
    }
    return bytes;
  }

  static Future<void> remove(String id) async {
    await Store.files.delete(id);
    await Store.meta.delete(id);
  }
}
