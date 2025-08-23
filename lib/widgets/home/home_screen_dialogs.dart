import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:developer';
import '../../models/game_room_model.dart';
import '../../screens/game_screen.dart';
import '../../services/player_service.dart';
import '../../services/supabase_service.dart';
import '../../providers/game_provider.dart';

class HomeScreenDialogs {
  // عرض مربع حوار للمستخدم الموجود في غرفة
  static void showUserInRoomDialog({
    required BuildContext context,
    required UserStatus currentUserStatus,
    required VoidCallback onLeaveRoom,
    required VoidCallback onRejoinRoom,
  }) {
    if (currentUserStatus.inRoom != true) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.info, color: Colors.blue.shade600),
            const SizedBox(width: 10),
            const Text('أنت في غرفة نشطة'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('أنت موجود حالياً في غرفة:'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    currentUserStatus.isOwner == true ? Icons.star : Icons.meeting_room,
                    color: Colors.blue,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          currentUserStatus.roomName ?? 'غير معروف',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          currentUserStatus.isOwner == true ? 'أنت مالك الغرفة' : 'أنت عضو في الغرفة',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              onLeaveRoom();
            },
            child: const Text('مغادرة الغرفة', style: TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              onRejoinRoom();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            child: const Text('العودة للغرفة', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // عرض مربع حوار لحذف الغرفة
  static Future<bool?> showDeleteDialog(BuildContext context, GameRoom room) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.red),
            SizedBox(width: 10),
            Text('حذف الغرفة'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('هل تريد حذف الغرفة "${room.name}"؟'),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'تحذير: سيتم إخراج جميع اللاعبين من الغرفة',
                style: TextStyle(fontSize: 12, color: Colors.red),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('حذف', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // عرض مربع حوار الانضمام للغرفة
  static void showJoiningRoomDialog(BuildContext context, String roomName) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text('جاري الانضمام لغرفة "$roomName"...'),
          ],
        ),
      ),
    );
  }

  // إعادة الانضمام للغرفة
  static Future<void> rejoinRoom({
    required BuildContext context,
    required UserStatus? currentUserStatus,
    required String? playerId,
  }) async {
    if (currentUserStatus?.roomId == null || playerId == null) return;

    try {
      final gameProvider = context.read<GameProvider>();
      final supabaseService = context.read<SupabaseService>();

      // محاولة إعادة الانضمام للغرفة
      final room = await supabaseService.getRoomById(currentUserStatus!.roomId!);

      if (room != null) {
        // تحديث GameProvider بمعلومات الغرفة
        gameProvider.rejoinRoom(room, playerId);

        // الانتقال لشاشة اللعبة
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => GameScreen(playerId: playerId),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('الغرفة غير موجودة'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      log('خطأ في إعادة الانضمام: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('فشل في العودة للغرفة'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}