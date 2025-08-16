import 'package:flutter/material.dart';
import '../../providers/game_provider.dart';
import '../../services/supabase_service.dart';
import 'room_card.dart';

class RoomsListView extends StatelessWidget {
  final List<GameRoom> rooms;
  final bool isLoading;
  final bool isMyRooms;
  final UserStatus? currentUserStatus;
  final Function(GameRoom) onJoinRoom;
  final Function(GameRoom) onDeleteRoom;

  const RoomsListView({
    super.key,
    required this.rooms,
    required this.isLoading,
    required this.isMyRooms,
    this.currentUserStatus,
    required this.onJoinRoom,
    required this.onDeleteRoom,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 20),
            Text('جاري تحميل الغرف...'),
          ],
        ),
      );
    }

    if (rooms.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isMyRooms ? Icons.inbox : Icons.search_off,
              size: 80,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 20),
            Text(
              isMyRooms ? 'لم تقم بإنشاء أي غرف بعد' : 'لا توجد غرف متاحة حالياً',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              isMyRooms ? 'قم بإنشاء غرفة جديدة!' : 'تحقق مرة أخرى لاحقاً',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(15),
      itemCount: rooms.length,
      itemBuilder: (context, index) {
        final room = rooms[index];
        return RoomCard(
          room: room,
          isMyRoom: isMyRooms,
          currentUserStatus: currentUserStatus,
          onJoinRoom: () => onJoinRoom(room),
          onDeleteRoom: () => onDeleteRoom(room),
        );
      },
    );
  }
}