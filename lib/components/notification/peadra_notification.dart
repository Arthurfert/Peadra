import 'package:flutter/material.dart';

enum NotificationType { success, error, warning, info }

class PeadraNotification {
  static void show(
    BuildContext context, {
    required String message,
    NotificationType type = NotificationType.success,
  }) {
    final state = Overlay.of(context);
    final colors = _getColors(type);

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _NotificationWidget(
        message: message,
        backgroundColor: colors.$1,
        icon: colors.$2,
        iconColor: colors.$3,
        onDismiss: () => entry.remove(),
      ),
    );

    state.insert(entry);
  }

  static (Color, IconData, Color) _getColors(NotificationType type) {
    switch (type) {
      case NotificationType.success:
        return (
          const Color(0xFF10B981),
          Icons.check_circle,
          Colors.white,
        );
      case NotificationType.error:
        return (
          const Color(0xFFEF4444),
          Icons.error,
          Colors.white,
        );
      case NotificationType.warning:
        return (
          const Color(0xFFF59E0B),
          Icons.warning_amber_rounded,
          Colors.white,
        );
      case NotificationType.info:
        return (
          const Color(0xFF3B82F6),
          Icons.info,
          Colors.white,
        );
    }
  }
}

class _NotificationWidget extends StatefulWidget {
  final String message;
  final Color backgroundColor;
  final IconData icon;
  final Color iconColor;
  final VoidCallback onDismiss;

  const _NotificationWidget({
    required this.message,
    required this.backgroundColor,
    required this.icon,
    required this.iconColor,
    required this.onDismiss,
  });

  @override
  State<_NotificationWidget> createState() => _NotificationWidgetState();
}

class _NotificationWidgetState extends State<_NotificationWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _fadeAnimation;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));

    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _controller.forward();

    Future.delayed(const Duration(seconds: 4), () {
      if (!_disposed) {
        _controller.reverse().then((_) {
          if (!_disposed) widget.onDismiss();
        });
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 24,
      right: 24,
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: widget.backgroundColor,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: widget.backgroundColor.withValues(alpha: 0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(widget.icon, color: widget.iconColor, size: 20),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      widget.message,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
