import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class HotkeyListener extends StatelessWidget {
  final Widget child;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;

  const HotkeyListener({
    Key? key,
    required this.child,
    this.onUndo,
    this.onRedo,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return RawKeyboardListener(
      focusNode: FocusNode(),
      autofocus: true,
      onKey: (RawKeyEvent event) {
        if (event is RawKeyDownEvent) {
          if (event.isControlPressed) {
            if (event.logicalKey == LogicalKeyboardKey.keyZ) {
              if (event.isShiftPressed) {
                onRedo?.call();
              } else {
                onUndo?.call();
              }
            } else if (event.logicalKey == LogicalKeyboardKey.keyY) {
              onRedo?.call();
            }
          }
        }
      },
      child: child,
    );
  }
}