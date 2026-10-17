import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../config.dart';
import '../main.dart';
import '../store.dart';
import '../ui.dart';
import 'doc_viewer.dart';
import 'settings.dart';
import 'topic.dart';

class StudentShell extends StatefulWidget {
  const StudentShell({super.key});
  @override
  State<StudentShell> createState() => _StudentShellState();
}

class _StudentShellState extends State<StudentShell> {
  int i = 0;
  static const pages = <Widget>[LibraryPage(), ProgressPage(), TimetablePage(), DownloadsPage(), SettingsPage()];
  static const items = [
    (Icons.menu_book_outlined, Icons.menu_book, 'Library'),
    (Icons.donut_large_outlined, Icons.donut_large, 'Progress'),
    (Icons.calendar_month_outlined, Icons.calendar_month, 'Timetable'),
    (Icons.download_for_offline_outlined, Icons.download_for_offline, 'Offline'),
    (Icons.settings_outlined, Icons.settings, 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 800;
    final body = AnimatedSwitcher(duration: const Duration(milliseconds: 280), child: KeyedSubtree(key: ValueKey(i), child: pages[i]));
    return Scaffold(
      body: SafeArea(
        child: wide
            ? Row(children: [
                NavigationRail(
                  backgroundColor: Colors.transparent,
                  selectedIndex: i,
                  labelType: NavigationRailLabelType.all,
                  onDestinationSelected: (v) => setState(() => i = v),
                  destinations: [for (final it in items) NavigationRailDestination(icon: Icon(it.$1), selectedIcon: Icon(it.$2), label: Text(it.$3))],
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
              destinations: [for (final it in items) NavigationDestination(icon: Icon(it.$1), selectedIcon: Icon(it.$2), label: it.$3)],
            ),
    );
  }
}

/* ---------- helpers over the cached tree ---------- */
List<Map> allTopicsOf(Map sem) => [for (final u in sem['units'] as List) ...(u['topics'] as List).cast<Map>()];

List<(String, Map)> allSemesters(Map? tree) => [
      if (tree != null)
        for (final p in tree['programs'] as List)
          for (final s in p['semesters'] as List) ('${p['name']} · ${s['name']}', s as Map)
    ];

double semProgress(Map sem) {
  final t = allTopicsOf(sem);
  if (t.isEmpty) return 0;
  return t.where((x) => Progress.done(x['id'])).length / t.length;
}

class PageHeader extends StatelessWidget {
  final String title;
  final String? sub;
  const PageHeader(this.title, {super.key, this.sub});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
          if (sub != null) Text(sub!, style: TextStyle(color: op(Theme.of(context).colorScheme.onSurface, .6))),
        ]),
      );
}

/* ---------- Library ---------- */
class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});
  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  late Future<void> f;
  @override
  void initState() {
    super.initState();
    f = context.read<AppState>().refreshAll();
  }

  Future<void> _refresh() => context.read<AppState>().refreshAll(force: true);

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return FutureBuilder(
      future: f,
      builder: (c, snap) {
        final tree = app.tree;
        if (tree == null) {
          return snap.connectionState == ConnectionState.done
              ? const Center(child: Padding(padding: EdgeInsets.all(30), child: Text('No content yet. Connect to the internet once to load the library.', textAlign: TextAlign.center)))
              : const Center(child: CircularProgressIndicator());
        }
        final progs = (tree['programs'] as List).cast<Map>();
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
            const PageHeader('Library', sub: 'Pull down to refresh'),
            if (progs.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('The administrator has not added any programs yet.')),
            for (var k = 0; k < progs.length; k++)
              FadeSlide(
                index: k,
                child: GlassCard(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: ExpansionTile(
                    shape: const Border(),
                    collapsedShape: const Border(),
                    leading: const Icon(Icons.school, color: kSeed),
                    title: Text(progs[k]['name'], style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
                    children: [for (final s in (progs[k]['semesters'] as List).cast<Map>()) _semTile(s, app)],
                  ),
                ),
              ),
          ]),
        );
      },
    );
  }

  Widget _semTile(Map s, AppState app) => ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        title: Text(s['name']),
        subtitle: LinearProgressIndicator(value: semProgress(s), minHeight: 5, borderRadius: BorderRadius.circular(5)),
        children: [for (final u in (s['units'] as List).cast<Map>()) _unitTile(u, app)],
      );

  Widget _unitTile(Map u, AppState app) {
    final topics = (u['topics'] as List).cast<Map>();
    return ExpansionTile(
      shape: const Border(),
      collapsedShape: const Border(),
      leading: const Icon(Icons.folder_open),
      title: Text('${u['code']} ${u['name']}'.trim()),
      subtitle: Text('${topics.where((t) => Progress.done(t['id'])).length}/${topics.length} read'),
      children: [
        for (final t in topics)
          ListTile(
            leading: Icon(Progress.done(t['id']) ? Icons.check_circle : Icons.radio_button_unchecked, color: Progress.done(t['id']) ? Colors.green : null),
            title: Text(t['title']),
            subtitle: Row(children: [
              if (t['hasFile'] == true) Text('${t['ext']}'.toUpperCase()),
              if (t['videoUrl'] != null && '${t['videoUrl']}'.isNotEmpty) const Padding(padding: EdgeInsets.only(left: 8), child: Icon(Icons.play_circle_outline, size: 16)),
              if (app.tutorDone.contains(t['id'])) const Padding(padding: EdgeInsets.only(left: 8), child: Text('· tutor completed', style: TextStyle(color: Colors.teal))),
            ]),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => TopicScreen(topic: t, unitName: '${u['name']}')));
              if (mounted) setState(() {});
            },
          ),
        if (topics.isEmpty) const ListTile(title: Text('No topics yet')),
      ],
    );
  }
}

