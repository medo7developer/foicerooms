import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../providers/game_provider.dart';
import '../../models/game_room_model.dart';
import '../../models/player_model.dart';
import '../../providers/game_state.dart';

class VotingContent extends StatelessWidget {
  final GameRoom room;
  final Player currentPlayer;

  const VotingContent({
    super.key,
    required this.room,
    required this.currentPlayer,
  });

  @override
  Widget build(BuildContext context) {
    final hasVoted = currentPlayer.isVoted;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          _buildVotingHeader(hasVoted),
          const SizedBox(height: 20),
          Expanded(child: _buildPlayersList(context, hasVoted)),
        ],
      ),
    );
  }

  Widget _buildVotingHeader(bool hasVoted) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.orange.shade100,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.orange, width: 2),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.how_to_vote,
            size: 40,
            color: Colors.orange,
          ),
          const SizedBox(height: 10),
          Text(
            hasVoted ? 'تم تسجيل صوتك!' : 'وقت التصويت',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.orange,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            hasVoted
                ? 'في انتظار باقي اللاعبين...'
                : 'صوت ضد اللاعب الذي تشك أنه الجاسوس',
            style: const TextStyle(
              fontSize: 14,
              color: Colors.black54,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildPlayersList(BuildContext context, bool hasVoted) {
    return ListView.builder(
      itemCount: room.players.length,
      itemBuilder: (context, index) {
        final player = room.players[index];
        final isCurrentPlayer = player.id == currentPlayer.id;

        if (isCurrentPlayer) return const SizedBox();

        return _buildPlayerVotingCard(context, player, hasVoted);
      },
    );
  }

  Widget _buildPlayerVotingCard(BuildContext context, Player player, bool hasVoted) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(15),
        leading: CircleAvatar(
          backgroundColor: Colors.orange,
          child: Text(
            player.name[0].toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          player.name,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        subtitle: Text('الأصوات: ${player.votes}'),
        trailing: hasVoted
            ? const Icon(Icons.check_circle, color: Colors.green)
            : ElevatedButton(
          onPressed: () => _votePlayer(context, player),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
          ),
          child: const Text('صوت'),
        ),
      ),
    );
  }

  Future<void> _votePlayer(BuildContext context, Player player) async {
    final gameProvider = context.read<GameProvider>();
    final currentRoom = gameProvider.currentRoom;

    if (currentRoom == null || currentRoom.state != GameState.voting) return;

    // تأكيد التصويت
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد التصويت'),
        content: Text('هل تريد التصويت ضد ${player.name}؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('تأكيد', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // استخدام التصويت مع المزامنة
      final success = await gameProvider.votePlayerWithServer(player.id);
      if (!success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('فشل في تسجيل الصوت'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}