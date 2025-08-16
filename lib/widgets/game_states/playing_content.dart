import 'package:flutter/material.dart';

import '../../../providers/game_provider.dart';

class PlayingContent extends StatelessWidget {
  final GameRoom room;
  final Player currentPlayer;
  final GameProvider gameProvider;
  final String playerId;
  final AnimationController cardController;
  final Function(List<Player>) onConnectToOtherPlayers;

  const PlayingContent({
    super.key,
    required this.room,
    required this.currentPlayer,
    required this.gameProvider,
    required this.playerId,
    required this.cardController,
    required this.onConnectToOtherPlayers,
  });

  @override
  Widget build(BuildContext context) {
    final word = gameProvider.currentWordForPlayer;

    // التحقق من الحاجة للاتصال بالآخرين مرة واحدة فقط
    if (room.players.length > 1) {
      Future.microtask(() => onConnectToOtherPlayers(room.players));
    }

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // عرض الكلمة
          _buildWordCard(word),
          const SizedBox(height: 30),
          // قائمة اللاعبين
          Expanded(child: _buildPlayersList()),
        ],
      ),
    );
  }

  Widget _buildWordCard(String? word) {
    return AnimatedBuilder(
      animation: cardController,
      builder: (context, child) {
        return Transform.scale(
          scale: 1.0 + (cardController.value * 0.1),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(30),
            decoration: BoxDecoration(
              color: currentPlayer.role == PlayerRole.spy
                  ? Colors.red.shade100
                  : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: currentPlayer.role == PlayerRole.spy
                    ? Colors.red
                    : Colors.green,
                width: 3,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              children: [
                Icon(
                  currentPlayer.role == PlayerRole.spy
                      ? Icons.visibility_off
                      : Icons.visibility,
                  size: 50,
                  color: currentPlayer.role == PlayerRole.spy
                      ? Colors.red
                      : Colors.green,
                ),
                const SizedBox(height: 20),
                Text(
                  word ?? '',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: currentPlayer.role == PlayerRole.spy
                        ? Colors.red
                        : Colors.green,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  currentPlayer.role == PlayerRole.spy
                      ? 'حاول اكتشاف الكلمة دون أن يكتشفوك!'
                      : 'تحدث عن الكلمة دون ذكرها مباشرة',
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.black54,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPlayersList() {
    return Container(
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
        children: [
          _buildPlayersListHeader(),
          Expanded(child: _buildPlayersListBody()),
        ],
      ),
    );
  }

  Widget _buildPlayersListHeader() {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: const BoxDecoration(
        color: Colors.green,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.people, color: Colors.white),
          const SizedBox(width: 10),
          const Text(
            'اللاعبون',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const Spacer(),
          Text(
            'الجولة ${room.currentRound}/${room.totalRounds}',
            style: const TextStyle(
              fontSize: 14,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayersListBody() {
    return ListView.builder(
      padding: const EdgeInsets.all(10),
      itemCount: room.players.length,
      itemBuilder: (context, index) {
        final player = room.players[index];
        final isCurrentPlayer = player.id == playerId;

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: isCurrentPlayer ? Colors.green.shade50 : Colors.white,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: isCurrentPlayer ? Colors.green : Colors.grey.shade300,
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: isCurrentPlayer ? Colors.green : Colors.grey,
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
                    Text(
                      isCurrentPlayer ? 'أنت' : 'لاعب',
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                player.isConnected ? Icons.mic : Icons.mic_off,
                color: player.isConnected ? Colors.green : Colors.red,
              ),
            ],
          ),
        );
      },
    );
  }
}