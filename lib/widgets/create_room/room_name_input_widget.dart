import 'package:flutter/material.dart';

class RoomNameInputWidget extends StatelessWidget {
  final TextEditingController controller;
  final bool isEnabled;

  const RoomNameInputWidget({
    super.key,
    required this.controller,
    required this.isEnabled,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: isEnabled,
      decoration: InputDecoration(
        hintText: 'أدخل اسم الغرفة',
        prefixIcon: const Icon(Icons.meeting_room),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
        ),
        filled: true,
        fillColor: isEnabled ? Colors.grey.shade50 : Colors.grey.shade100,
      ),
      maxLength: 30,
    );
  }
}