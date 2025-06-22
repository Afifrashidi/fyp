import 'package:flutter/material.dart';

class TextInputDialog {
  static Future<String?> show(
      BuildContext context, {
        required double fontSize,
        required Color color,
      }) async {
    final controller = TextEditingController();

    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Text'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Enter text...',
            border: OutlineInputBorder(),
          ),
          style: TextStyle(fontSize: fontSize, color: color),
          autofocus: true,
          maxLines: null,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}