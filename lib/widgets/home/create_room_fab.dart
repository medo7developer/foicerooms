import 'package:flutter/material.dart';

class CreateRoomFab extends StatelessWidget {
  final AnimationController controller;
  final bool canCreate;
  final bool isInRoom;
  final VoidCallback onCreateRoom;

  const CreateRoomFab({
    super.key,
    required this.controller,
    required this.canCreate,
    required this.isInRoom,
    required this.onCreateRoom,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        return Transform.scale(
          scale: 1.0 + (controller.value * 0.1),
          child: FloatingActionButton.extended(
            onPressed: canCreate ? onCreateRoom : null,
            icon: const Icon(Icons.add),
            label: Text(isInRoom ? 'في غرفة' : 'إنشاء غرفة'),
            backgroundColor: canCreate ? const Color(0xFF667eea) : Colors.grey,
            foregroundColor: Colors.white,
            elevation: 8,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(25),
            ),
          ),
        );
      },
    );
  }
}