/* ---------- Progress ---------- */
class ProgressPage extends StatefulWidget {
  const ProgressPage({super.key});
  @override
  State<ProgressPage> createState() => _ProgressPageState();
}

class _ProgressPageState extends State<ProgressPage> {
  String? get semId => Store.sett.get('semId');

  void _startSession(List<(String, Map)> sems) {
    String? pick = semId ?? (sems.isNotEmpty ? sems.first.$2['id'] : null);
    showDialog(
      context: context,
      builder: (dctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text('Start a study session'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Choose the semester you are in. Tick topics as you finish them to track coverage.'),
            const SizedBox(height: 12),
            DropdownButton<String>(
              isExpanded: true,
              value: pick,
              items: [for (final s in sems) DropdownMenuItem(value: s.$2['id'] as String, child: Text(s.$1, overflow: TextOverflow.ellipsis))],
              onChanged: (v) => set(() => pick = v),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('Cancel')),
            GlowButton(
              label: 'Start',
              icon: Icons.play_arrow,
              onTap: () {
                if (pick != null) {
                  if (Store.sett.get('start:$pick') == null) Store.sett.put('start:$pick', DateTime.now().millisecondsSinceEpoch);
                  Store.sett.put('semId', pick);
                }
                Navigator.pop(dctx);
                setState(() {});
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
    final sems = allSemesters(app.tree);
    final cur = sems.where((s) => s.$2['id'] == semId).toList();
    return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
      const PageHeader('Progress', sub: 'Your coverage, tracked on this device'),
      if (cur.isEmpty)
        GlassCard(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          child: Column(children: [
            const Icon(Icons.flag_outlined, size: 44, color: kSeed),
            const SizedBox(height: 8),
            const Text('Start a session to track your progress', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            GlowButton(label: 'Start session', icon: Icons.play_arrow, onTap: sems.isEmpty ? null : () => _startSession(sems)),
          ]),
        )
      else
        ..._current(cur.first, app, sems),
      if (sems.isNotEmpty) ...[
        const Padding(padding: EdgeInsets.fromLTRB(20, 18, 20, 4), child: Text('All semesters', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18))),
        for (final s in sems)
          GlassCard(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.$1, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 8),
                LinearProgressIndicator(value: semProgress(s.$2), minHeight: 7, borderRadius: BorderRadius.circular(7)),
              ])),
              const SizedBox(width: 14),
              Text('${(semProgress(s.$2) * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.w800)),
            ]),
          ),
      ],
    ]);
  }

  List<Widget> _current(( String, Map) cur, AppState app, List<(String, Map)> sems) {
    final topics = allTopicsOf(cur.$2);
    final done = topics.where((t) => Progress.done(t['id'])).length;
    final tutorAhead = topics.where((t) => app.tutorDone.contains(t['id']) && !Progress.done(t['id'])).length;
    final value = topics.isEmpty ? 0.0 : done / topics.length;
    final start = Store.sett.get('start:${cur.$2['id']}') as int?;
    final expected = start == null ? 0.0 : (DateTime.now().millisecondsSinceEpoch - start) / (kSemesterDays * 86400000);
    final last = Progress.last();
    final idleDays = last == null ? null : DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(last)).inDays;
    final reminders = <String>[
      if (tutorAhead > 0) 'Your tutor has completed $tutorAhead topic${tutorAhead == 1 ? '' : 's'} you have not confirmed yet.',
      if (topics.isNotEmpty && expected > 0.1 && value + .15 < expected.clamp(0.0, 1.0)) 'You are behind schedule for this semester — try a topic today.',
      if (idleDays != null && idleDays >= 3) 'You have not read anything for $idleDays days.',
    ];
    return [
      GlassCard(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        child: Column(children: [
          Text(cur.$1, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          ProgressRing(value: value, caption: '$done of ${topics.length} topics'),
          const SizedBox(height: 16),
          GlowButton(label: 'Change semester', outlined: true, icon: Icons.swap_horiz, onTap: () => _startSession(sems)),
        ]),
      ),
      for (final r in reminders)
        GlassCard(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
          padding: const EdgeInsets.all(14),
          child: Row(children: [const Icon(Icons.notifications_active_outlined, color: Colors.orange), const SizedBox(width: 12), Expanded(child: Text(r))]),
        ),
      for (final u in (cur.$2['units'] as List).cast<Map>())
        GlassCard(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
          padding: const EdgeInsets.all(14),
          child: Builder(builder: (_) {
            final ts = (u['topics'] as List).cast<Map>();
            final d = ts.where((t) => Progress.done(t['id'])).length;
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${u['code']} ${u['name']}'.trim(), style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: ts.isEmpty ? 0 : d / ts.length, minHeight: 7, borderRadius: BorderRadius.circular(7)),
              const SizedBox(height: 4),
              Text('$d / ${ts.length} topics', style: const TextStyle(fontSize: 12)),
            ]);
          }),
        ),
    ];
  }
}

