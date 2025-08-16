import 'package:flutter/material.dart';
import '../../services/supabase_service.dart';

class CurrentRoomBanner extends StatelessWidget {
  final UserStatus userStatus;
  final VoidCallback onRejoinRoom;

  const CurrentRoomBanner({
    super.key,
    required this.userStatus,
    required this.onRejoinRoom,
  });

  @override
  Widget build(BuildContext context) {
    if (!userStatus.inRoom) return const SizedBox();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.orange.shade100,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.orange, width: 2),
      ),
      child: Row(
        children: [
          Icon(
            userStatus.isOwner ? Icons.star : Icons.meeting_room,
            color: Colors.orange,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'أنت في غرفة: ${userStatus.roomName}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  userStatus.isOwner ? 'أنت مالك الغرفة' : 'أنت عضو في الغرفة',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onRejoinRoom,
            child: const Text('العودة', style: TextStyle(color: Colors.orange)),
          ),
        ],
      ),
    );
  }
}