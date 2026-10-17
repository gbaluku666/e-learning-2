import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../main.dart';
import '../ui.dart';
import 'settings.dart';
import 'topic.dart';

class TutorShell extends StatefulWidget {
  const TutorShell({super.key});
  @override
  State<TutorShell> createState() => _TutorShellState();
}

class _TutorShellState extends State<TutorShell> {
  int i = 0;
  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 800;
    final body = AnimatedSwitcher(duration: const Duration(milliseconds: 280), child: KeyedSubtree(key: ValueKey(i), child: i == 0 ? const TutorCoursesPage() : const SettingsPage()));
    const dest = [(Icons.dashboard_outlined, Icons.dashboard, 'My courses'), (Icons.settings_outlined, Icons.settings, 'Settings')];
    return Scaffold(
      body: SafeArea(
        child: wide
            ? Row(children: [
                NavigationRail(
                  backgroundColor: Colors.transparent,
                  selectedIndex: i,
                  labelType: NavigationRailLabelType.all,
                  onDestinationSelected: (v) => setState(() => i = v),
                  destinations: [for (final d in dest) NavigationRailDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: Text(d.$3))],
                ),
                Expanded(child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 900), child: body))),
              ])
            : body,
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: i,
              onDestinationSelected: (v) => setState(() => i = v),
              destinations: [for (final d in dest) NavigationDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: d.$3)],
            ),
    );
  }
}

class TutorCoursesPage extends StatefulWidget {
  const TutorCoursesPage({super.key});
  @override
  State<TutorCoursesPage> createState() => _TutorCoursesPageState();
}

class _TutorCoursesPageState extends State<TutorCoursesPage> {
  late Future<List<Map>> f = _load();

  Future<List<Map>> _load() async {
    final app = context.read<AppState>();
    final d = await Api.call('tutorUnits', cache: true);
    await app.refreshAll(force: true);
    return (d as List).cast<Map>();
  }

  Future<void> _refresh() async {
    setState(() => f = _load());
    await f;
  }

  Future<void> _toggle(Map t, bool done) async {
    final app = context.read<AppState>();
    try {
      await Api.call('tutorMark', p: {'topicId': t['id'], 'done': done});
      await app.refreshAll(force: true);
    } on ApiException catch (e) {
      if (mounted) snack(context, e.message);
    }
  }

  void _addMaterial(Map t) {
    final title = TextEditingController(), content = TextEditingController();
    String type = 'note';
    showDialog(
      context: context,
      builder: (dctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text('Extra material · ${t['title']}', overflow: TextOverflow.ellipsis),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButton<String>(
                isExpanded: true,
                value: type,
                items: const [
                  DropdownMenuItem(value: 'note', child: Text('Note')),
                  DropdownMenuItem(value: 'link', child: Text('Link')),
                  DropdownMenuItem(value: 'image', child: Text('Picture (image link)')),
                ],
                onChanged: (v) => set(() => type = v!),
              ),
              const SizedBox(height: 10),
              TextField(controller: title, decoration: const InputDecoration(labelText: 'Title')),
              const SizedBox(height: 10),
              TextField(controller: content, minLines: 3, maxLines: 6, decoration: InputDecoration(labelText: type == 'note' ? 'Your note' : 'https://…')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('Cancel')),
            GlowButton(
              label: 'Send to students',
              icon: Icons.send,
              onTap: () async {
                try {
                  await Api.call('addMaterial', p: {'topicId': t['id'], 'type': type, 'title': title.text.trim(), 'content': content.text.trim()});
                  if (dctx.mounted) Navigator.pop(dctx);
                  if (mounted) snack(context, 'Added');
                } on ApiException catch (e) {
                  if (dctx.mounted) snack(dctx, e.message);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return FutureBuilder<List<Map>>(
      future: f,
      builder: (c, s) {
        if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (s.hasError) return Center(child: Text('${s.error}'));
        final units = s.data!;
        final all = [for (final u in units) ...(u['topics'] as List).cast<Map>()];
        final doneAll = all.where((t) => app.tutorDone.contains(t['id'])).length;
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Text('Hello, ${app.name ?? ''}', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
            ),
            GlassCard(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              child: Column(children: [
                const Text('Overall progress', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 14),
                ProgressRing(value: all.isEmpty ? 0 : doneAll / all.length, caption: '$doneAll of ${all.length} topics'),
              ]),
            ),
            if (units.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('The administrator has not allocated any course units to you yet.')),
            for (var k = 0; k < units.length; k++) FadeSlide(index: k, child: _unitCard(units[k], app)),
          ]),
        );
      },
    );
  }

  Widget _unitCard(Map u, AppState app) {
    final unit = u['unit'] as Map;
    final topics = (u['topics'] as List).cast<Map>();
    final done = topics.where((t) => app.tutorDone.contains(t['id'])).length;
    return GlassCard(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        title: Text('${unit['code']} ${unit['name']}'.trim(), style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${unit['program']} · ${unit['semester']}', maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
          LinearProgressIndicator(value: topics.isEmpty ? 0 : done / topics.length, minHeight: 6, borderRadius: BorderRadius.circular(6)),
        ]),
        children: [
          for (final t in topics)
            ListTile(
              leading: Checkbox(value: app.tutorDone.contains(t['id']), onChanged: (v) => _toggle(t, v ?? false)),
              title: Text(t['title']),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TopicScreen(topic: t, unitName: '${unit['name']}'))),
              trailing: IconButton(tooltip: 'Add extra material', icon: const Icon(Icons.note_add_outlined), onPressed: () => _addMaterial(t)),
            ),
          if (topics.isEmpty) const ListTile(title: Text('No topics yet')),
        ],
      ),
    );
  }
}
