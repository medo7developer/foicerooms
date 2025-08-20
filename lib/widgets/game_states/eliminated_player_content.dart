// ملف جديد: lib/widgets/game_states/eliminated_player_content.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/game_provider.dart';

class EliminatedPlayerContent extends StatelessWidget {
  final GameRoom room;
  final Player currentPlayer;

  const EliminatedPlayerContent({
    super.key,
    required this.room,
    required this.currentPlayer,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          _buildEliminationHeader(),
          const SizedBox(height: 30),
          _buildGameStatus(),
          const SizedBox(height: 20),
          Expanded(child: _buildRemainingPlayers()),
          const SizedBox(height: 20),
          _buildActionButtons(context),
        ],
      ),
    );
  }

  Widget _buildEliminationHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.red.shade400, Colors.red.shade600],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.red.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          const Icon(
            Icons.person_off,
            size: 60,
            color: Colors.white,
          ),
          const SizedBox(height: 15),
          const Text(
            'تم إقصاؤك!',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            currentPlayer.role == PlayerRole.spy
                ? '🕵️ لقد تم اكتشاف أنك الجاسوس!'
                : '😔 لسوء الحظ، تم التصويت ضدك',
            style: const TextStyle(
              fontSize: 16,
              color: Colors.white70,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildGameStatus() {
    String statusText = '';
    IconData statusIcon = Icons.info;
    Color statusColor = Colors.blue;

    switch (room.state) {
      case GameState.voting:
        statusText = 'اللاعبون يصوتون الآن...';
        statusIcon = Icons.how_to_vote;
        statusColor = Colors.orange;
        break;
      case GameState.continueVoting:
        statusText = 'التصويت على إكمال الجولات';
        statusIcon = Icons.poll;
        statusColor = Colors.purple;
        break;
      case GameState.playing:
        statusText = 'الجولة ${room.currentRound} من ${room.totalRounds} جارية';
        statusIcon = Icons.play_circle;
        statusColor = Colors.green;
        break;
      case GameState.finished:
        statusText = 'انتهت اللعبة';
        statusIcon = Icons.flag;
        statusColor = Colors.grey;
        break;
      default:
        statusText = 'حالة غير معروفة';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: statusColor, width: 2),
      ),
      child: Row(
        children: [
          Icon(statusIcon, color: statusColor, size: 30),
          const SizedBox(width: 15),
          Expanded(
            child: Text(
              statusText,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: statusColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRemainingPlayers() {
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
            decoration: BoxDecoration(
              color: Colors.grey.shade700,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(15),
                topRight: Radius.circular(15),
              ),
            ),
            child: const Row(
              children: [
                Icon(Icons.people, color: Colors.white),
                SizedBox(width: 10),
                Text(
                  'اللاعبون المتبقون',
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
            child: room.players.isEmpty
                ? const Center(
              child: Text(
                'لا يوجد لاعبون متبقون',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            )
                : ListView.builder(
              padding: const EdgeInsets.all(10),
              itemCount: room.players.length,
              itemBuilder: (context, index) {
                final player = room.players[index];
                return _buildPlayerCard(player);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerCard(Player player) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: player.isConnected ? Colors.green : Colors.grey,
            child: Text(
              player.name[0].toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  player.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                Text(
                  player.isConnected ? 'متصل' : 'غير متصل',
                  style: TextStyle(
                    fontSize: 12,
                    color: player.isConnected ? Colors.green : Colors.grey,
                  ),
                ),
              ],
            ),
          ),
          if (room.state == GameState.voting && player.isVoted)
            const Icon(Icons.check_circle, color: Colors.green, size: 20),
          if (room.state == GameState.continueVoting && player.isVoted)
            Icon(
              player.votes == 1 ? Icons.play_arrow : Icons.stop,
              color: player.votes == 1 ? Colors.green : Colors.red,
              size: 20,
            ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: room.state == GameState.finished
                ? null
                : () => _showSpectatorDialog(context),
            icon: const Icon(Icons.visibility, color: Colors.white),
            label: const Text(
              'مشاهدة',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              disabledBackgroundColor: Colors.grey,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
        const SizedBox(width: 15),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => _leaveGame(context),
            icon: const Icon(Icons.exit_to_app, color: Colors.white),
            label: const Text(
              'مغادرة',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showSpectatorDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('وضع المشاهدة'),
        content: const Text('ستبقى في الغرفة لمشاهدة باقي اللعبة دون مشاركة'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // يمكن إضافة منطق إضافي هنا إذا لزم الأمر
            },
            child: const Text('موافق'),
          ),
        ],
      ),
    );
  }

  void _leaveGame(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('مغادرة اللعبة'),
        content: const Text('هل تريد مغادرة اللعبة نهائياً؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              // إزالة اللاعب من قاعدة البيانات وإنهاء الاتصال
              context.read<GameProvider>().leaveRoom();
              Navigator.popUntil(context, (route) => route.isFirst);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('مغادرة', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}