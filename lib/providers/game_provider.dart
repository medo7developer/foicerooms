import 'package:flutter/material.dart';

enum GameState { waiting, playing, voting, finished }
enum PlayerRole { normal, spy }

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
}

class GameRoom {
  final String id;
  final String name;
  final String creatorId;
  final int maxPlayers;
  final int totalRounds;
  final int roundDuration; // بالثواني
  List<Player> players;
  GameState state;
  int currentRound;
  String? currentWord;
  String? spyId;
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
    this.roundStartTime,
  });
}

class GameProvider extends ChangeNotifier {
  GameRoom? _currentRoom;
  Player? _currentPlayer;
  List<GameRoom> _availableRooms = [];

  // كلمات اللعبة
  final List<String> _gameWords = [
    'مدرسة', 'مستشفى', 'مطعم', 'مكتبة', 'حديقة',
    'بنك', 'صيدلية', 'سوق', 'سينما', 'متحف',
    'شاطئ', 'جبل', 'غابة', 'صحراء', 'نهر',
    'طائرة', 'سيارة', 'قطار', 'سفينة', 'دراجة',
    'طبيب', 'مدرس', 'مهندس', 'طباخ', 'فنان'
  ];

  GameRoom? get currentRoom => _currentRoom;
  Player? get currentPlayer => _currentPlayer;
  List<GameRoom> get availableRooms => _availableRooms;

  // إنشاء غرفة جديدة
  GameRoom createRoom({
    required String name,
    required String creatorId,
    required int maxPlayers,
    required int totalRounds,
    required int roundDuration,
  }) {
    final room = GameRoom(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      creatorId: creatorId,
      maxPlayers: maxPlayers,
      totalRounds: totalRounds,
      roundDuration: roundDuration,
    );

    _availableRooms.add(room);
    notifyListeners();
    return room;
  }

  // الانضمام لغرفة
  bool joinRoom(String roomId, String playerId, String playerName) {
    final room = _availableRooms.firstWhere((r) => r.id == roomId);

    if (room.players.length >= room.maxPlayers) {
      return false;
    }

    final player = Player(id: playerId, name: playerName);
    room.players = [...room.players, player];
    _currentRoom = room;
    _currentPlayer = player;

    // بدء اللعبة إذا اكتمل العدد
    if (room.players.length == room.maxPlayers) {
      startGame();
    }

    notifyListeners();
    return true;
  }

  // بدء اللعبة
  void startGame() {
    if (_currentRoom == null) return;

    _currentRoom!.state = GameState.playing;
    _currentRoom!.currentRound = 1;
    _startNewRound();
  }

  // بدء جولة جديدة
  void _startNewRound() {
    if (_currentRoom == null) return;

    // اختيار الجاسوس عشوائياً
    _currentRoom!.players.shuffle();
    final spyIndex = DateTime.now().millisecond % _currentRoom!.players.length;
    _currentRoom!.spyId = _currentRoom!.players[spyIndex].id;

    // تعيين الأدوار
    for (int i = 0; i < _currentRoom!.players.length; i++) {
      _currentRoom!.players[i].role = i == spyIndex ? PlayerRole.spy : PlayerRole.normal;
      _currentRoom!.players[i].votes = 0;
      _currentRoom!.players[i].isVoted = false;
    }

    // اختيار كلمة عشوائية
    _gameWords.shuffle();
    _currentRoom!.currentWord = _gameWords.first;
    _currentRoom!.roundStartTime = DateTime.now();

    notifyListeners();

    // انتهاء الجولة تلقائياً
    Future.delayed(Duration(seconds: _currentRoom!.roundDuration), () {
      if (_currentRoom?.state == GameState.playing) {
        startVoting();
      }
    });
  }

  // بدء التصويت
  void startVoting() {
    if (_currentRoom == null) return;

    _currentRoom!.state = GameState.voting;
    notifyListeners();
  }

  // التصويت على لاعب
  void votePlayer(String voterId, String targetId) {
    if (_currentRoom == null || _currentRoom!.state != GameState.voting) return;

    final voter = _currentRoom!.players.firstWhere((p) => p.id == voterId);
    if (voter.isVoted) return;

    voter.isVoted = true;
    final target = _currentRoom!.players.firstWhere((p) => p.id == targetId);
    target.votes++;

    // التحقق من انتهاء التصويت
    final totalVoted = _currentRoom!.players.where((p) => p.isVoted).length;
    if (totalVoted == _currentRoom!.players.length) {
      _endRound();
    }

    notifyListeners();
  }

  // انتهاء الجولة
  void _endRound() {
    if (_currentRoom == null) return;

    // العثور على اللاعب الأكثر تصويتاً
    final sortedPlayers = [..._currentRoom!.players]..sort((a, b) => b.votes.compareTo(a.votes));
    final mostVoted = sortedPlayers.first;

    // إزالة اللاعب الأكثر تصويتاً
    _currentRoom!.players.removeWhere((p) => p.id == mostVoted.id);

    // التحقق من نتيجة اللعبة
    final spy = _currentRoom!.players.where((p) => p.role == PlayerRole.spy).toList();

    if (spy.isEmpty) {
      // الجاسوس تم إقصاؤه - فوز اللاعبين العاديين
      _currentRoom!.state = GameState.finished;
    } else if (_currentRoom!.players.length <= 2) {
      // بقي الجاسوس للنهاية - فوز الجاسوس
      _currentRoom!.state = GameState.finished;
    } else if (_currentRoom!.currentRound >= _currentRoom!.totalRounds) {
      // انتهاء الجولات - فوز الجاسوس
      _currentRoom!.state = GameState.finished;
    } else {
      // جولة جديدة
      _currentRoom!.currentRound++;
      _startNewRound();
    }

    notifyListeners();
  }

  // مغادرة الغرفة
  void leaveRoom() {
    _currentRoom = null;
    _currentPlayer = null;
    notifyListeners();
  }

  // معلومات الوقت المتبقي
  Duration? get remainingTime {
    if (_currentRoom?.roundStartTime == null) return null;

    final elapsed = DateTime.now().difference(_currentRoom!.roundStartTime!);
    final total = Duration(seconds: _currentRoom!.roundDuration);
    final remaining = total - elapsed;

    return remaining.isNegative ? Duration.zero : remaining;
  }

  // الحصول على الكلمة للاعب الحالي
  String? get currentWordForPlayer {
    if (_currentRoom == null || _currentPlayer == null) return null;

    return _currentPlayer!.role == PlayerRole.spy
        ? '??? أنت الجاسوس'
        : _currentRoom!.currentWord;
  }
}