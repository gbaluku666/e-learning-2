import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../api.dart';
import '../config.dart';
import '../main.dart';
import '../store.dart';
import '../ui.dart';
import 'doc_viewer.dart';

class TopicScreen extends StatefulWidget {
  final Map topic;
  final String unitName;
  const TopicScreen({super.key, required this.topic, required this.unitName});
  @override
  State<TopicScreen> createState() => _TopicScreenState();
}

class _TopicScreenState extends State<TopicScreen> with WidgetsBindingObserver {
  final ValueNotifier<int> secs = ValueNotifier(0);
  Timer? _t;
  bool _active = true;
  String get id => widget.topic['id'];
  late final bool isStudent;

  @override
  void initState() {
    super.initState();
    isStudent = context.read<AppState>().role == 'student';
    WidgetsBinding.instance.addObserver(this);
    secs.value = Progress.secs(id);
    // Time spent on the topic (only while the app is in the foreground) is what
    // unlocks the "I've read this" button, so ticking can't be done blindly.
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_active || !isStudent) return;
      secs.value++;
      if (secs.value % 5 == 0) Progress.setSecs(id, secs.value);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) => _active = s == AppLifecycleState.resumed;

  @override
  void dispose() {
    _t?.cancel();
    if (isStudent && secs.value > 0) Progress.setSecs(id, secs.value);
    WidgetsBinding.instance.removeObserver(this);
    secs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.topic['title'], overflow: TextOverflow.ellipsis),
          bottom: const TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
            Tab(icon: Icon(Icons.description_outlined), text: 'Material'),
            Tab(icon: Icon(Icons.play_circle_outline), text: 'Video'),
            Tab(icon: Icon(Icons.note_alt_outlined), text: 'Extra notes'),
            Tab(icon: Icon(Icons.forum_outlined), text: 'Discussion'),
          ]),
        ),
        body: TabBarView(children: [
          _MaterialTab(topic: widget.topic, unitName: widget.unitName),
          _VideoTab(url: '${widget.topic['videoUrl'] ?? ''}'),
          _ExtraTab(topicId: id),
          _ChatTab(topicId: id),
        ]),
        bottomNavigationBar: SafeArea(child: app.role == 'tutor' ? _tutorBar(app) : _studentBar(app)),
      ),
    );
  }

  Widget _tutorBar(AppState app) {
    final done = app.tutorDone.contains(id);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: GlowButton(
        label: done ? 'Completed — tap to undo' : 'Mark topic as completed',
        icon: done ? Icons.check_circle : Icons.check_circle_outline,
        onTap: () async {
          try {
            await Api.call('tutorMark', p: {'topicId': id, 'done': !done});
            await app.refreshAll(force: true);
          } on ApiException catch (e) {
            if (mounted) snack(context, e.message);
          }
        },
      ),
    );
  }

  Widget _studentBar(AppState app) {
    return ValueListenableBuilder<int>(
      valueListenable: secs,
      builder: (_, s, __) {
        final done = Progress.done(id);
        final left = kMinReadSeconds - s;
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (app.tutorDone.contains(id))
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.verified, color: Colors.teal, size: 18),
                  SizedBox(width: 6),
                  Text('Your tutor has completed this topic', style: TextStyle(color: Colors.teal, fontWeight: FontWeight.w600)),
                ]),
              ),
            if (!done && left > 0) ...[
              LinearProgressIndicator(value: s / kMinReadSeconds, minHeight: 6, borderRadius: BorderRadius.circular(6)),
              const SizedBox(height: 6),
              Text('Keep reading… $left s until you can mark this as read', style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 8),
            ],
            GlowButton(
              label: done ? 'Marked as read — tap to undo' : 'I have read this topic',
              icon: done ? Icons.check_circle : Icons.done,
              onTap: done || left <= 0
                  ? () => setState(() {
                        Progress.setDone(id, !done);
                        if (!done) HapticFeedback.mediumImpact();
                      })
                  : null,
            ),
          ]),
        );
      },
    );
  }
}

