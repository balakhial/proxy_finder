import 'package:flutter/material.dart';

enum AppMessageType { success, error, info, warning }

class AppMessage {
  AppMessage._();

  static void show(
    BuildContext context, {
    required String message,
    AppMessageType type = AppMessageType.success,
    Duration duration = const Duration(seconds: 3),
  }) {
    const colors = {
      AppMessageType.success: Color(0xFF4D956B),
      AppMessageType.error: Color(0xFFD85C5C),
      AppMessageType.info: Color(0xFF5796C8),
      AppMessageType.warning: Color(0xFFE2A84B),
    };
    const icons = {
      AppMessageType.success: Icons.check_circle_outline,
      AppMessageType.error: Icons.error_outline,
      AppMessageType.info: Icons.info_outline,
      AppMessageType.warning: Icons.warning_amber_rounded,
    };

    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(icons[type], color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: colors[type],
          behavior: SnackBarBehavior.floating,
          duration: duration,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
  }
}
