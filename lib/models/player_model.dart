import '../providers/game_provider.dart';

class Player {
  final String id;
  final String name;
  bool isConnected;
  bool isVoted;
  int votes;
  PlayerRole role;

  Player({
    required this.id,
    required this.name,
    this.isConnected = false,
    this.isVoted = false,
    this.votes = 0,
    this.role = PlayerRole.normal,
  });

  Player copyWith({
    String? id,
    String? name,
    bool? isConnected,
    bool? isVoted,
    int? votes,
    PlayerRole? role,
  }) {
    return Player(
      id: id ?? this.id,
      name: name ?? this.name,
      isConnected: isConnected ?? this.isConnected,
      isVoted: isVoted ?? this.isVoted,
      votes: votes ?? this.votes,
      role: role ?? this.role,
    );
  }
}
