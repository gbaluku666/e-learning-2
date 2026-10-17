import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart' as xl;
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../api.dart';
import '../ui.dart';

/// Opens topic files inside the app: pdf, docx, xlsx, pptx, images and text.
/// Light/dark mode is applied to the documents as well.
class DocViewer extends StatefulWidget {
  final Map topic;
  const DocViewer({super.key, required this.topic});
  @override
  State<DocViewer> createState() => _DocViewerState();
}

class _DocViewerState extends State<DocViewer> {
  late Future<Uint8List> f = FileService.fetch(widget.topic);

  String get ext => '${widget.topic['ext']}'.toLowerCase();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.topic['title']}', overflow: TextOverflow.ellipsis)),
      body: FutureBuilder<Uint8List>(
        future: f,
        builder: (c, s) {
          if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (s.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('${s.error}', textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  GlowButton(label: 'Try again', icon: Icons.refresh, onTap: () => setState(() => f = FileService.fetch(widget.topic))),
                ]),
              ),
            );
          }
          return _body(context, s.data!);
        },
      ),
    );
  }

  Widget _body(BuildContext context, Uint8List b) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    switch (ext) {
      case 'pdf':
        final v = SfPdfViewer.memory(b);
        return dark
            ? ColorFiltered(
                colorFilter: const ColorFilter.matrix(<double>[-1, 0, 0, 0, 255, 0, -1, 0, 0, 255, 0, 0, -1, 0, 255, 0, 0, 0, 1, 0]),
                child: v)
            : v;
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'gif':
      case 'webp':
        return InteractiveViewer(maxScale: 6, child: Center(child: Image.memory(b)));
      case 'xlsx':
        return _SheetView(bytes: b);
      case 'docx':
        return _TextView(text: _docx(b), empty: 'This document has no readable text.');
      case 'pptx':
        return _TextView(text: _pptx(b), empty: 'This presentation has no readable text.');
      case 'txt':
      case 'csv':
      case 'md':
        return _TextView(text: utf8.decode(b, allowMalformed: true), empty: 'Empty file.');
      default:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('.$ext files (older Office formats) cannot be previewed. Ask your administrator to upload .pdf, .docx, .xlsx or .pptx.', textAlign: TextAlign.center),
          ),
        );
    }
  }

  static String _unesc(String s) => s.replaceAll('&amp;', '&').replaceAll('&lt;', '<').replaceAll('&gt;', '>').replaceAll('&quot;', '"').replaceAll('&apos;', "'");

  static String _docx(Uint8List b) {
    final a = ZipDecoder().decodeBytes(b);
    final f = a.findFile('word/document.xml');
    if (f == null) return '';
    var x = utf8.decode(f.content as List<int>, allowMalformed: true);
    x = x.replaceAll('</w:p>', '\n').replaceAll(RegExp(r'<w:tab/>'), '\t').replaceAll(RegExp(r'<w:br[^>]*/>'), '\n').replaceAll(RegExp(r'<[^>]+>'), '');
    return _unesc(x).trim();
  }

  static String _pptx(Uint8List b) {
    final a = ZipDecoder().decodeBytes(b);
    final slides = a.files.where((f) => RegExp(r'^ppt/slides/slide\d+\.xml$').hasMatch(f.name)).toList()
      ..sort((p, q) => int.parse(RegExp(r'(\d+)').firstMatch(p.name.split('/').last)!.group(1)!).compareTo(int.parse(RegExp(r'(\d+)').firstMatch(q.name.split('/').last)!.group(1)!)));
    final out = StringBuffer();
    var n = 1;
    for (final s in slides) {
      final x = utf8.decode(s.content as List<int>, allowMalformed: true);
      final parts = RegExp(r'<a:t[^>]*>(.*?)</a:t>', dotAll: true).allMatches(x).map((m) => _unesc(m.group(1)!)).where((t) => t.trim().isNotEmpty);
      out.writeln('— Slide ${n++} —');
      for (final p in parts) {
        out.writeln(p);
      }
      out.writeln();
    }
    return out.toString().trim();
  }
}

class _TextView extends StatelessWidget {
  final String text, empty;
  const _TextView({required this.text, required this.empty});
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760), child: SelectableText(text.isEmpty ? empty : text, style: const TextStyle(fontSize: 16, height: 1.6)))),
      );
}

class _SheetView extends StatefulWidget {
  final Uint8List bytes;
  const _SheetView({required this.bytes});
  @override
  State<_SheetView> createState() => _SheetViewState();
}

class _SheetViewState extends State<_SheetView> {
  late final xl.Excel book = xl.Excel.decodeBytes(widget.bytes);
  String? sel;
  @override
  Widget build(BuildContext context) {
    final names = book.tables.keys.toList();
    if (names.isEmpty) return const Center(child: Text('Empty workbook.'));
    sel ??= names.first;
    final sheet = book.tables[sel]!;
    final rows = sheet.rows.take(400).toList();
    final cols = rows.fold<int>(0, (m, r) => r.length > m ? r.length : m);
    final line = Theme.of(context).colorScheme.outlineVariant;
    return Column(children: [
      if (names.length > 1)
        SizedBox(
          height: 52,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 8), children: [
            for (final n in names)
              Padding(padding: const EdgeInsets.all(6), child: ChoiceChip(label: Text(n), selected: n == sel, onSelected: (_) => setState(() => sel = n))),
          ]),
        ),
      Expanded(
        child: SingleChildScrollView(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: Table(
              defaultColumnWidth: const IntrinsicColumnWidth(),
              border: TableBorder.all(color: line),
              children: [
                for (final r in rows)
                  TableRow(children: [
                    for (var i = 0; i < cols; i++)
                      Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), child: Text(i < r.length ? '${r[i]?.value ?? ''}' : '')),
                  ]),
              ],
            ),
          ),
        ),
      ),
    ]);
  }
}