/* ---------- Material (file) ---------- */
class _MaterialTab extends StatefulWidget {
  final Map topic;
  final String unitName;
  const _MaterialTab({required this.topic, required this.unitName});
  @override
  State<_MaterialTab> createState() => _MaterialTabState();
}

class _MaterialTabState extends State<_MaterialTab> {
  bool busy = false;
  @override
  Widget build(BuildContext context) {
    final t = widget.topic;
    if (t['hasFile'] != true) {
      return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('No file was attached to this topic. Check the Video and Extra notes tabs.')));
    }
    final saved = FileService.has(t['id']);
    return ListView(padding: const EdgeInsets.all(16), children: [
      GlassCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Icon(Icons.insert_drive_file_outlined, size: 40, color: kSeed),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${t['fileName']}', style: const TextStyle(fontWeight: FontWeight.w700)),
              Text('${'${t['ext']}'.toUpperCase()} · ${fmtSize((t['size'] ?? 0) as num)} (compressed)'),
            ])),
          ]),
          const SizedBox(height: 18),
          GlowButton(label: 'Open in app', icon: Icons.menu_book, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DocViewer(topic: t)))),
          const SizedBox(height: 10),
          saved
              ? GlowButton(
                  label: 'Downloaded — remove',
                  icon: Icons.download_done,
                  outlined: true,
                  onTap: () async {
                    await FileService.remove(t['id']);
                    setState(() {});
                  })
              : GlowButton(
                  label: 'Download for offline',
                  icon: Icons.download,
                  outlined: true,
                  loading: busy,
                  onTap: () async {
                    setState(() => busy = true);
                    try {
                      await FileService.fetch(t, save: true, unitName: widget.unitName);
                      if (mounted) snack(context, 'Saved inside the app for offline use');
                    } on ApiException catch (e) {
                      if (mounted) snack(context, e.message);
                    } finally {
                      if (mounted) setState(() => busy = false);
                    }
                  }),
        ]),
      ),
    ]);
  }
}

/* ---------- Video ---------- */
class _VideoTab extends StatefulWidget {
  final String url;
  const _VideoTab({required this.url});
  @override
  State<_VideoTab> createState() => _VideoTabState();
}

class _VideoTabState extends State<_VideoTab> {
  YoutubePlayerController? c;
  bool get _embedSupported => kIsWeb || defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    final vid = YoutubePlayerController.convertUrlToId(widget.url);
    if (vid != null && _embedSupported) {
      c = YoutubePlayerController.fromVideoId(videoId: vid, autoPlay: false, params: const YoutubePlayerParams(showFullscreenButton: true));
    }
  }

  @override
  void dispose() {
    c?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.url.trim().isEmpty) return const Center(child: Text('No support video for this topic.'));
    if (c != null) {
      return ListView(padding: const EdgeInsets.all(16), children: [
        ClipRRect(borderRadius: BorderRadius.circular(20), child: YoutubePlayer(controller: c!, aspectRatio: 16 / 9)),
        const SizedBox(height: 10),
        const Text('Videos need an internet connection.', textAlign: TextAlign.center),
      ]);
    }
    // The YouTube iframe player is not available in Windows desktop builds.
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Video playback inside the window is available on the mobile app and website.', textAlign: TextAlign.center),
          const SizedBox(height: 14),
          GlowButton(label: 'Watch video', icon: Icons.play_arrow, onTap: () => launchUrl(Uri.parse(widget.url), mode: LaunchMode.externalApplication)),
        ]),
      ),
    );
  }
}

/* ---------- Tutor extra notes ---------- */
class _ExtraTab extends StatefulWidget {
  final String topicId;
  const _ExtraTab({required this.topicId});
  @override
  State<_ExtraTab> createState() => _ExtraTabState();
}

