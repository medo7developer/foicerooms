import 'package:flutter/material.dart';

import '../../providers/game_provider.dart';
import '../game_states/continue_voting_content.dart';
import '../game_states/eliminated_player_content.dart';
import '../game_states/waiting_content.dart';
import '../game_states/playing_content.dart';
import '../game_states/voting_content.dart';
import '../game_states/finished_content.dart';

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
      // استيراد الملف الجديد في أعلى الملف:
      // import '../game_states/eliminated_player_content.dart';

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
    }
  }
}