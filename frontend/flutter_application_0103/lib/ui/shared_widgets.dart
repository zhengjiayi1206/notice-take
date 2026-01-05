import 'dart:math' as math;

import 'package:flutter/material.dart';

class SectionTitle extends StatelessWidget {
  const SectionTitle({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.black54),
          ),
        ],
      ],
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.title, required this.description});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54),
          ),
        ],
      ),
    );
  }
}

class InfoPill extends StatelessWidget {
  const InfoPill({super.key, required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F7FB),
        borderRadius: BorderRadius.circular(20),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: const Color(0xFF146C94)),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Minimal futuristic app background:
/// - soft off-white base
/// - subtle flowing light/depth (blurred blobs)
/// - hint of teal AI glow
/// - low contrast, no sharp elements
class FuturisticBackground extends StatelessWidget {
  const FuturisticBackground({
    super.key,
    this.child,
    this.animate = false,
  });

  final Widget? child;

  /// 如果想要“微微流动”的效果，设为 true。
  /// 默认 false（静态背景更省电、更稳定）。
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final bg = CustomPaint(
      painter: _FuturisticBackgroundPainter(
        time: 0,
      ),
      child: child,
    );

    if (!animate) return bg;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(seconds: 8),
      curve: Curves.linear,
      onEnd: () {},
      builder: (context, t, _) {
        // 循环动画：用 (t*2π) 来驱动轻微偏移
        return CustomPaint(
          painter: _FuturisticBackgroundPainter(time: t),
          child: child,
        );
      },
    );
  }
}

class _FuturisticBackgroundPainter extends CustomPainter {
  _FuturisticBackgroundPainter({required this.time});

  /// 0..1
  final double time;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // 1) 底色：off-white + very light gray 的柔和渐变
    final basePaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFFF7F8FA), // off-white
          Color(0xFFF1F3F6), // very light gray
        ],
        stops: [0.0, 1.0],
      ).createShader(rect);

    canvas.drawRect(rect, basePaint);

    // 2) 轻微“深度”层：非常低对比的径向渐变（像雾一样）
    final depthPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.2, -0.4),
        radius: 1.2,
        colors: [
          const Color(0xFFFFFFFF).withOpacity(0.55),
          const Color(0xFFEDEFF3).withOpacity(0.00),
        ],
        stops: const [0.0, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, depthPaint);

    // 3) AI teal glow：几团非常柔和的“光晕”（无锐利边缘）
    // 通过 blur + opacity 控制“克制”
    final t = time * 2 * math.pi;

    _drawGlow(
      canvas,
      size,
      center: Offset(size.width * (0.72 + 0.02 * math.sin(t)),
          size.height * (0.28 + 0.02 * math.cos(t))),
      radius: size.shortestSide * 0.55,
      color: const Color(0xFF22B7B0).withOpacity(0.10), // teal glow
      blurSigma: 60,
    );

    _drawGlow(
      canvas,
      size,
      center: Offset(size.width * (0.25 + 0.02 * math.cos(t * 0.8)),
          size.height * (0.65 + 0.02 * math.sin(t * 0.8))),
      radius: size.shortestSide * 0.70,
      color: const Color(0xFF1AA6A1).withOpacity(0.08),
      blurSigma: 70,
    );

    // 4) “very subtle flowing light”：一条很淡的流动光带（低对比、无图案感）
    final bandCenterY = size.height * (0.42 + 0.02 * math.sin(t * 0.6));
    final bandRect = Rect.fromLTWH(0, bandCenterY - size.height * 0.18,
        size.width, size.height * 0.36);

    final bandPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Colors.white.withOpacity(0.00),
          Colors.white.withOpacity(0.08),
          const Color(0xFF22B7B0).withOpacity(0.05),
          Colors.white.withOpacity(0.06),
          Colors.white.withOpacity(0.00),
        ],
        stops: const [0.0, 0.28, 0.55, 0.78, 1.0],
      ).createShader(bandRect)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);

    canvas.drawRect(bandRect, bandPaint);

    // 5) 可选：极轻微噪点质感（避免“纯渐变太塑料”）
    // 用点状透明叠加，控制到几乎看不见
    _drawSubtleNoise(canvas, size);
  }

  void _drawGlow(
    Canvas canvas,
    Size size, {
    required Offset center,
    required double radius,
    required Color color,
    required double blurSigma,
  }) {
    final glowRect = Rect.fromCircle(center: center, radius: radius);

    final glowPaint = Paint()
      ..shader = RadialGradient(
        center: Alignment(
          (center.dx / size.width) * 2 - 1,
          (center.dy / size.height) * 2 - 1,
        ),
        radius: 1.0,
        colors: [
          color,
          color.withOpacity(0.0),
        ],
        stops: const [0.0, 1.0],
      ).createShader(glowRect)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, blurSigma);

    canvas.drawCircle(center, radius, glowPaint);
  }

  void _drawSubtleNoise(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withOpacity(0.015);
    final rng = math.Random(7); // 固定种子：每次一致（更“UI”）
    final count = (size.width * size.height / 12000).clamp(80, 240).toInt();

    for (int i = 0; i < count; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height;
      final r = rng.nextDouble() * 1.2 + 0.2;
      canvas.drawCircle(Offset(x, y), r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _FuturisticBackgroundPainter oldDelegate) {
    // 如果你开启 animate=true，就会不断重绘（time 会变化）
    return oldDelegate.time != time;
  }
}
