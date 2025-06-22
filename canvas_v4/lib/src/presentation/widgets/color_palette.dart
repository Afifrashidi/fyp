// lib/src/presentation/widgets/color_palette.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_drawing_board/src/constants/app_constants.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ColorPalette extends StatefulWidget {
  final ValueNotifier<Color> selectedColor;

  const ColorPalette({Key? key, required this.selectedColor}) : super(key: key);

  @override
  State<ColorPalette> createState() => _ColorPaletteState();
}

class _ColorPaletteState extends State<ColorPalette> {
  List<Color> _customColors = [];

  @override
  void initState() {
    super.initState();
    _loadCustomColors();
  }

  Future<void> _loadCustomColors() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final colorStrings = prefs.getStringList(AppConstants.customColorsKey) ?? [];

      setState(() {
        _customColors = colorStrings
            .map((colorString) => Color(int.parse(colorString)))
            .toList();
      });
    } catch (e) {
      debugPrint('Error loading custom colors: $e');
    }
  }

  Future<void> _saveCustomColors() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final colorStrings = _customColors
          .map((color) => color.value.toString())
          .toList();

      await prefs.setStringList(AppConstants.customColorsKey, colorStrings);
    } catch (e) {
      debugPrint('Error saving custom colors: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: widget.selectedColor,
      builder: (context, selectedColor, child) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Default color palette
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: AppColors.defaultPalette.map((color) {
                return _ColorBox(
                  color: color,
                  isSelected: color == selectedColor,
                  onTap: () => widget.selectedColor.value = color,
                  tooltip: _getColorName(color),
                );
              }).toList(),
            ),

            // Custom colors section
            if (_customColors.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text(
                'Custom Colors',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: _customColors.map((color) {
                  return _ColorBox(
                    color: color,
                    isSelected: color == selectedColor,
                    onTap: () => widget.selectedColor.value = color,
                    onLongPress: () => _removeCustomColor(color),
                    tooltip: 'Custom color\nLong press to remove',
                    showRemoveIcon: true,
                  );
                }).toList(),
              ),
            ],

            // Add custom color button
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _showColorPicker,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Custom Color'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  String _getColorName(Color color) {
    if (color == Colors.black) return 'Black';
    if (color == Colors.white) return 'White';
    if (color == Colors.red) return 'Red';
    if (color == Colors.green) return 'Green';
    if (color == Colors.blue) return 'Blue';
    if (color == Colors.yellow) return 'Yellow';
    if (color == Colors.orange) return 'Orange';
    if (color == Colors.purple) return 'Purple';
    if (color == Colors.pink) return 'Pink';
    if (color == Colors.cyan) return 'Cyan';
    if (color == Colors.brown) return 'Brown';
    if (color == Colors.grey) return 'Grey';
    return 'Color #${color.value.toRadixString(16).substring(2).toUpperCase()}';
  }

  void _showColorPicker() async {
    final Color? pickedColor = await showDialog<Color>(
      context: context,
      builder: (context) => _ColorPickerDialog(
        initialColor: widget.selectedColor.value,
      ),
    );

    if (pickedColor != null) {
      widget.selectedColor.value = pickedColor;
      _addCustomColor(pickedColor);
    }
  }

  void _addCustomColor(Color color) {
    if (!_customColors.contains(color) &&
        !AppColors.defaultPalette.contains(color)) {
      setState(() {
        _customColors.add(color);
        // Limit custom colors to 12
        if (_customColors.length > 12) {
          _customColors.removeAt(0);
        }
      });

      _saveCustomColors();

      // Show feedback
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(SuccessMessages.colorAdded),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _removeCustomColor(Color color) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Color'),
        content: const Text('Remove this custom color from the palette?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _customColors.remove(color);
              });
              _saveCustomColors();
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }
}

class _ColorBox extends StatelessWidget {
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final String? tooltip;
  final bool showRemoveIcon;

  const _ColorBox({
    required this.color,
    required this.isSelected,
    required this.onTap,
    this.onLongPress,
    this.tooltip,
    this.showRemoveIcon = false,
  });

