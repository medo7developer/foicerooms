import 'package:flutter/material.dart';

class PlayerNameSection extends StatelessWidget {
  final TextEditingController controller;
  final String? savedPlayerName;
  final bool isInRoom;
  final ValueChanged<String> onNameChanged;

  const PlayerNameSection({
    super.key,
    required this.controller,
    this.savedPlayerName,
    required this.isInRoom,
    required this.onNameChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person, color: Color(0xFF667eea)),
              const SizedBox(width: 10),
              const Text(
                'اسم اللاعب',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              if (savedPlayerName != null) ...[
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'محفوظ',
                    style: TextStyle(
                      color: Colors.green,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 15),
          TextField(
            controller: controller,
            enabled: !isInRoom, // منع التعديل إذا كان في غرفة
            decoration: InputDecoration(
              hintText: 'أدخل اسمك هنا',
              prefixIcon: const Icon(Icons.edit, color: Color(0xFF667eea)),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: isInRoom
                  ? Colors.grey.shade100
                  : const Color(0xFF667eea).withOpacity(0.1),
              contentPadding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
            ),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            onChanged: onNameChanged,
          ),
        ],
      ),
    );
  }
}