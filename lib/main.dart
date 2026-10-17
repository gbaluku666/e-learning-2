import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import 'api.dart';
import 'screens/login.dart';
import 'screens/student.dart';
import 'screens/tutor.dart';
import 'store.dart';
import 'ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Store.init();
  runApp(ChangeNotifierProvider(create: (_) => AppState()..load(), child: const ELibraryApp()));
}

class AppState extends ChangeNotifier {
  ThemeMode mode = ThemeMode.system;
  String? role; // 'student' | 'tutor'
  String? name, email, voucher;
  String deviceId = '';
  bool voucherRevoked = false;
  Map? tree;
  Set<String> tutorDone = {};

  void load() {
    deviceId = Store.sett.get('deviceId') ?? '';
    if (deviceId.isEmpty) {
      // identifier given automatically on first launch; progress is tied to it
      deviceId = const Uuid().v4();
      Store.sett.put('deviceId', deviceId);
    }
    final m = Store.sett.get('theme');
    mode = m == 'dark' ? ThemeMode.dark : (m == 'light' ? ThemeMode.light : ThemeMode.system);
    voucher = Store.sett.get('voucher');
    name = Store.sett.get('name');
    if (Store.sett.get('role') == 'student' && voucher != null) {
      role = 'student';
      Api.token = Store.sett.get('token');
    }
    Api.onVoucher = () {
      if (role == 'student' && !voucherRevoked) {
        voucherRevoked = true;
        notifyListeners();
      }
    };
    Api.onAuth = () async {
      if (role != 'student' || voucher == null) {
        logout();
        return false;
      }
      try {
        await loginStudent(voucher!, name);
        return true;
      } catch (_) {
        return false;
      }
    };
    // show the last cached library immediately (works offline)
    try {
      final c = Store.cache.get('tree|{}');
      if (c is String) tree = Map.from(jsonDecode(c) as Map);
      final d = Store.cache.get('tutorDone|{}');
      if (d is String) tutorDone = Set<String>.from(jsonDecode(d) as List);
    } catch (_) {}
  }

  void setTheme(ThemeMode m) {
    mode = m;
    Store.sett.put('theme', m == ThemeMode.dark ? 'dark' : (m == ThemeMode.light ? 'light' : 'system'));
    notifyListeners();
  }

  Future<void> loginStudent(String v, String? n) async {
    final r = await Api.call('studentLogin', p: {'deviceId': deviceId, 'voucher': v, 'name': n ?? ''});
    Api.token = r['token'];
    role = 'student';
    voucher = v.trim().toUpperCase();
    name = (n ?? '').trim();
    voucherRevoked = false;
    Store.sett.put('role', 'student');
    Store.sett.put('voucher', voucher);
    Store.sett.put('name', name);
    Store.sett.put('token', Api.token);
    notifyListeners();
  }

  Future<void> loginTutor(String em, String pw) async {
    final r = await Api.call('login', p: {'email': em, 'password': pw, 'role': 'tutor'});
    Api.token = r['token'];
    role = 'tutor';
    name = r['user']['name'];
    email = r['user']['email'];
    notifyListeners();
  }

  void logout() {
    // progress, downloads and timetable stay on the device (tied to deviceId)
    role = null;
    Api.token = null;
    voucherRevoked = false;
    voucher = null;
    Store.sett.delete('role');
    Store.sett.delete('voucher');
    Store.sett.delete('token');
    notifyListeners();
  }

  Future<void> refreshAll({bool force = false}) async {
    try {
      final t = await Api.call('tree', cache: true, ttl: force ? 0 : 300);
      tree = Map.from(t as Map);
      final d = await Api.call('tutorDone', cache: true, ttl: force ? 0 : 120);
      tutorDone = Set<String>.from(d as List);
    } on ApiException catch (_) {
      // offline or error: keep whatever is cached
    }
    notifyListeners();
  }
}

class ELibraryApp extends StatelessWidget {
  const ELibraryApp({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return MaterialApp(
      title: 'E-Library',
      debugShowCheckedModeBanner: false,
      themeMode: app.mode,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      builder: (c, child) => AnimatedBg(child: child!),
      home: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        child: _root(app),
      ),
    );
  }

  Widget _root(AppState app) {
    if (app.role == null) return const LoginScreen(key: ValueKey('login'));
    if (app.role == 'student' && app.voucherRevoked) return const LoginScreen(key: ValueKey('voucher'), voucherOnly: true);
    if (app.role == 'tutor') return const TutorShell(key: ValueKey('tutor'));
    return const StudentShell(key: ValueKey('student'));
  }
}
