import 'package:flutter/material.dart';
import '../../providers/game_provider.dart';
import '../../services/player_service.dart';
import '../../services/supabase_service.dart';
import '../../models/game_room_model.dart';
import '../../models/player_model.dart';

class RoomCard extends StatelessWidget {
  final GameRoom room;
  final bool isMyRoom;
  final UserStatus? currentUserStatus;
  final VoidCallback onJoinRoom;
  final VoidCallback onDeleteRoom;

  const RoomCard({
    super.key,
    required this.room,
    required this.isMyRoom,
    this.currentUserStatus,
    required this.onJoinRoom,
    required this.onDeleteRoom,
  });

  @override
  Widget build(BuildContext context) {
    final playersCount = room.players.length;
    final maxPlayers = room.maxPlayers;
    final isFull = playersCount >= maxPlayers;
    final fillPercentage = playersCount / maxPlayers;
    final canJoin = !isFull && !isMyRoom && currentUserStatus?.inRoom != true;

    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            isFull ? Colors.grey.shade100 : const Color(0xFF667eea).withOpacity(0.1),
            isFull ? Colors.grey.shade200 : const Color(0xFF764ba2).withOpacity(0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isFull ? Colors.grey.shade300 : const Color(0xFF667eea).withOpacity(0.3),
          width: 2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildRoomHeader(isFull),
            const SizedBox(height: 15),
            _buildProgressBar(fillPercentage, isFull),
            const SizedBox(height: 15),
            _buildActionButtons(canJoin),
          ],
        ),
      ),
    );
  }

  Widget _buildRoomHeader(bool isFull) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isFull ? Colors.grey : const Color(0xFF667eea),
            shape: BoxShape.circle,
          ),
          child: Icon(
            isMyRoom ? Icons.star : Icons.groups,
            color: Colors.white,
            size: 24,
          ),
        ),
        const SizedBox(width: 15),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      room.name,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isFull ? Colors.grey : Colors.black87,
                      ),
                    ),
                  ),
                  if (isMyRoom)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.amber,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'مالك',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              _buildRoomStats(isFull),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRoomStats(bool isFull) {
    final playersCount = room.players.length;
    final maxPlayers = room.maxPlayers;

    return Row(
      children: [
        Icon(
          Icons.people,
          size: 16,
          color: isFull ? Colors.grey : Colors.black54,
        ),
        const SizedBox(width: 4),
        Text(
          '$playersCount/$maxPlayers',
          style: TextStyle(
            color: isFull ? Colors.grey : Colors.black54,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 15),
        Icon(
          Icons.timer,
          size: 16,
          color: isFull ? Colors.grey : Colors.black54,
        ),
        const SizedBox(width: 4),
        Text(
          '${room.roundDuration ~/ 60}د',
          style: TextStyle(
            color: isFull ? Colors.grey : Colors.black54,
          ),
        ),
        const SizedBox(width: 15),
        Icon(
          Icons.repeat,
          size: 16,
          color: isFull ? Colors.grey : Colors.black54,
        ),
        const SizedBox(width: 4),
        Text(
          '${room.totalRounds} جولات',
          style: TextStyle(
            color: isFull ? Colors.grey : Colors.black54,
          ),
        ),
      ],
    );
  }

  Widget _buildProgressBar(double fillPercentage, bool isFull) {
    return Container(
      height: 8,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(4),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: fillPercentage,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isFull
                  ? [Colors.grey, Colors.grey.shade400]
                  : [const Color(0xFF667eea), const Color(0xFF764ba2)],
            ),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButtons(bool canJoin) {
    final playersCount = room.players.length;
    final maxPlayers = room.maxPlayers;
    final isFull = playersCount >= maxPlayers;

    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: canJoin ? onJoinRoom : null,
            icon: Icon(
              _getJoinButtonIcon(isFull, isMyRoom),
              size: 20,
            ),
            label: Text(
              _getJoinButtonText(isFull, isMyRoom),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: canJoin ? const Color(0xFF667eea) : Colors.grey,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        if (isMyRoom) ...[
          const SizedBox(width: 10),
          ElevatedButton.icon(
            onPressed: onDeleteRoom,
            icon: const Icon(Icons.delete, size: 20),
            label: const Text('حذف'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ],
      ],
    );
  }

  IconData _getJoinButtonIcon(bool isFull, bool isMyRoom) {
    if (isFull) return Icons.lock;
    if (isMyRoom) return Icons.star;
    if (currentUserStatus?.inRoom == true) return Icons.block;
    return Icons.login;
  }

  String _getJoinButtonText(bool isFull, bool isMyRoom) {
    if (isFull) return 'ممتلئة';
    if (isMyRoom) return 'غرفتك';
    if (currentUserStatus?.inRoom == true) return 'في غرفة أخرى';
    return 'انضمام';
  }
}