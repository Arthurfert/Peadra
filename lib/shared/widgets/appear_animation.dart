import 'package:material_ui/material_ui.dart';

/// Staggered entrance of a row: fades in while rising a few pixels, starting
/// [index * 7%] of the animation later so rows flow from top to bottom.
/// Beyond the first [maxSlots] rows the stagger is capped so a long list
/// isn't waiting on its tail.
///
/// State is keyed by the caller's [Key] (typically row id + appear epoch): a
/// plain refresh keeps the same key and the settled row is untouched, while
/// re-entering the view (new epoch, new keys) replays the whole sequence.
/// See [LazyKeepAliveStack.activationSignals] for the refocus plumbing.
class AppearAnimation extends StatefulWidget {
  final int index;
  final Widget child;

  /// Test probe: counts state creations so widget tests can detect an
  /// entrance replaying when it must not.
  @visibleForTesting
  static int createdCount = 0;

  /// For tests.
  static void resetCreatedCount() => createdCount = 0;

  const AppearAnimation({
    required super.key,
    required this.index,
    required this.child,
  });

  @override
  State<AppearAnimation> createState() => _AppearAnimationState();
}

class _AppearAnimationState extends State<AppearAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _curve;

  @override
  void initState() {
    super.initState();
    AppearAnimation.createdCount++;
    // Slot 0..10: each row's slice of the 400ms controller starts ~7% later
    // than the previous one; from slot 10 on, everything animates together
    // in the last third of the controller.
    final start = widget.index.clamp(0, 10) * 0.07;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _curve = CurvedAnimation(
      parent: _controller,
      curve: Interval(start, 1.0, curve: Curves.easeOutCubic),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curve,
      builder: (context, child) {
        final t = _curve.value;
        // No settle flip to the raw child: a type change in the child slot
        // remounts the subtree and would restart any animation inside it.
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 8 * (1.0 - t)),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// Staggered fill of a progress bar: [builder] is driven with a progress
/// value easing from 0 to 1, starting [index * 7%] of the animation later
/// so bars fill from top to bottom. Staggered and settled once at
/// [maxSlots] like [AppearAnimation]; a changed [Key] restarts the fill.
class BarFillAnimation extends StatefulWidget {
  final int index;
  final Widget Function(BuildContext context, double progress) builder;

  const BarFillAnimation({
    required super.key,
    required this.index,
    required this.builder,
  });

  @override
  State<BarFillAnimation> createState() => _BarFillAnimationState();
}

class _BarFillAnimationState extends State<BarFillAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _curve;

  @override
  void initState() {
    super.initState();
    final start = widget.index.clamp(0, 10) * 0.07;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _curve = CurvedAnimation(
      parent: _controller,
      curve: Interval(start, 1.0, curve: Curves.easeOutCubic),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curve,
      builder: (context, _) => widget.builder(context, _curve.value),
    );
  }
}
