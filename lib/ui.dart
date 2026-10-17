import 'dart:math' as math;

import 'package:flutter/material.dart';

const kSeed = Color(0xFF6C5CE7);
const kSeed2 = Color(0xFF9B59F6);

Color op(Color c, double o) => c.withAlpha((o * 255).round());

ThemeData buildTheme(Brightness b) {
  final cs = ColorScheme.fromSeed(seedColor: kSeed, brightness: b);
  return ThemeData(
    useMaterial3: true,
    colorScheme: cs,
    scaffoldBackgroundColor: Colors.transparent,
    appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, elevation: 0, scrolledUnderElevation: 0),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: op(b == Brightness.dark ? Colors.white : Colors.white, b == Brightness.dark ? .08 : .85),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: kSeed, width: 2)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: op(cs.surface, .85),
      indicatorColor: op(kSeed, .25),
      height: 70,
    ),
  );
}

/// Slowly drifting gradient behind the whole app.
class AnimatedBg extends StatefulWidget {
  final Widget child;
  const AnimatedBg({super.key, required this.child});
  @override
  State<AnimatedBg> createState() => _AnimatedBgState();
}

class _AnimatedBgState extends State<AnimatedBg> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 14))..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final colors = dark
        ? const [Color(0xFF0F0C29), Color(0xFF302B63), Color(0xFF24243E)]
        : const [Color(0xFFEEF0FF), Color(0xFFDCD6FF), Color(0xFFF3E8FF)];
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.lerp(Alignment.topLeft, Alignment.topRight, _c.value)!,
            end: Alignment.lerp(Alignment.bottomRight, Alignment.bottomLeft, _c.value)!,
            colors: colors,
          ),
        ),
        child: child,
      ),
      child: widget.child,
    );
  }
}

/// Gradient button with hover lift and press-down feedback.
class GlowButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool loading;
  final bool outlined;
  final bool danger;
  const GlowButton({super.key, required this.label, this.icon, this.onTap, this.loading = false, this.outlined = false, this.danger = false});
  @override
  State<GlowButton> createState() => _GlowButtonState();
}

class _GlowButtonState extends State<GlowButton> {
  bool _hover = false, _down = false;
  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null && !widget.loading;
    final colors = widget.danger ? const [Color(0xFFE11D48), Color(0xFFFB7185)] : const [kSeed, kSeed2];
    final fg = widget.outlined ? Theme.of(context).colorScheme.onSurface : Colors.white;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        onTap: enabled ? widget.onTap : null,
        child: AnimatedScale(
          scale: _down ? .95 : (_hover ? 1.03 : 1),
          duration: const Duration(milliseconds: 120),
          child: AnimatedOpacity(
            opacity: enabled || widget.loading ? 1 : .5,
            duration: const Duration(milliseconds: 150),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
              decoration: BoxDecoration(
                gradient: widget.outlined ? null : LinearGradient(colors: colors),
                color: widget.outlined ? op(Colors.white, .12) : null,
                border: widget.outlined ? Border.all(color: op(kSeed, .5)) : null,
                borderRadius: BorderRadius.circular(16),
                boxShadow: widget.outlined
                    ? null
                    : [BoxShadow(color: op(colors[0], _hover ? .55 : .35), blurRadius: _hover ? 26 : 16, offset: const Offset(0, 8))],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
                if (widget.loading)
                  SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: fg))
                else if (widget.icon != null) ...[Icon(widget.icon, color: fg, size: 20), const SizedBox(width: 10)],
                if (!widget.loading) Flexible(child: Text(widget.label, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 15))),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets margin;
  final VoidCallback? onTap;
  const GlassCard({super.key, required this.child, this.padding = const EdgeInsets.all(18), this.margin = const EdgeInsets.symmetric(vertical: 7), this.onTap});
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final r = BorderRadius.circular(22);
    return Padding(
      padding: margin,
      child: Material(
        color: op(Colors.white, dark ? .07 : .72),
        borderRadius: r,
        child: InkWell(
          onTap: onTap,
          borderRadius: r,
          child: Container(
            padding: padding,
            decoration: BoxDecoration(borderRadius: r, border: Border.all(color: op(Colors.white, dark ? .12 : .85))),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Fades and slides a child in when it first appears.
class FadeSlide extends StatelessWidget {
  final Widget child;
  final int index;
  const FadeSlide({super.key, required this.child, this.index = 0});
  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 380 + math.min(index, 8) * 70),
      curve: Curves.easeOutCubic,
      builder: (_, v, c) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, 18 * (1 - v)), child: c)),
      child: child,
    );
  }
}

/// Animated circular progress used for semester and tutor progress.
class ProgressRing extends StatelessWidget {
  final double value;
  final double size;
  final String? caption;
  const ProgressRing({super.key, required this.value, this.size = 160, this.caption});
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (_, v, __) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(v, op(dark ? Colors.white : kSeed, .14)),
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('${(v * 100).round()}%', style: TextStyle(fontSize: size * .22, fontWeight: FontWeight.w800)),
              if (caption != null) Text(caption!, style: TextStyle(fontSize: size * .09, color: op(Theme.of(context).colorScheme.onSurface, .65))),
            ]),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double v;
  final Color track;
  _RingPainter(this.v, this.track);
  @override
  void paint(Canvas canvas, Size s) {
    final stroke = s.width * .09;
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, s.width - stroke, s.height - stroke);
    canvas.drawArc(rect, 0, math.pi * 2, false, Paint()..style = PaintingStyle.stroke..strokeWidth = stroke..color = track);
    if (v <= 0) return;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * v,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = const SweepGradient(startAngle: -math.pi / 2, endAngle: math.pi * 1.5, colors: [kSeed, kSeed2, Color(0xFF22D3EE)]).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.v != v || o.track != track;
}

void snack(BuildContext c, String m) {
  ScaffoldMessenger.of(c).hideCurrentSnackBar();
  ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))));
}

String fmtSize(num b) => b > 1048576 ? '${(b / 1048576).toStringAsFixed(1)} MB' : '${(b / 1024).ceil()} KB';
