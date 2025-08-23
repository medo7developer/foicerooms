import 'package:flutter/material.dart';

class CreatingRoomInfoWidget extends StatelessWidget {
  const CreatingRoomInfoWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return const Text(
      'يرجى الانتظار، جاري إنشاء الغرفة وإعداد الإعدادات...',
      style: TextStyle(
        fontSize: 12,
        color: Colors.grey,
        fontStyle: FontStyle.italic,
      ),
      textAlign: TextAlign.center,
    );
  }
}