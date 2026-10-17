import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../main.dart';
import '../store.dart';
import '../ui.dart';
import 'login.dart' show isMobileApp;

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final staff = app.role == 'tutor';
    return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        child: Text('Settings', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
      ),
      GlassCard(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Appearance', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode), label: Text('Light')),
              ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto), label: Text('Auto')),
              ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode), label: Text('Dark')),
            ],
            selected: {app.mode},
            onSelectionChanged: (s) => app.setTheme(s.first),
          ),
          const SizedBox(height: 6),
          const Text('Dark mode also applies to documents.', style: TextStyle(fontSize: 12)),
        ]),
      ),
      if (staff)
        GlassCard(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Signed in as ${app.name ?? ''}', style: const TextStyle(fontWeight: FontWeight.w800)),
            Text(app.email ?? ''),
            const SizedBox(height: 14),
            GlowButton(label: 'Change password', icon: Icons.lock_reset, outlined: true, onTap: () => _changePassword(context)),
          ]),
        )
      else
        GlassCard(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Your identifier', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            SelectableText(app.deviceId, style: const TextStyle(fontFamily: 'monospace')),
            const SizedBox(height: 6),
            const Text('Your progress, downloads and timetable are tied to this identifier and kept on this device.', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 10),
            Text('Voucher: ${app.voucher ?? '-'}'),
          ]),
        ),
      if (!staff)
        GlassCard(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            GlowButton(
              label: 'Clear cached data',
              icon: Icons.cleaning_services_outlined,
              outlined: true,
              onTap: () async {
                await Store.cache.clear();
                if (context.mounted) snack(context, 'Cache cleared. Downloads and progress are untouched.');
              },
            ),
          ]),
        ),
      GlassCard(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: GlowButton(label: 'Sign out', icon: Icons.logout, danger: true, onTap: () => app.logout()),
      ),
      if (isMobileApp) const SizedBox.shrink(),
    ]);
  }

  void _changePassword(BuildContext context) {
    final o = TextEditingController(), n = TextEditingController();
    showDialog(
      context: context,
      builder: (dctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Change password'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: o, obscureText: true, decoration: const InputDecoration(labelText: 'Current password')),
          const SizedBox(height: 12),
          TextField(controller: n, obscureText: true, decoration: const InputDecoration(labelText: 'New password')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('Cancel')),
          GlowButton(
            label: 'Update',
            onTap: () async {
              try {
                await Api.call('changePassword', p: {'oldPassword': o.text, 'newPassword': n.text});
                if (dctx.mounted) Navigator.pop(dctx);
                if (context.mounted) snack(context, 'Password changed');
              } on ApiException catch (e) {
                if (dctx.mounted) snack(dctx, e.message);
              }
            },
          ),
        ],
      ),
    );
  }
}
