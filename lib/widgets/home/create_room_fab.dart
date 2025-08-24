import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/user_providers/auth_provider.dart';

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

// تعديل lib/widgets/home/create_room_fab.dart
// استبدل دالة build بهذه النسخة:

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        // تحديد إمكانية الإنشاء بناءً على حالة المصادقة
        final canCreateRoom = authProvider.isAuthenticated &&
            authProvider.playerName.isNotEmpty &&
            !isInRoom;

        return AnimatedBuilder(
          animation: controller,
          builder: (context, child) {
            return Transform.scale(
              scale: 1.0 + (controller.value * 0.1),
              child: FloatingActionButton.extended(
                onPressed: canCreateRoom ? onCreateRoom : null,
                icon: const Icon(Icons.add),
                label: Text(
                    isInRoom
                        ? 'في غرفة'
                        : authProvider.isAuthenticated
                        ? 'إنشاء غرفة'
                        : 'سجل دخولك أولاً'
                ),
                backgroundColor: canCreateRoom ? const Color(0xFF667eea) : Colors.grey,
                foregroundColor: Colors.white,
                elevation: 8,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
              ),
            );
          },
        );
      },
    );
  }
}