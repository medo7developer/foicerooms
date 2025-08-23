import 'package:flutter/material.dart';
import '../../models/player_model.dart';
import '../../providers/game_provider.dart';
import '../../providers/game_state.dart';
import '../game_stats/continue_voting_content.dart';
import '../game_stats/eliminated_player_content.dart';
import '../game_stats/waiting_content.dart';
import '../game_stats/playing_content.dart';
import '../game_stats/voting_content.dart';
import '../game_stats/finished_content.dart';
import '../../models/game_room_model.dart';

class GameContent extends StatelessWidget {
  final GameRoom room;
  final Player currentPlayer;
  final GameProvider gameProvider;
  final String playerId;
  final AnimationController cardController;
  final Function(List<Player>) onConnectToOtherPlayers;

  const GameContent({
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
    // تحقق من حالة اللاعب أولاً
    final isEliminated = gameProvider.isCurrentPlayerEliminated;
    if (isEliminated) {
      return EliminatedPlayerContent(
        room: room,
        currentPlayer: currentPlayer,
      );
    }

    // العرض العادي للاعبين المتبقين
    switch (room.state) {
      case GameState.waiting:
        return WaitingContent(room: room);
      case GameState.playing:
        return PlayingContent(
          room: room,
          currentPlayer: currentPlayer,
          gameProvider: gameProvider,
          playerId: playerId,
          cardController: cardController,
          onConnectToOtherPlayers: onConnectToOtherPlayers,
        );
      case GameState.voting:
        return VotingContent(room: room, currentPlayer: currentPlayer);
      case GameState.finished:
        return FinishedContent(room: room, currentPlayer: currentPlayer);
      case GameState.continueVoting:
        return ContinueVotingContent(room: room, currentPlayer: currentPlayer);
      default:
      // حالة افتراضية للتعامل مع أي حالة غير متوقعة
        return const Scaffold(
          body: Center(
            child: Text('حالة لعبة غير معروفة'),
          ),
        );
    }
  }
}