/* ---------- Timetable (offline, never uploaded) ---------- */
class TimetablePage extends StatefulWidget {
  const TimetablePage({super.key});
  @override
  State<TimetablePage> createState() => _TimetablePageState();
}

class _TimetablePageState extends State<TimetablePage> {
  static const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

  List<Map> get items {
    final raw = Store.tt.get('items');
    return raw == null ? [] : (jsonDecode(raw as String) as List).cast<Map>();
  }

  void _save(List<Map> l) {
    Store.tt.put('items', jsonEncode(l));
    setState(() {});
  }

  Future<void> _add() async {
    final title = TextEditingController();
    int day = DateTime.now().weekday - 1;
    TimeOfDay from = const TimeOfDay(hour: 8, minute: 0), to = const TimeOfDay(hour: 9, minute: 0);
    await showDialog(
      context: context,
      builder: (dctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text('Add study slot'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: title, decoration: const InputDecoration(labelText: 'What will you study?')),
            const SizedBox(height: 12),
            DropdownButton<int>(isExpanded: true, value: day, items: [for (var i = 0; i < 7; i++) DropdownMenuItem(value: i, child: Text(days[i]))], onChanged: (v) => set(() => day = v!)),
            Row(children: [
              Expanded(child: TextButton(onPressed: () async { final t = await showTimePicker(context: ctx, initialTime: from); if (t != null) set(() => from = t); }, child: Text('From ${from.format(ctx)}'))),
              Expanded(child: TextButton(onPressed: () async { final t = await showTimePicker(context: ctx, initialTime: to); if (t != null) set(() => to = t); }, child: Text('To ${to.format(ctx)}'))),
            ]),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('Cancel')),
            GlowButton(
              label: 'Add',
              onTap: () {
                if (title.text.trim().isEmpty) return;
                final l = items..add({'t': title.text.trim(), 'd': day, 'f': from.hour * 60 + from.minute, 'e': to.hour * 60 + to.minute});
                _save(l);
                Navigator.pop(dctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  String _t(int m) => '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final l = items;
    return Stack(children: [
      ListView(padding: const EdgeInsets.only(bottom: 90), children: [
        const PageHeader('Timetable', sub: 'Stored only on this device'),
        if (l.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('No study slots yet. Tap + to plan your week.')),
        for (var d = 0; d < 7; d++)
          if (l.any((x) => x['d'] == d)) ...[
            Padding(padding: const EdgeInsets.fromLTRB(20, 14, 20, 2), child: Text(days[d], style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
            for (final x in (l.where((x) => x['d'] == d).toList()..sort((a, b) => (a['f'] as int).compareTo(b['f'] as int))))
              GlassCard(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  const Icon(Icons.schedule, color: kSeed),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(x['t'], style: const TextStyle(fontWeight: FontWeight.w600)), Text('${_t(x['f'])} – ${_t(x['e'])}')])),
                  IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _save(l..remove(x))),
                ]),
              ),
          ],
      ]),
      Positioned(right: 20, bottom: 20, child: GlowButton(label: 'Add', icon: Icons.add, onTap: _add)),
    ]);
  }
}

/* ---------- Offline downloads ---------- */
class DownloadsPage extends StatefulWidget {
  const DownloadsPage({super.key});
  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage> {
  @override
  Widget build(BuildContext context) {
    final metas = Store.meta.values.cast<Map>().toList();
    return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
      const PageHeader('Offline', sub: 'Files saved inside the app — open them without internet'),
      if (metas.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('Nothing downloaded yet. Open a topic and tap “Download for offline”.')),
      for (final m in metas)
        GlassCard(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
          padding: const EdgeInsets.all(8),
          child: ListTile(
            leading: const Icon(Icons.description_outlined, color: kSeed),
            title: Text('${m['title']}'),
            subtitle: Text('${m['unit']} · ${'${m['ext']}'.toUpperCase()} · ${fmtSize(m['size'] as num)}'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DocViewer(topic: Map.from(m)))),
            trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () async { await FileService.remove(m['id']); setState(() {}); }),
          ),
        ),
    ]);
  }
}
