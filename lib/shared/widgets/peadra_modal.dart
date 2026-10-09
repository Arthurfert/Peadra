import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/providers/theme_provider.dart';
import '../../core/responsive/responsive_layout.dart';
import '../../core/theme/peadra_colors.dart';

/// A modal with a title, a body and action buttons that adapts to the
/// screen size: docked to the bottom of the screen on phones (like the
/// transaction details sheet), centered dialog on larger screens.
///
/// Show it via [showPeadraModal], which picks the matching route
/// ([showModalBottomSheet] on phones, [showDialog] otherwise).
///
/// The [content] must be intrinsically sized (no [Expanded]/[Flexible], no
/// unbounded-height scrolling widgets): on phones the whole sheet — title,
/// content and actions — scrolls as one when it exceeds the screen.
///
/// [PeadraModal] can be nested inside any state holder ([StatefulBuilder]
/// around it or a dedicated [StatefulWidget] returning it); the layout is
/// decided at build time from the available screen width.
class PeadraModal extends StatelessWidget {
  final Widget? title;
  final Widget content;
  final List<Widget>? actions;

  const PeadraModal({
    super.key,
    this.title,
    required this.content,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final themeName = context.watch<ThemeProvider>().themeName;
    final colors = PeadraTheme.getColors(themeName);
    if (ResponsiveLayout.isPhone(context)) {
      return _buildSheet(context, colors);
    }
    return AlertDialog(
      backgroundColor: colors.surface,
      title: title,
      content: content,
      actions: actions,
    );
  }

  Widget _buildSheet(BuildContext context, PeadraColors colors) {
    final actions = this.actions;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        12,
        24,
        24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color:
                        colors.placeholderColor.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              if (title != null) ...[
                const SizedBox(height: 16),
                title!,
              ],
              const SizedBox(height: 12),
              content,
              if (actions != null && actions.isNotEmpty) ...[
                const SizedBox(height: 20),
                Row(
                  children: [
                    for (int i = 0; i < actions.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(child: _sheetAction(actions[i])),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Secondary ([TextButton]) actions render outlined in sheets, like the
/// Cancel button of the transaction details modal. Primary
/// (elevated/filled) actions and desktop dialogs keep their styling.
Widget _sheetAction(Widget action) {
  if (action is! TextButton) return action;
  return OutlinedButton(
    onPressed: action.onPressed,
    onLongPress: action.onLongPress,
    style: action.style,
    focusNode: action.focusNode,
    autofocus: action.autofocus,
    child: action.child ?? const SizedBox.shrink(),
  );
}

/// Shows a modal docked to the bottom on phones and as a centered dialog
/// on larger screens. Returns the value passed to [Navigator.pop].
///
/// The [builder] can return a [PeadraModal] directly or any widget that
/// builds one (e.g. a [StatefulWidget] or [StatefulBuilder]): the layout
/// adapts at build time.
Future<T?> showPeadraModal<T>({
  required BuildContext context,
  required Widget Function(BuildContext dialogContext) builder,
}) {
  if (ResponsiveLayout.isPhone(context)) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: builder,
    );
  }
  return showDialog<T>(
    context: context,
    builder: builder,
  );
}
