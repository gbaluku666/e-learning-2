import 'package:hive_flutter/hive_flutter.dart';

/// Everything the student keeps on their own device (offline).
class Store {
  static late Box cache; // cached API responses
  static late LazyBox files; // downloaded (decompressed) files, kept inside the app
  static late Box meta; // metadata of downloaded files
  static late Box prog; // reading progress
  static late Box sett; // settings, device id, session
  static late Box tt; // timetable (never sent to the server)

  static Future<void> init() async {
    cache = await Hive.openBox('cache');
    files = await Hive.openLazyBox('files');
    meta = await Hive.openBox('meta');
    prog = await Hive.openBox('prog');
    sett = await Hive.openBox('sett');
    tt = await Hive.openBox('tt');
  }
}

/// Per-topic reading progress, stored on the device and tied to the device id.
class Progress {
  static int secs(String id) => (Store.prog.get('s:$id') ?? 0) as int;
  static void setSecs(String id, int v) => Store.prog.put('s:$id', v);
  static bool done(String id) => Store.prog.get('d:$id') == true;
  static void setDone(String id, bool v) {
    Store.prog.put('d:$id', v);
    if (v) Store.prog.put('last', DateTime.now().millisecondsSinceEpoch);
  }

  static int? last() => Store.prog.get('last') as int?;
}
