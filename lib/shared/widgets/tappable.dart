/// Accessible wrapper for custom-drawn controls.
library;

import 'package:flutter/material.dart';

/// A custom-drawn control made usable by everyone: announced to a screen
/// reader as a button with a name and state, and at least 48×48 to touch,
/// without changing how it looks.
///
/// The app drew most of its small controls — chips, swatches, toggles, the
/// insight refresh — as a bare `GestureDetector` around a decoration. Those
/// are invisible to TalkBack and VoiceOver, or read as an unlabelled
/// "button", and several were 14–24px tall. This keeps the decoration and
/// fixes both.
///
/// 48 is Android's floor and Material's `kMinInteractiveDimension`; iOS asks
/// for 44, so it covers both. The floor is applied by padding the layout around the child, which is
/// what Material's own `MaterialTapTargetSize.padded` does: the visible pill
/// stays the size it was, centred in a larger invisible target.
class Tappable extends StatefulWidget {
  const Tappable({
    super.key,
    required this.onTap,
    required this.child,
    this.label,
    this.hint,
    this.selected,
    this.toggled,
    this.onLongPress,
    this.minSize = kMinInteractiveDimension,
  });

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget child;

  /// What a screen reader says. Needed when [child] has no text of its own —
  /// an icon or a colour swatch. When given, it replaces the child's text
  /// rather than being read alongside it.
  final String? label;

  /// What happens on activation, when the label alone does not say —
  /// "Refreshes the price".
  final String? hint;

  /// For one-of-many choices (a period chip, a swatch).
  final bool? selected;

  /// For on/off switches (Repeat, the notes disclosure).
  final bool? toggled;

  final double minSize;

  @override
  State<Tappable> createState() => _TappableState();
}

class _TappableState extends State<Tappable> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final enabled = w.onTap != null;
    // The GestureDetector sits outside the labelled node, and MergeSemantics
    // joins the two. The other way round, `excludeSemantics` also removed the
    // detector's tap action — a button a screen reader could announce but
    // not press.
    //
    // FocusableActionDetector makes it reachable with Tab and pressable with
    // Enter or Space, which a bare GestureDetector is not — on the desktop
    // builds these controls could not be reached from the keyboard at all.
    return MergeSemantics(
      child: FocusableActionDetector(
        enabled: enabled,
        mouseCursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              w.onTap?.call();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: w.onTap,
          onLongPress: w.onLongPress,
          child: Semantics(
            button: true,
            enabled: enabled,
            selected: w.selected,
            toggled: w.toggled,
            label: w.label,
            hint: w.hint,
            excludeSemantics: w.label != null,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: w.minSize,
                minHeight: w.minSize,
              ),
              child: Center(
                widthFactor: 1,
                heightFactor: 1,
                child: DecoratedBox(
                  position: DecorationPosition.foreground,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border:
                        _focused
                            ? Border.all(
                              color: Theme.of(context).colorScheme.primary,
                              width: 2,
                            )
                            : null,
                  ),
                  child: w.child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
