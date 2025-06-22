// lib/src/extensions/grid_snap_extensions.dart

import 'package:flutter/material.dart';
import 'package:flutter_drawing_board/src/constants/app_constants.dart';

/// Extensions for grid snapping functionality
extension GridSnapExtensions on Offset {
  /// Snap this offset to the nearest grid point if grid snapping is enabled
  Offset snapToGrid({
    required bool snapEnabled,
    double? gridSpacing,
    double? tolerance,
  }) {
    if (!snapEnabled) return this;

    final spacing = gridSpacing ?? AppConstants.gridSpacing;
    final snapTolerance = tolerance ?? AppConstants.gridSnapTolerance;

    // Calculate nearest grid point
    final nearestGridPoint = Offset(
      (dx / spacing).round() * spacing,
      (dy / spacing).round() * spacing,
    );

    // Only snap if within tolerance
    if ((this - nearestGridPoint).distance <= snapTolerance) {
      return nearestGridPoint;
    }

    return this;
  }

  /// Get the nearest grid point without applying it
  Offset getNearestGridPoint({double? gridSpacing}) {
    final spacing = gridSpacing ?? AppConstants.gridSpacing;

    return Offset(
      (dx / spacing).round() * spacing,
      (dy / spacing).round() * spacing,
    );
  }

  /// Check if this point is close to a grid intersection
  bool isNearGridPoint({
    double? gridSpacing,
    double? tolerance,
  }) {
    final snapTolerance = tolerance ?? AppConstants.gridSnapTolerance;
    final nearest = getNearestGridPoint(gridSpacing: gridSpacing);
    return (this - nearest).distance <= snapTolerance;
  }

  /// Snap to sub-grid if closer than main grid
  Offset snapToGridWithSubGrid({
    required bool snapEnabled,
    double? mainGridSpacing,
    double? subGridSpacing,
    double? tolerance,
  }) {
    if (!snapEnabled) return this;

    final mainSpacing = mainGridSpacing ?? AppConstants.gridSpacing;
    final subSpacing = subGridSpacing ?? AppConstants.subGridSpacing;
    final snapTolerance = tolerance ?? AppConstants.gridSnapTolerance;

    // Check sub-grid first (finer snapping)
    final nearestSubGrid = Offset(
      (dx / subSpacing).round() * subSpacing,
      (dy / subSpacing).round() * subSpacing,
    );

    if ((this - nearestSubGrid).distance <= snapTolerance / 2) {
      return nearestSubGrid;
    }

    // Fall back to main grid
    return snapToGrid(
      snapEnabled: true,
      gridSpacing: mainSpacing,
      tolerance: snapTolerance,
    );
  }
}

/// Grid utility functions
class GridUtils {
  GridUtils._();

  /// Get all grid intersection points within a given area
  static List<Offset> getGridIntersections({
    required Size canvasSize,
    double? gridSpacing,
  }) {
    final spacing = gridSpacing ?? AppConstants.gridSpacing;
    final intersections = <Offset>[];

    for (double x = 0; x <= canvasSize.width; x += spacing) {
      for (double y = 0; y <= canvasSize.height; y += spacing) {
        intersections.add(Offset(x, y));
      }
    }

    return intersections;
  }

  /// Check if a point aligns with grid lines
  static bool isOnGridLine({
    required Offset point,
    double? gridSpacing,
    double? tolerance,
  }) {
    final spacing = gridSpacing ?? AppConstants.gridSpacing;
    final snapTolerance = tolerance ?? AppConstants.gridSnapTolerance;

    final xRemainder = point.dx % spacing;
    final yRemainder = point.dy % spacing;

    final xOnGrid = xRemainder <= snapTolerance ||
        xRemainder >= (spacing - snapTolerance);
    final yOnGrid = yRemainder <= snapTolerance ||
        yRemainder >= (spacing - snapTolerance);

    return xOnGrid || yOnGrid;
  }

  /// Get grid lines that intersect with a given rectangle
  static List<Offset> getGridLinesInRect({
    required Rect rect,
    double? gridSpacing,
    bool includeVertical = true,
    bool includeHorizontal = true,
  }) {
    final spacing = gridSpacing ?? AppConstants.gridSpacing;
    final lines = <Offset>[];

    if (includeVertical) {
      final startX = (rect.left / spacing).floor() * spacing;
      for (double x = startX; x <= rect.right; x += spacing) {
        if (x >= rect.left) {
          lines.add(Offset(x, rect.top));
          lines.add(Offset(x, rect.bottom));
        }
      }
    }

    if (includeHorizontal) {
      final startY = (rect.top / spacing).floor() * spacing;
      for (double y = startY; y <= rect.bottom; y += spacing) {
        if (y >= rect.top) {
          lines.add(Offset(rect.left, y));
          lines.add(Offset(rect.right, y));
        }
      }
    }

    return lines;
  }
}