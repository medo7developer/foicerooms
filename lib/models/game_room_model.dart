// في كلاس GameRoom، أضف الحقل التالي:
import 'package:voice_rooms_app/models/player_model.dart';

import '../providers/game_provider.dart';
import '../providers/game_state.dart';

class GameRoom {
  final String id;
  final String name;
  final String creatorId;
  final int maxPlayers;
  final int totalRounds;
  final int roundDuration;
  List<Player> players;
  GameState state;
  int currentRound;
  String? currentWord;
  String? spyId;
  String? revealedSpyId;
  String? winner; // *** حقل جديد للفائز ***
  DateTime? roundStartTime;

  GameRoom({
    required this.id,
    required this.name,
    required this.creatorId,
    required this.maxPlayers,
    required this.totalRounds,
    required this.roundDuration,
    this.players = const [],
    this.state = GameState.waiting,
    this.currentRound = 0,
    this.currentWord,
    this.spyId,
    this.revealedSpyId,
    this.winner, // *** إضافة الحقل الجديد ***
    this.roundStartTime,
  });

  GameRoom copyWith({
    String? id,
    String? name,
    String? creatorId,
    int? maxPlayers,
    int? totalRounds,
    int? roundDuration,
    List<Player>? players,
    GameState? state,
    int? currentRound,
    String? currentWord,
    String? spyId,
    String? revealedSpyId,
    String? winner, // *** إضافة الحقل الجديد ***
    DateTime? roundStartTime,
  }) {
    return GameRoom(
      id: id ?? this.id,
      name: name ?? this.name,
      creatorId: creatorId ?? this.creatorId,
      maxPlayers: maxPlayers ?? this.maxPlayers,
      totalRounds: totalRounds ?? this.totalRounds,
      roundDuration: roundDuration ?? this.roundDuration,
      players: players ?? this.players,
      state: state ?? this.state,
      currentRound: currentRound ?? this.currentRound,
      currentWord: currentWord ?? this.currentWord,
      spyId: spyId ?? this.spyId,
      revealedSpyId: revealedSpyId ?? this.revealedSpyId,
      winner: winner ?? this.winner, // *** إضافة الحقل الجديد ***
      roundStartTime: roundStartTime ?? this.roundStartTime,
    );
  }
}
