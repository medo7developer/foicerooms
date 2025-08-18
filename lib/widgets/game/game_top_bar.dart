import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/game_provider.dart';
import 'game_screen_mixin.dart';

class GameTopBar extends StatelessWidget with GameScreenMixin {
  final GameRoom room;
  final Player currentPlayer;
  final bool isRealtimeConnected;
  final VoidCallback onLeaveGame;

   GameTopBar({
    super.key,
    required this.room,
    required this.currentPlayer,
    required this.isRealtimeConnected,
    required this.onLeaveGame,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          IconButton(
            onPressed: onLeaveGame,
            icon: const Icon(Icons.exit_to_app, color: Colors.white),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  room.name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      getStatusText(room.state),
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: isRealtimeConnected ? Colors.green : Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          _buildTimerWidget(room),
        ],
      ),
    );
  }

  Widget _buildTimerWidget(GameRoom room) {
    return Consumer<GameProvider>(
      builder: (context, gameProvider, child) {
        final remainingTime = gameProvider.remainingTime;

        if (remainingTime == null || room.state != GameState.playing) {
          return const SizedBox();
        }

        final minutes = remainingTime.inMinutes;
        final seconds = remainingTime.inSeconds % 60;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        );
      },
    );
  }
  Color _getStatusColor(GameState state) {
    switch (state) {
      case GameState.waiting:
        return Colors.blue;
      case GameState.playing:
        return Colors.green;
      case GameState.voting:
        return Colors.orange;
      case GameState.continueVoting:
        return Colors.purple;
      case GameState.finished:
        return Colors.grey;
    }
  }

// وتحديث دالة _getStatusText:
  String _getStatusText(GameState state) {
    switch (state) {
      case GameState.waiting:
        return 'في انتظار اللاعبين';
      case GameState.playing:
        return 'اللعبة جارية';
      case GameState.voting:
        return 'وقت التصويت';
      case GameState.continueVoting:
        return 'التصويت على الإكمال';
      case GameState.finished:
        return 'انتهت اللعبة';
    }
  }
}