import 'package:flutter/material.dart';
import '../../services/supabase_service.dart';

class FloatingCreateButton extends StatelessWidget {
  final AnimationController controller;
  final bool canCreate;
  final UserStatus? currentUserStatus;
  final String playerName;
  final String? playerId;
  final VoidCallback onPressed;

  const FloatingCreateButton({
    super.key,
    required this.controller,
    required this.canCreate,
    required this.currentUserStatus,
    required this.playerName,
    required this.playerId,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        return Transform.scale(
          scale: 1.0 + (controller.value * 0.1),
          child: FloatingActionButton.extended(
            onPressed: canCreate ? onPressed : null,
            icon: const Icon(Icons.add),
            label: Text(currentUserStatus?.inRoom == true ? 'في غرفة' : 'إنشاء غرفة'),
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