  @override
  Widget build(BuildContext context) {
    Widget colorBox = GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        height: 32,
        width: 32,
        decoration: BoxDecoration(
          color: color,
          border: Border.all(
            color: isSelected ? AppColors.selectedToolBorder : Colors.grey.shade300,
            width: isSelected ? 3 : 1,
          ),
          borderRadius: BorderRadius.circular(4),
          boxShadow: isSelected
              ? [const BoxShadow(
            color: Colors.black26,
            blurRadius: 4,
            offset: Offset(0, 2),
          )]
              : null,
        ),
        child: showRemoveIcon && onLongPress != null
            ? Icon(
          Icons.close,
          size: 12,
          color: color.computeLuminance() > 0.5 ? Colors.black : Colors.white,
        )
            : null,
      ),
    );

    if (tooltip != null) {
      return Tooltip(
        message: tooltip!,
        child: colorBox,
      );
    }

    return colorBox;
  }
}

class _ColorPickerDialog extends StatefulWidget {
  final Color initialColor;

  const _ColorPickerDialog({required this.initialColor});

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late Color _currentColor;
  late HSVColor _hsvColor;
  final TextEditingController _hexController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _currentColor = widget.initialColor;
    _hsvColor = HSVColor.fromColor(_currentColor);
    _updateHexField();
  }

  void _updateHexField() {
    _hexController.text = _currentColor.value.toRadixString(16).substring(2).toUpperCase();
  }

  void _updateFromHex(String hex) {
    try {
      final color = Color(int.parse('FF$hex', radix: 16));
      setState(() {
        _currentColor = color;
        _hsvColor = HSVColor.fromColor(color);
      });
    } catch (e) {
      // Invalid hex, ignore
    }
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Choose Color'),
      content: SizedBox(
        width: 300,
        height: 420,
        child: Column(
          children: [
            // Current color preview
            Container(
              height: 60,
              width: double.infinity,
              decoration: BoxDecoration(
                color: _currentColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Center(
                child: Text(
                  '#${_currentColor.value.toRadixString(16).substring(2).toUpperCase()}',
                  style: TextStyle(
                    color: _currentColor.computeLuminance() > 0.5
                        ? Colors.black : Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Hex input field
            TextFormField(
              controller: _hexController,
              decoration: const InputDecoration(
                labelText: 'Hex Color',
                prefixText: '#',
                border: OutlineInputBorder(),
              ),
              maxLength: 6,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9A-Fa-f]')),
              ],
              onChanged: _updateFromHex,
            ),

            const SizedBox(height: 16),

            // Hue slider
            const Text('Hue', style: TextStyle(fontWeight: FontWeight.w500)),
            Slider(
              value: _hsvColor.hue,
              min: 0,
              max: 360,
              onChanged: (value) {
                setState(() {
                  _hsvColor = _hsvColor.withHue(value);
                  _currentColor = _hsvColor.toColor();
                  _updateHexField();
                });
              },
            ),

            // Saturation slider
            const Text('Saturation', style: TextStyle(fontWeight: FontWeight.w500)),
            Slider(
              value: _hsvColor.saturation,
              min: 0,
              max: 1,
              onChanged: (value) {
                setState(() {
                  _hsvColor = _hsvColor.withSaturation(value);
                  _currentColor = _hsvColor.toColor();
                  _updateHexField();
                });
              },
            ),

            // Value/Brightness slider
            const Text('Brightness', style: TextStyle(fontWeight: FontWeight.w500)),
            Slider(
              value: _hsvColor.value,
              min: 0,
              max: 1,
              onChanged: (value) {
                setState(() {
                  _hsvColor = _hsvColor.withValue(value);
                  _currentColor = _hsvColor.toColor();
                  _updateHexField();
                });
              },
            ),

            // Alpha slider
            const Text('Opacity', style: TextStyle(fontWeight: FontWeight.w500)),
            Slider(
              value: _hsvColor.alpha,
              min: 0,
              max: 1,
              onChanged: (value) {
                setState(() {
                  _hsvColor = _hsvColor.withAlpha(value);
                  _currentColor = _hsvColor.toColor();
                  _updateHexField();
                });
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(_currentColor),
          child: const Text('Select'),
        ),
      ],
    );
  }
}