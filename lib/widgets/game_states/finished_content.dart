import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../providers/game_provider.dart';

class FinishedContent extends StatelessWidget {
  final GameRoom room;
  final Player currentPlayer;

  const FinishedContent({
    super.key,
    required this.room,
    required this.currentPlayer,
  });

  @override
  Widget build(BuildContext context) {
    final wasPlayerSpy = currentPlayer.role == PlayerRole.spy;
    final spyWon = room.players.any((p) => p.role == PlayerRole.spy);
    final playerWon = wasPlayerSpy ? spyWon : !spyWon;

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
            _buildResultIcon(playerWon),
            const SizedBox(height: 20),
            _buildResultTitle(playerWon),
            const SizedBox(height: 10),
            _buildResultDescription(wasPlayerSpy, spyWon),
            const SizedBox(height: 30),
            _buildBackToHomeButton(context),
          ],
        ),
      ),
    );
  }

  Widget _buildResultIcon(bool playerWon) {
    return Icon(
      playerWon ? Icons.emoji_events : Icons.sentiment_dissatisfied,
      size: 80,
      color: playerWon ? Colors.amber : Colors.grey,
    );
  }

  Widget _buildResultTitle(bool playerWon) {
    return Text(
      playerWon ? '🎉 فزت!' : '😔 خسرت',
      style: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.bold,
        color: playerWon ? Colors.amber : Colors.grey,
      ),
    );
  }

  Widget _buildResultDescription(bool wasPlayerSpy, bool spyWon) {
    String description;

    if (wasPlayerSpy) {
      description = spyWon ? 'نجحت في خداع الآخرين!' : 'تم اكتشافك!';
    } else {
      description = spyWon
          ? 'لم تتمكنوا من اكتشاف الجاسوس'
          : 'نجحتم في اكتشاف الجاسوس!';
    }

    return Text(
      description,
      style: const TextStyle(
        fontSize: 16,
        color: Colors.black54,
      ),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildBackToHomeButton(BuildContext context) {
    return ElevatedButton(
      onPressed: () {
        context.read<GameProvider>().leaveRoom();
        Navigator.popUntil(context, (route) => route.isFirst);
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.purple,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(
          horizontal: 30,
          vertical: 15,
        ),
      ),
      child: const Text('العودة للرئيسية'),
    );
  }
}