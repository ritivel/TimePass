// Shared "Quiet Interface" primitives used by the shell and every catalog
// component. Motion is feedback-only and respects reduced-motion settings.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'tp_theme.dart';

/// Fade + 12px rise on first build. The one entrance animation every
/// answer component shares.
class TpEnter extends StatefulWidget {
  const TpEnter({super.key, this.delay = Duration.zero, required this.child});

  final Duration delay;
  final Widget child;

  @override
  State<TpEnter> createState() => _TpEnterState();
}

class _TpEnterState extends State<TpEnter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: TpMotion.enter);
  late final CurvedAnimation _anim =
      CurvedAnimation(parent: _controller, curve: TpMotion.enterCurve);
  Timer? _delayTimer;

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      _delayTimer = Timer(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _anim.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return widget.child;
    return FadeTransition(
      opacity: _anim,
      child: AnimatedBuilder(
        animation: _anim,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, 12 * (1 - _anim.value)),
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}

/// The standard answer card: white, large radius, soft shadow, no border.
class TpCard extends StatelessWidget {
  const TpCard({
    super.key,
    this.padding = const EdgeInsets.all(18),
    required this.child,
  });

  final EdgeInsetsGeometry padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.tp;
    return TpEnter(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(color: t.shadow, blurRadius: 20, offset: const Offset(0, 6)),
            BoxShadow(
                color: t.shadow.withValues(alpha: 0.04),
                blurRadius: 2,
                offset: const Offset(0, 1)),
          ],
        ),
        // Material (not a plain color box) so ListTile/ink children paint
        // correctly against the card surface.
        child: Material(
          color: t.card,
          borderRadius: BorderRadius.circular(20),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Card section header: semibold, sentence case ("What you need"),
/// optionally with a trailing widget (e.g. the LIVE badge).
class TpSectionHeader extends StatelessWidget {
  const TpSectionHeader(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final label = Text(text, style: sectionHeader(context));
    if (trailing == null) return label;
    return Row(children: [Expanded(child: label), trailing!]);
  }
}

/// The user's query: quiet gray bubble, right-aligned by the caller.
class QueryBubble extends StatelessWidget {
  const QueryBubble({super.key, required this.text, this.onTap});

  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tp;
    return Material(
      color: t.bubble,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Text(
            text,
            style: TextStyle(fontSize: 14.5, height: 1.4, color: t.ink),
          ),
        ),
      ),
    );
  }
}

/// The waiting state: three quiet dots breathing in sequence — the
/// interface thinking, never a spinner.
class ThinkingDots extends StatefulWidget {
  const ThinkingDots({super.key, this.size = 7});

  final double size;

  @override
  State<ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<ThinkingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tp;
    if (MediaQuery.of(context).disableAnimations) {
      return Text('…', style: TextStyle(color: t.inkMuted));
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++)
            Padding(
              padding: EdgeInsets.only(right: widget.size * 0.7),
              child: _dot(t, i),
            ),
        ],
      ),
    );
  }

  Widget _dot(TpTokens t, int i) {
    final phase = (_controller.value - i * 0.18) % 1.0;
    final wave = 0.5 + 0.5 * math.sin(phase * 2 * math.pi);
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Color.lerp(
            t.inkMuted.withValues(alpha: 0.25), t.inkMuted, wave),
      ),
    );
  }
}

/// Pulsing lamp — LIVE indicators, recording state.
class PulseDot extends StatefulWidget {
  const PulseDot({super.key, required this.color, this.size = 8});

  final Color color;
  final double size;

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: TpMotion.pulse)..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) {
      return Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color),
      );
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final wave = 0.5 + 0.5 * math.sin(_controller.value * 2 * math.pi);
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color.withValues(alpha: 0.45 + 0.55 * wave),
          ),
        );
      },
    );
  }
}

/// LIVE badge: small red lamp + lettering. Content semantics, kept quiet.
class LiveBadge extends StatelessWidget {
  const LiveBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tp;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PulseDot(color: t.signalRed, size: 7),
        const SizedBox(width: 5),
        Text('LIVE',
            style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: t.signalRed)),
      ],
    );
  }
}

/// Empty-state category tile: soft gray cell with a generated 3D object,
/// a label, and the query it fires — the ingredient-tile pattern.
class SampleTile extends StatelessWidget {
  const SampleTile({
    super.key,
    required this.asset,
    required this.label,
    required this.query,
    required this.onTap,
  });

  final String asset;
  final String label;
  final String query;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tp;
    return Material(
      color: t.tile,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(asset, height: 64, filterQuality: FilterQuality.medium),
              const SizedBox(height: 10),
              Text(label,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                      color: t.ink)),
              const SizedBox(height: 2),
              Text(
                query,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: caption(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
