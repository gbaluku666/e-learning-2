import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../config.dart';
import '../main.dart';
import '../ui.dart';

/// Admins sign in on the web dashboard / computer app only, never on phones.
bool get isMobileApp => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

class LoginScreen extends StatefulWidget {
  final bool voucherOnly;
  const LoginScreen({super.key, this.voucherOnly = false});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  int tab = 0; // 0 student, 1 tutor, 2 admin
  final voucher = TextEditingController();
  final name = TextEditingController();
  final email = TextEditingController();
  final pass = TextEditingController();
  bool busy = false;

  @override
  void initState() {
    super.initState();
    name.text = context.read<AppState>().name ?? '';
  }

  Future<void> _go(Future<void> Function() fn) async {
    setState(() => busy = true);
    try {
      await fn();
    } on ApiException catch (e) {
      if (mounted) snack(context, e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final tabs = <ButtonSegment<int>>[
      const ButtonSegment(value: 0, label: Text('Student'), icon: Icon(Icons.school_outlined)),
      const ButtonSegment(value: 1, label: Text('Tutor'), icon: Icon(Icons.person_outline)),
      if (!isMobileApp) const ButtonSegment(value: 2, label: Text('Admin'), icon: Icon(Icons.admin_panel_settings_outlined)),
    ];
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: FadeSlide(
              child: GlassCard(
                padding: const EdgeInsets.all(28),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Icon(Icons.auto_stories_rounded, size: 56, color: kSeed),
                  const SizedBox(height: 10),
                  const Text('E-Library', textAlign: TextAlign.center, style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(widget.voucherOnly ? 'Your voucher was deactivated. Enter a new code — your progress is safe.' : 'Learn anywhere, even offline',
                      textAlign: TextAlign.center, style: TextStyle(color: op(Theme.of(context).colorScheme.onSurface, .65))),
                  const SizedBox(height: 22),
                  if (!widget.voucherOnly) ...[
                    SegmentedButton<int>(
                      segments: tabs,
                      selected: {tab},
                      showSelectedIcon: false,
                      style: const ButtonStyle(padding: WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 14, horizontal: 8))),
                      onSelectionChanged: (s) => setState(() => tab = s.first),
                    ),
                    const SizedBox(height: 20),
                  ],
                  AnimatedSize(
                    duration: const Duration(milliseconds: 250),
                    child: widget.voucherOnly || tab == 0 ? _student(app) : (tab == 1 ? _tutor(app) : _admin()),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _student(AppState app) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(controller: voucher, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Voucher code', prefixIcon: Icon(Icons.confirmation_number_outlined))),
        const SizedBox(height: 12),
        TextField(controller: name, decoration: const InputDecoration(labelText: 'Your name (optional)', prefixIcon: Icon(Icons.badge_outlined))),
        const SizedBox(height: 20),
        GlowButton(label: 'Enter library', icon: Icons.login, loading: busy, onTap: () => _go(() async {
          await app.loginStudent(voucher.text, name.text);
          await app.refreshAll(force: true);
        })),
      ]);

  Widget _tutor(AppState app) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline))),
        const SizedBox(height: 12),
        TextField(controller: pass, obscureText: true, decoration: const InputDecoration(labelText: 'Password', prefixIcon: Icon(Icons.lock_outline))),
        const SizedBox(height: 20),
        GlowButton(label: 'Sign in', icon: Icons.login, loading: busy, onTap: () => _go(() async {
          await app.loginTutor(email.text, pass.text);
          await app.refreshAll(force: true);
        })),
        TextButton(onPressed: () => forgotPasswordDialog(context), child: const Text('Forgot password?')),
      ]);

  Widget _admin() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('The administrator signs in with a password on the admin dashboard.', textAlign: TextAlign.center),
        const SizedBox(height: 18),
        GlowButton(
            label: 'Open admin dashboard',
            icon: Icons.open_in_new,
            onTap: () => launchUrl(Uri.parse(kApiUrl), mode: LaunchMode.externalApplication)),
      ]);
}

/// Email verification-code password reset (tutors; admin uses the same flow on the dashboard).
Future<void> forgotPasswordDialog(BuildContext context) async {
  final email = TextEditingController();
  final code = TextEditingController();
  final pw = TextEditingController();
  int stage = 0;
  bool busy = false;
  await showDialog(
    context: context,
    builder: (dctx) => StatefulBuilder(builder: (ctx, set) {
      Future<void> run(Future<void> Function() f) async {
        set(() => busy = true);
        try {
          await f();
        } on ApiException catch (e) {
          if (ctx.mounted) snack(ctx, e.message);
        } finally {
          set(() => busy = false);
        }
      }

      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Reset password'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          if (stage == 0) ...[
            const Text('We will email you a 6-digit verification code.'),
            const SizedBox(height: 12),
            TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email')),
          ] else ...[
            TextField(controller: code, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Verification code')),
            const SizedBox(height: 12),
            TextField(controller: pw, obscureText: true, decoration: const InputDecoration(labelText: 'New password')),
          ],
        ]),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('Cancel')),
          GlowButton(
            label: stage == 0 ? 'Send code' : 'Reset',
            loading: busy,
            onTap: () => run(() async {
              if (stage == 0) {
                await Api.call('requestReset', p: {'email': email.text});
                set(() => stage = 1);
              } else {
                await Api.call('confirmReset', p: {'email': email.text, 'code': code.text, 'newPassword': pw.text});
                if (dctx.mounted) Navigator.pop(dctx);
                if (context.mounted) snack(context, 'Password updated. Sign in with it.');
              }
            }),
          ),
        ],
      );
    }),
  );
}
