// lib/src/constants/interaction_enums.dart
import 'package:flutter/material.dart';

/// States for image interaction handling
enum InteractionState {
  idle,
  dragging,
  scaling,
  rotating;

  bool get isActive => this != InteractionState.idle;
}

/// Types of gestures recognized in the canvas
enum GestureType {
  tap,
  doubleTap,
  longPress,
  pan,
  pinch,
  rotate;
}

/// Selection modes for canvas objects
enum SelectionMode {
  single,
  multiple,
  area;
}

/// Canvas view modes
enum ViewMode {
  drawing,
  preview,
  fullscreen;
}

/// Image alignment options for canvas objects
enum AlignmentType {
  left,
  right,
  top,
  bottom,
  centerHorizontal,
  centerVertical;

  String get displayName {
    switch (this) {
      case AlignmentType.left:
        return 'Align Left';
      case AlignmentType.right:
        return 'Align Right';
      case AlignmentType.top:
        return 'Align Top';
      case AlignmentType.bottom:
        return 'Align Bottom';
      case AlignmentType.centerHorizontal:
        return 'Center Horizontally';
      case AlignmentType.centerVertical:
        return 'Center Vertically';
    }
  }

  IconData get icon {
    switch (this) {
      case AlignmentType.left:
        return Icons.format_align_left;
      case AlignmentType.right:
        return Icons.format_align_right;
      case AlignmentType.top:
        return Icons.vertical_align_top;
      case AlignmentType.bottom:
        return Icons.vertical_align_bottom;
      case AlignmentType.centerHorizontal:
        return Icons.format_align_center; // ✅ FIXED: Valid icon
      case AlignmentType.centerVertical:
        return Icons.vertical_align_center; // ✅ FIXED: Valid icon
    }
  }

  String get tooltip {
    switch (this) {
      case AlignmentType.left:
        return 'Align selected images to the left';
      case AlignmentType.right:
        return 'Align selected images to the right';
      case AlignmentType.top:
        return 'Align selected images to the top';
      case AlignmentType.bottom:
        return 'Align selected images to the bottom';
      case AlignmentType.centerHorizontal:
        return 'Center selected images horizontally';
      case AlignmentType.centerVertical:
        return 'Center selected images vertically';
    }
  }
}

/// Image distribution options for canvas objects
enum DistributeType {
  horizontal,
  vertical;

  String get displayName {
    switch (this) {
      case DistributeType.horizontal:
        return 'Distribute Horizontally';
      case DistributeType.vertical:
        return 'Distribute Vertically';
    }
  }

  IconData get icon {
    switch (this) {
      case DistributeType.horizontal:
        return Icons.swap_horiz; // ✅ FIXED: Valid icon for horizontal distribution
      case DistributeType.vertical:
        return Icons.swap_vert; // ✅ FIXED: Valid icon for vertical distribution
    }
  }

  String get tooltip {
    switch (this) {
      case DistributeType.horizontal:
        return 'Distribute selected images horizontally with equal spacing';
      case DistributeType.vertical:
        return 'Distribute selected images vertically with equal spacing';
    }
  }

  /// Minimum number of images required for distribution
  int get minSelectionCount => 3;
}

/// Image transformation types
enum TransformType {
  move,
  scale,
  rotate,
  flip;

  String get displayName {
    switch (this) {
      case TransformType.move:
        return 'Move';
      case TransformType.scale:
        return 'Scale';
      case TransformType.rotate:
        return 'Rotate';
      case TransformType.flip:
        return 'Flip';
    }
  }

  IconData get icon {
    switch (this) {
      case TransformType.move:
        return Icons.open_with;
      case TransformType.scale:
        return Icons.aspect_ratio;
      case TransformType.rotate:
        return Icons.rotate_right;
      case TransformType.flip:
        return Icons.flip;
    }
  }
}

/// Layer ordering operations
enum LayerOperation {
  bringToFront,
  sendToBack,
  bringForward,
  sendBackward;

  String get displayName {
    switch (this) {
      case LayerOperation.bringToFront:
        return 'Bring to Front';
      case LayerOperation.sendToBack:
        return 'Send to Back';
      case LayerOperation.bringForward:
        return 'Bring Forward';
      case LayerOperation.sendBackward:
        return 'Send Backward';
    }
  }

  IconData get icon {
    switch (this) {
      case LayerOperation.bringToFront:
        return Icons.flip_to_front;
      case LayerOperation.sendToBack:
        return Icons.flip_to_back;
      case LayerOperation.bringForward:
        return Icons.keyboard_arrow_up;
      case LayerOperation.sendBackward:
        return Icons.keyboard_arrow_down;
    }
  }
}