class _ExtraTabState extends State<_ExtraTab> {
  late Future<dynamic> f;
  @override
  void initState() {
    super.initState();
    f = Api.call('materials', p: {'topicId': widget.topicId}, cache: true, ttl: 60).catchError((_) => []);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: f,
      builder: (c, s) {
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        final l = (s.data as List).cast<Map>();
        if (l.isEmpty) return const Center(child: Text('Your tutor has not added extra notes yet.'));
        return ListView(padding: const EdgeInsets.all(16), children: [
          for (final m in l)
            GlassCard(
              onTap: m['type'] != 'note' && '${m['content']}'.startsWith('http') ? () => launchUrl(Uri.parse('${m['content']}'), mode: LaunchMode.externalApplication) : null,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(m['type'] == 'link' ? Icons.link : (m['type'] == 'image' ? Icons.image_outlined : Icons.sticky_note_2_outlined), color: kSeed),
                  const SizedBox(width: 10),
                  Expanded(child: Text('${m['title']}', style: const TextStyle(fontWeight: FontWeight.w700))),
                ]),
                const SizedBox(height: 8),
                if (m['type'] == 'image' && '${m['content']}'.startsWith('http'))
                  ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.network('${m['content']}', errorBuilder: (_, __, ___) => Text('${m['content']}')))
                else
                  Text('${m['content']}'),
              ]),
            ),
        ]);
      },
    );
  }
}

/* ---------- Discussion chat ---------- */
class _ChatTab extends StatefulWidget {
  final String topicId;
  const _ChatTab({required this.topicId});
  @override
  State<_ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<_ChatTab> {
  List<Map> msgs = [];
  final input = TextEditingController();
  final scroll = ScrollController();
  Timer? _poll;
  bool offline = false;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 8), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await Api.call('comments', p: {'topicId': widget.topicId}, cache: true);
      if (!mounted) return;
      final l = (d as List).cast<Map>();
      final grew = l.length != msgs.length;
      setState(() {
        msgs = l;
        offline = false;
      });
      if (grew) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (scroll.hasClients) scroll.animateTo(scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
        });
      }
    } on ApiException {
      if (mounted) setState(() => offline = true);
    }
  }

  Future<void> _send() async {
    final text = input.text.trim();
    if (text.isEmpty) return;
    final app = context.read<AppState>();
    input.clear();
    try {
      await Api.call('addComment', p: {'topicId': widget.topicId, 'text': text, 'name': (app.name ?? '').isNotEmpty ? app.name : 'Student ${app.deviceId.substring(0, 4)}'});
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        input.text = text;
        snack(context, e.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      if (offline) Container(width: double.infinity, color: op(Colors.orange, .25), padding: const EdgeInsets.all(8), child: const Text('Offline — showing saved messages', textAlign: TextAlign.center)),
      Expanded(
        child: msgs.isEmpty
            ? const Center(child: Text('No messages yet. Ask a question about this topic!'))
            : ListView.builder(
                controller: scroll,
                padding: const EdgeInsets.all(12),
                itemCount: msgs.length,
                itemBuilder: (_, i) {
                  final m = msgs[i];
                  final mine = m['mine'] == true;
                  final staff = m['role'] != 'student';
                  return Align(
                    alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .78),
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        gradient: mine ? const LinearGradient(colors: [kSeed, kSeed2]) : null,
                        color: mine ? null : op(Theme.of(context).colorScheme.onSurface, .08),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${m['name']}${staff ? '  · tutor' : ''}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: mine ? Colors.white70 : (staff ? Colors.teal : null))),
                        const SizedBox(height: 2),
                        Text('${m['text']}', style: TextStyle(color: mine ? Colors.white : null)),
                      ]),
                    ),
                  );
                },
              ),
      ),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Row(children: [
            Expanded(child: TextField(controller: input, onSubmitted: (_) => _send(), decoration: const InputDecoration(hintText: 'Write a message…'))),
            const SizedBox(width: 8),
            IconButton.filled(onPressed: _send, icon: const Icon(Icons.send_rounded)),
          ]),
        ),
      ),
    ]);
  }
}
