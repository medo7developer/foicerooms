import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../providers/game_provider.dart';

class WaitingContent extends StatelessWidget {
  final GameRoom room;

  const WaitingContent({super.key, required this.room});

  @override
  Widget build(BuildContext context) {
    final gameProvider = context.watch<GameProvider>();
    final canStart = gameProvider.canStartGame();
    final isCreator = gameProvider.isCurrentPlayerCreator;
    final hasEnoughPlayers = gameProvider.hasEnoughPlayers;
    final connectedCount = gameProvider.connectedPlayersCount;

    return Center(
      child: Container(
        margin: const EdgeInsets.all(20),
        padding: const EdgeInsets.all(30),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.hourglass_empty,
              size: 60,
              color: Colors.blue,
            ),
            const SizedBox(height: 20),
            const Text(
              'في انتظار اللاعبين',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '$connectedCount/${room.maxPlayers} لاعبين',
              style: TextStyle(
                fontSize: 18,
                color: hasEnoughPlayers ? Colors.green : Colors.orange,
                fontWeight: FontWeight.bold,
              ),
            ),

            // مؤشر الحالة
            const SizedBox(height: 15),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: hasEnoughPlayers ? Colors.green.withOpacity(0.1) : Colors
                    .orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                hasEnoughPlayers
                    ? '✓ العدد كافي لبدء اللعبة'
                    : 'نحتاج ${gameProvider.minimumPlayersRequired -
                    connectedCount} لاعبين إضافيين على الأقل',
                style: TextStyle(
                  color: hasEnoughPlayers ? Colors.green : Colors.orange,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),

            const SizedBox(height: 20),

            // قائمة اللاعبين
            ...room.players.map((player) =>
                _buildPlayerCard(player, gameProvider.currentPlayer?.id ?? '')),

            // زر بدء اللعبة أو رسالة الانتظار
            if (isCreator)
              _buildStartGameButton(
                  context, gameProvider, canStart, connectedCount)
            else
              _buildWaitingMessage(hasEnoughPlayers),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerCard(Player player, String currentPlayerId) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: player.isConnected ? Colors.blue.shade50 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: player.isConnected ? Colors.blue : Colors.grey,
          width: player.id == currentPlayerId ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: player.isConnected ? Colors.blue : Colors.grey,
            child: Text(
              player.name[0].toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      player.name,
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: player.isConnected ? Colors.black87 : Colors
                            .grey,
                      ),
                    ),
                    if (player.id == currentPlayerId) ...[
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'أنت',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  player.isConnected ? 'متصل' : 'غير متصل',
                  style: TextStyle(
                    fontSize: 10,
                    color: player.isConnected ? Colors.green : Colors.red,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (player.id == room.creatorId) ...[
            const Icon(Icons.star, color: Colors.amber, size: 20),
          ],
          if (player.isConnected) ...[
            const SizedBox(width: 10),
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Colors.green,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStartGameButton(BuildContext context, GameProvider gameProvider,
      bool canStart, int connectedCount) {
    return Column(
      children: [
        const SizedBox(height: 25),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: canStart ? () =>
                _showStartGameConfirmation(
                    context, gameProvider, connectedCount) : null,
            icon: Icon(
              canStart ? Icons.play_arrow : Icons.lock,
              color: Colors.white,
            ),
            label: Text(
              canStart ? 'بدء اللعبة' : 'نحتاج المزيد من اللاعبين',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: canStart ? Colors.green : Colors.grey,
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

  Widget _buildWaitingMessage(bool hasEnoughPlayers) {
    return Column(
      children: [
        const SizedBox(height: 25),
        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blue.withOpacity(0.3)),
          ),
          child: Column(
            children: [
              const Row(
                children: [
                  Icon(Icons.info, color: Colors.blue),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'في انتظار مالك الغرفة لبدء اللعبة...',
                      style: TextStyle(
                        color: Colors.blue,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              if (hasEnoughPlayers) ...[
                const SizedBox(height: 5),
                Text(
                  'العدد كافي، يمكن البدء في أي وقت!',
                  style: TextStyle(
                    color: Colors.green.shade700,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showStartGameConfirmation(BuildContext context,
      GameProvider gameProvider, int connectedCount) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) =>
          AlertDialog(
            title: const Text('بدء اللعبة'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('هل تريد بدء اللعبة مع $connectedCount لاعبين؟'),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'سيتم اختيار جاسوس عشوائياً من بين اللاعبين',
                    style: TextStyle(fontSize: 12),
                    textAlign: TextAlign.center,
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
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                ),
                child: const Text(
                    'بدء اللعبة', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
    );

    if (confirmed == true) {
      _startGameWithLoadingDialog(context, gameProvider);
    }
  }

  Future<void> _startGameWithLoadingDialog(BuildContext context,
      GameProvider gameProvider) async {
    // إظهار مؤشر التحميل
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
      const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 15),
            Text('جاري بدء اللعبة...'),
          ],
        ),
      ),
    );

    // بدء اللعبة مع الخادم
    final success = await gameProvider.startGameWithServer();

    // إغلاق مؤشر التحميل
    Navigator.pop(context);

    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('فشل في بدء اللعبة، يرجى المحاولة مرة أخرى'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}