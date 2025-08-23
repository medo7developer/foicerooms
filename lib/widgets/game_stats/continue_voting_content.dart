// ملف: lib/widgets/game_stats/continue_voting_content.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/game_provider.dart';
import '../../models/game_room_model.dart';
import '../../models/player_model.dart';

class ContinueVotingContent extends StatelessWidget {
  final GameRoom room;
  final Player currentPlayer;

  const ContinueVotingContent({
    super.key,
    required this.room,
    required this.currentPlayer,
  });

// تحديثات في ملف: lib/widgets/game_stats/continue_voting_content.dart

  @override
  Widget build(BuildContext context) {
    // *** فحص عدد اللاعبين المتبقين ***
    final connectedPlayers = room.players.where((p) => p.isConnected).length;

    // إذا كان عدد اللاعبين أقل من 3، لا نعرض واجهة التصويت
    if (connectedPlayers < 3) {
      return _buildInsufficientPlayersMessage(context);
    }

    final hasVoted = currentPlayer.isVoted;
    final playerChoice = hasVoted ? (currentPlayer.votes == 1 ? 'إكمال' : 'إنهاء') : null;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          _buildVotingHeader(hasVoted, playerChoice),
          const SizedBox(height: 30),
          if (!hasVoted) _buildVotingButtons(context),
          const SizedBox(height: 30),
          Expanded(child: _buildPlayersVotingStatus()),
        ],
      ),
    );
  }

// *** دالة جديدة لعرض رسالة عدم كفاية اللاعبين ***
  Widget _buildInsufficientPlayersMessage(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(20),
        padding: const EdgeInsets.all(30),
        decoration: BoxDecoration(
          color: Colors.orange.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.orange, width: 2),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.groups_2_outlined,
              size: 60,
              color: Colors.orange,
            ),
            const SizedBox(height: 20),
            const Text(
              'عدد اللاعبين غير كافٍ',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.orange,
              ),
            ),
            const SizedBox(height: 15),
            Text(
              'عدد اللاعبين المتبقين (${room.players.where((p) => p.isConnected).length}) أقل من الحد الأدنى المطلوب (3)\nسيتم إنهاء اللعبة تلقائياً...',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 20),
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVotingHeader(bool hasVoted, String? playerChoice) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.purple.shade100,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.purple, width: 2),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.how_to_vote,
            size: 40,
            color: Colors.purple,
          ),
          const SizedBox(height: 10),
          Text(
            hasVoted ? 'تم تسجيل صوتك!' : 'هل تريد إكمال الجولات؟',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.purple,
            ),
          ),
          const SizedBox(height: 5),
          if (hasVoted) ...[
            Text(
              'صوتك: $playerChoice',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.purple,
              ),
            ),
            const SizedBox(height: 5),
            const Text(
              'في انتظار باقي اللاعبين...',
              style: TextStyle(
                fontSize: 14,
                color: Colors.black54,
              ),
            ),
          ] else ...[
            const Text(
              'اختر ما إذا كنت تريد إكمال الجولات أم إنهاء اللعبة',
              style: TextStyle(
                fontSize: 14,
                color: Colors.black54,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVotingButtons(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => _voteToContinue(context, true),
            icon: const Icon(Icons.play_arrow, color: Colors.white),
            label: const Text(
              'إكمال الجولات',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(width: 15),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => _voteToContinue(context, false),
            icon: const Icon(Icons.stop, color: Colors.white),
            label: const Text(
              'إنهاء اللعبة',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPlayersVotingStatus() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(15),
            decoration: const BoxDecoration(
              color: Colors.purple,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(15),
                topRight: Radius.circular(15),
              ),
            ),
            child: const Row(
              children: [
                Icon(Icons.people, color: Colors.white),
                SizedBox(width: 10),
                Text(
                  'حالة التصويت',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(10),
              itemCount: room.players.length,
              itemBuilder: (context, index) {
                final player = room.players[index];
                return _buildPlayerVotingCard(player);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerVotingCard(Player player) {
    String statusText = 'لم يصوت بعد';
    Color statusColor = Colors.grey;
    IconData statusIcon = Icons.hourglass_empty;

    if (player.isVoted) {
      if (player.votes == 1) {
        statusText = 'إكمال الجولات';
        statusColor = Colors.green;
        statusIcon = Icons.play_arrow;
      } else {
        statusText = 'إنهاء اللعبة';
        statusColor = Colors.red;
        statusIcon = Icons.stop;
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: player.id == currentPlayer.id ? Colors.purple.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: player.id == currentPlayer.id ? Colors.purple : Colors.grey.shade300,
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: player.id == currentPlayer.id ? Colors.purple : Colors.grey,
            child: Text(
              player.name[0].toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  player.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Row(
                  children: [
                    Icon(statusIcon, size: 16, color: statusColor),
                    const SizedBox(width: 5),
                    Text(
                      statusText,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _voteToContinue(BuildContext context, bool continuePlaying) async {
    // تأكيد الاختيار
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الاختيار'),
        content: Text(
            continuePlaying
                ? 'هل تريد إكمال الجولات المتبقية؟'
                : 'هل تريد إنهاء اللعبة الآن؟'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: continuePlaying ? Colors.green : Colors.red,
            ),
            child: Text(
              'تأكيد',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final gameProvider = context.read<GameProvider>();
      final success = await gameProvider.voteToContinueWithServer(continuePlaying);

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