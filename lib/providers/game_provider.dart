import 'dart:developer';

import 'package:flutter/material.dart';

import '../services/supabase_service.dart';

enum GameState { waiting, playing, voting, continueVoting, finished }
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

// تحديثات في ملف: lib/providers/game_provider.dart

// في كلاس GameRoom، أضف الحقل التالي:
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

class GameProvider extends ChangeNotifier {
  GameRoom? _currentRoom;
  Player? _currentPlayer;
  List<GameRoom> _availableRooms = [];
  SupabaseService? _supabaseService;
// إضافة متغير للتحكم في حالة التبديل:
  bool _isTransitioning = false;
  DateTime? _lastStateChange;

  // كلمات اللعبة
  final List<String> _gameWords = [
    'مدرسة', 'مستشفى', 'مطعم', 'مكتبة', 'حديقة',
    'بنك', 'صيدلية', 'سوق', 'سينما', 'متحف',
    'شاطئ', 'جبل', 'غابة', 'صحراء', 'نهر',
    'طائرة', 'سيارة', 'قطار', 'سفينة', 'دراجة',
    'طبيب', 'مدرس', 'مهندس', 'طباخ', 'فنان',
    'مطار', 'قطب', 'فندق', 'مخبز', 'ملعب',
    'جامعة', 'مصنع', 'محطة', 'حمام سباحة', 'مزرعة'
  ];

  GameRoom? get currentRoom => _currentRoom;
  Player? get currentPlayer => _currentPlayer;
  List<GameRoom> get availableRooms => _availableRooms;
  GameState? _lastKnownState;
  int _lastPlayersCount = 0;

  // إنشاء غرفة جديدة مع إضافة المنشئ
  GameRoom createRoom({
    required String name,
    required String creatorId,
    required String creatorName,
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

    // إضافة المنشئ كأول لاعب
    final creator = Player(
      id: creatorId,
      name: creatorName,
      isConnected: true,
    );
    room.players = [creator];

    _availableRooms.add(room);
    _currentRoom = room;
    _currentPlayer = creator;

    notifyListeners();
    return room;
  }

  void setSupabaseService(SupabaseService service) {
    _supabaseService = service;
  }

  // إضافة دالة للتحقق من التغييرات
  bool hasStateChanged() {
    return _lastKnownState != _currentRoom?.state;
  }

  bool hasPlayersCountChanged() {
    return _lastPlayersCount != (_currentRoom?.players.length ?? 0);
  }

  // تحسين دالة الانضمام للغرفة مع إشعار فوري
  bool joinRoom(String roomId, String playerId, String playerName) {
    try {
      // البحث عن الغرفة بأمان
      GameRoom? targetRoom;
      for (final room in _availableRooms) {
        if (room.id == roomId) {
          targetRoom = room;
          break;
        }
      }

      if (targetRoom == null) {
        debugPrint('الغرفة غير موجودة: $roomId');
        return false;
      }

      // التحقق من امتلاء الغرفة
      if (targetRoom.players.length >= targetRoom.maxPlayers) {
        debugPrint('الغرفة ممتلئة');
        return false;
      }

      // التحقق من وجود اللاعب مسبقاً
      final existingPlayerIndex = targetRoom.players.indexWhere((p) => p.id == playerId);
      if (existingPlayerIndex != -1) {
        // تحديث حالة الاتصال للاعب الموجود
        targetRoom.players[existingPlayerIndex] = targetRoom.players[existingPlayerIndex].copyWith(
          isConnected: true,
          name: playerName,
        );
      } else {
        // إضافة لاعب جديد
        final newPlayer = Player(
          id: playerId,
          name: playerName,
          isConnected: true,
        );
        targetRoom.players = [...targetRoom.players, newPlayer];
      }

      _currentRoom = targetRoom;
      _currentPlayer = targetRoom.players.firstWhere((p) => p.id == playerId);
      _lastPlayersCount = targetRoom.players.length;

      // إشعار فوري بالتحديث
      notifyListeners();

      // التحقق من إمكانية بدء اللعبة
      _checkAutoStart(targetRoom, playerId);

      debugPrint('تم الانضمام بنجاح - عدد اللاعبين الحالي: ${targetRoom.players.length}');
      return true;
    } catch (e) {
      debugPrint('خطأ في الانضمام للغرفة: $e');
      return false;
    }
  }

  // تحديث دالة checkRoundTimeout:
  void checkRoundTimeout() {
    if (_currentRoom == null ||
        _currentRoom!.state != GameState.playing ||
        _isTransitioning) return;

    final remainingTime = this.remainingTime;
    if (remainingTime != null && remainingTime.inSeconds <= 0) {
      _isTransitioning = true;
      debugPrint('انتهى وقت الجولة - بدء التصويت');

      // استخدام الخادم لإنهاء الجولة
      _endRoundOnServer();
    }
  }

// إضافة دالة لإنهاء الجولة عبر الخادم:
  Future<void> _endRoundOnServer() async {
    if (_currentRoom == null || _supabaseService == null) return;

    try {
      final success = await _supabaseService!.endRoundAndStartVoting(_currentRoom!.id);
      if (success) {
        debugPrint('تم إنهاء الجولة على الخادم');
      } else {
        debugPrint('فشل في إنهاء الجولة على الخادم');
        _isTransitioning = false; // إعادة تعيين في حالة الفشل
      }
    } catch (e) {
      debugPrint('خطأ في إنهاء الجولة على الخادم: $e');
      _isTransitioning = false;
    }
  }

// إزالة الدالة startVoting القديمة أو تحديثها:
  void startVoting() {
    if (_currentRoom == null || _isTransitioning) return;

    // هذه الدالة لن تستخدم مباشرة، سيتم استخدام الخادم
    debugPrint('تم استدعاء startVoting - يجب استخدام الخادم');
  }

  // تحسين دالة إعادة الانضمام
  void rejoinRoom(GameRoom room, String playerId) {
    try {
      _currentRoom = room;
      _lastKnownState = room.state;
      _lastPlayersCount = room.players.length;

      // البحث عن اللاعب الحالي بأمان
      Player? currentPlayer;
      for (final player in room.players) {
        if (player.id == playerId) {
          currentPlayer = player;
          break;
        }
      }

      _currentPlayer = currentPlayer;

      // إشعار فوري
      notifyListeners();

      debugPrint('تم إعادة الانضمام للغرفة: ${room.name} - الحالة: ${room.state}');
    } catch (e) {
      debugPrint('خطأ في إعادة الانضمام للغرفة: $e');
    }
  }

  // إضافة دالة للحصول على معلومات التحديث الأخير
  Map<String, dynamic> get lastUpdateInfo => {
    'roomId': _currentRoom?.id,
    'state': _currentRoom?.state.toString(),
    'playersCount': _currentRoom?.players.length ?? 0,
    'connectedCount': connectedPlayersCount,
    'lastStateChange': _lastKnownState.toString(),
    'timestamp': DateTime.now().toIso8601String(),
  };

  // إضافة دالة لفرض التحديث
  void forceUpdate() {
    debugPrint('فرض تحديث واجهة المستخدم');
    notifyListeners();
  }

  // تحسين دالة التحقق من إمكانية بدء اللعبة
  void _checkAutoStart(GameRoom room, String playerId) {
    final connectedPlayers = room.players.where((p) => p.isConnected).length;
    final canAutoStart = connectedPlayers >= room.maxPlayers &&
        room.state == GameState.waiting;

    if (canAutoStart) {
      debugPrint('اكتمل العدد المطلوب (${connectedPlayers}/${room.maxPlayers}) - يمكن بدء اللعبة');

      // إشعار بإمكانية البدء
      if (room.creatorId == playerId) {
        debugPrint('المنشئ متصل - يمكن بدء اللعبة');
      }

      // إشعار فوري بالتغيير
      notifyListeners();
    }
  }

  // دالة لمراقبة حالة الاتصال
  void updateConnectionStatus(String playerId, bool isConnected) {
    if (_currentRoom == null) return;

    try {
      final playerIndex = _currentRoom!.players.indexWhere((p) => p.id == playerId);
      if (playerIndex != -1) {
        _currentRoom!.players[playerIndex] = _currentRoom!.players[playerIndex].copyWith(
            isConnected: isConnected
        );

        if (_currentPlayer?.id == playerId) {
          _currentPlayer = _currentRoom!.players[playerIndex];
        }

        debugPrint('تحديث حالة الاتصال للاعب $playerId: $isConnected');
        notifyListeners();
      }
    } catch (e) {
      debugPrint('خطأ في تحديث حالة الاتصال: $e');
    }
  }

  // 2. إضافة دالة التصويت على الإكمال في كلاس GameProvider
  Future<bool> voteToContinueWithServer(bool continuePlaying) async {
    if (_supabaseService == null || _currentPlayer == null) return false;

    try {
      await _supabaseService!.voteToContinue(_currentPlayer!.id, continuePlaying);

      // تحديث حالة اللاعب محلياً
      final playerIndex = _currentRoom!.players.indexWhere((p) => p.id == _currentPlayer!.id);
      if (playerIndex != -1) {
        _currentRoom!.players[playerIndex].isVoted = true;
        _currentRoom!.players[playerIndex].votes = continuePlaying ? 1 : 0;
        notifyListeners();
      }

      return true;
    } catch (e) {
      log('خطأ في التصويت على الإكمال: $e');
      return false;
    }
  }

// تحسين دالة updateRoomFromRealtime
  void updateRoomFromRealtime(GameRoom updatedRoom, String playerId) {
    if (_currentRoom == null) return;

    // حفظ الحالة السابقة للمقارنة
    final oldState = _currentRoom!.state;
    final oldPlayersCount = _currentRoom!.players.length;
    final oldConnectedCount = connectedPlayersCount;

    // تحديث بيانات الغرفة
    _currentRoom = updatedRoom;

    // العثور على اللاعب الحالي في البيانات المحدثة
    Player? updatedPlayer;
    for (final player in updatedRoom.players) {
      if (player.id == playerId) {
        updatedPlayer = player;
        break;
      }
    }

    if (updatedPlayer == null) {
      log('⚠️ اللاعب $playerId تم إقصاؤه من الغرفة');
      _currentPlayer = Player(
        id: playerId,
        name: _currentPlayer?.name ?? 'لاعب محذوف',
        isConnected: false,
        isVoted: true,
        votes: 0,
        role: _currentPlayer?.role ?? PlayerRole.normal,
      );
    } else {
      _currentPlayer = updatedPlayer;
    }

    // تسجيل التغييرات المهمة
    final newConnectedCount = connectedPlayersCount;
    if (oldConnectedCount != newConnectedCount) {
      log('👥 تغير عدد اللاعبين المتصلين من $oldConnectedCount إلى $newConnectedCount');
    }

    if (oldState != updatedRoom.state) {
      log('🔄 تغيرت حالة الغرفة من $oldState إلى ${updatedRoom.state}');
      _handleStateTransition(oldState, updatedRoom.state);
    }

    // تحديث متغيرات التتبع
    _lastKnownState = updatedRoom.state;
    _lastPlayersCount = updatedRoom.players.length;

    // إشعارات متعددة للتأكد من التحديث
    notifyListeners();

    // إشعار إضافي بعد تأخير قصير
    Future.delayed(const Duration(milliseconds: 50), () {
      if (_currentRoom != null) {
        notifyListeners();
      }
    });

    // إشعار نهائي للتأكد
    Future.delayed(const Duration(milliseconds: 200), () {
      if (_currentRoom != null) {
        notifyListeners();
      }
    });
  }

// أضف هذه الدالة الجديدة لمعالجة انتقالات الحالة:
  void _handleStateTransition(GameState oldState, GameState newState) {
    switch (newState) {
      case GameState.voting:
        if (oldState == GameState.playing) {
          log('⏰ انتهت الجولة - بدء التصويت');
          _isTransitioning = false; // إعادة تعيين حالة التبديل
        }
        break;

      case GameState.continueVoting:
        if (oldState == GameState.voting) {
          log('🗳️ انتهى التصويت العادي - بدء تصويت الإكمال');
        }
        break;

      case GameState.playing:
        if (oldState == GameState.continueVoting || oldState == GameState.waiting) {
          log('▶️ بدء جولة جديدة');
        }
        break;

      case GameState.finished:
        log('🏁 انتهت اللعبة');
        break;

      default:
        break;
    }
  }

// أضف هذه الدالة للتحقق من حالة اللاعب:
  bool get isCurrentPlayerEliminated {
    if (_currentPlayer == null || _currentRoom == null) return false;

    // تحقق من وجود اللاعب في قائمة اللاعبين الحاليين
    return !_currentRoom!.players.any((p) => p.id == _currentPlayer!.id);
  }

// 4. دالة مساعدة للتحقق من حالة التصويت على الإكمال
  bool get isInContinueVoting => _currentRoom?.state == GameState.continueVoting;

// 5. دالة للحصول على عدد الأصوات في تصويت الإكمال
  Map<String, int> get continueVotingResults {
    if (_currentRoom == null ||
        _currentRoom!.state != GameState.continueVoting) {
      return {'continue': 0, 'end': 0, 'pending': 0};
    }

    int continueVotes = 0;
    int endVotes = 0;
    int pendingVotes = 0;

    for (final player in _currentRoom!.players) {
      if (player.isVoted) {
        if (player.votes == 1) {
          continueVotes++;
        } else {
          endVotes++;
        }
      } else {
        pendingVotes++;
      }
    }

    return {
      'continue': continueVotes,
      'end': endVotes,
      'pending': pendingVotes,
    };
  }

    // دالة للحصول على إحصائيات مفصلة
  @override
  Map<String, dynamic> get enhancedGameStats => {
    'totalPlayers': _currentRoom?.players.length ?? 0,
    'connectedPlayers': connectedPlayersCount,
    'disconnectedPlayers': (_currentRoom?.players.length ?? 0) - connectedPlayersCount,
    'currentRound': _currentRoom?.currentRound ?? 0,
    'totalRounds': _currentRoom?.totalRounds ?? 0,
    'gameState': _currentRoom?.state.toString() ?? 'unknown',
    'isPlayerSpy': isCurrentPlayerSpy,
    'isCreator': isCurrentPlayerCreator,
    'canStart': canStartGame(),
    'roomId': _currentRoom?.id,
    'playerId': _currentPlayer?.id,
    'lastUpdate': DateTime.now().millisecondsSinceEpoch,
    'stateChanged': hasStateChanged(),
    'playersChanged': hasPlayersCountChanged(),
  };

  // دالة جديدة للمنشئ لبدء اللعبة يدوياً
  bool canStartGame() {
    if (_currentRoom == null || _currentPlayer == null) return false;

    // التحقق من أن اللاعب الحالي هو المنشئ
    if (_currentRoom!.creatorId != _currentPlayer!.id) return false;

    // التحقق من حالة الغرفة
    if (_currentRoom!.state != GameState.waiting) return false;

    // التحقق من العدد الأدنى للاعبين
    final connectedPlayers = _currentRoom!.players.where((p) => p.isConnected).length;
    return connectedPlayers >= 3; // الحد الأدنى 3 لاعبين
  }

  // تحسين دالة بدء اللعبة
  bool startGameManually() {
    if (!canStartGame()) {
      debugPrint('لا يمكن بدء اللعبة - شروط غير مكتملة');
      return false;
    }

    _startGame();
    return true;
  }

  // إضافة getter لمعرفة ما إذا كان اللاعب الحالي هو المنشئ
  bool get isCurrentPlayerCreator {
    return _currentRoom?.creatorId == _currentPlayer?.id;
  }

  // إضافة getter لعدد اللاعبين المتصلين
  int get connectedPlayersCount {
    return _currentRoom?.players.where((p) => p.isConnected).length ?? 0;
  }

  // إضافة getter للحد الأدنى المطلوب
  int get minimumPlayersRequired => 3;

  // إضافة getter لمعرفة ما إذا كان العدد كافياً
  bool get hasEnoughPlayers {
    return connectedPlayersCount >= minimumPlayersRequired;
  }

  // بدء اللعبة مع التحقق من الأمان
  void startGame() {
    _startGame();
  }

  // بدء اللعبة (دالة داخلية)
  void _startGame() {
    if (_currentRoom == null || _currentRoom!.players.isEmpty) {
      debugPrint('لا توجد غرفة أو لاعبين لبدء اللعبة');
      return;
    }

    _currentRoom!.state = GameState.playing;
    _currentRoom!.currentRound = 1;
    _startNewRound();
  }

  // بدء جولة جديدة مع تحسينات
  void _startNewRound() {
    if (_currentRoom == null || _currentRoom!.players.isEmpty) return;

    try {
      // إنشاء نسخة من قائمة اللاعبين للخلط
      final playersToShuffle = List<Player>.from(_currentRoom!.players);
      playersToShuffle.shuffle();

      // اختيار الجاسوس عشوائياً
      final spyIndex = DateTime.now().millisecond % playersToShuffle.length;
      _currentRoom!.spyId = playersToShuffle[spyIndex].id;

      // تعيين الأدوار وإعادة تعيين الإحصائيات
      for (int i = 0; i < _currentRoom!.players.length; i++) {
        final playerId = _currentRoom!.players[i].id;
        final isSpyPlayer = playerId == _currentRoom!.spyId;

        _currentRoom!.players[i] = _currentRoom!.players[i].copyWith(
          role: isSpyPlayer ? PlayerRole.spy : PlayerRole.normal,
          votes: 0,
          isVoted: false,
        );
      }

      // تحديث دور اللاعب الحالي
      if (_currentPlayer != null) {
        final currentPlayerIndex = _currentRoom!.players.indexWhere((p) => p.id == _currentPlayer!.id);
        if (currentPlayerIndex != -1) {
          _currentPlayer = _currentRoom!.players[currentPlayerIndex];
        }
      }

      // اختيار كلمة عشوائية
      final shuffledWords = List<String>.from(_gameWords);
      shuffledWords.shuffle();
      _currentRoom!.currentWord = shuffledWords.first;
      _currentRoom!.roundStartTime = DateTime.now();

      debugPrint('بدأت جولة جديدة - الجاسوس: ${_currentRoom!.spyId}, الكلمة: ${_currentRoom!.currentWord}');

      notifyListeners();

      // انتهاء الجولة تلقائياً
      Future.delayed(Duration(seconds: _currentRoom!.roundDuration), () {
        if (_currentRoom?.state == GameState.playing &&
            _currentRoom?.currentRound == _currentRoom?.currentRound) {
          startVoting();
        }
      });
    } catch (e) {
      debugPrint('خطأ في بدء الجولة الجديدة: $e');
    }
  }

  // التصويت على لاعب مع التحقق الآمن
  void votePlayer(String voterId, String targetId) {
    if (_currentRoom == null || _currentRoom!.state != GameState.voting) {
      debugPrint('لا يمكن التصويت في هذا الوقت');
      return;
    }

    try {
      // العثور على اللاعب المصوت بأمان
      int voterIndex = -1;
      for (int i = 0; i < _currentRoom!.players.length; i++) {
        if (_currentRoom!.players[i].id == voterId) {
          voterIndex = i;
          break;
        }
      }

      if (voterIndex == -1) {
        debugPrint('اللاعب المصوت غير موجود: $voterId');
        return;
      }

      if (_currentRoom!.players[voterIndex].isVoted) {
        debugPrint('اللاعب صوت مسبقاً');
        return;
      }

      // العثور على الهدف بأمان
      int targetIndex = -1;
      for (int i = 0; i < _currentRoom!.players.length; i++) {
        if (_currentRoom!.players[i].id == targetId) {
          targetIndex = i;
          break;
        }
      }

      if (targetIndex == -1) {
        debugPrint('اللاعب المستهدف غير موجود: $targetId');
        return;
      }

      // تسجيل التصويت
      _currentRoom!.players[voterIndex] = _currentRoom!.players[voterIndex].copyWith(isVoted: true);
      _currentRoom!.players[targetIndex] = _currentRoom!.players[targetIndex].copyWith(
          votes: _currentRoom!.players[targetIndex].votes + 1
      );

      // التحقق من انتهاء التصويت
      final totalVoted = _currentRoom!.players.where((p) => p.isVoted).length;
      if (totalVoted >= _currentRoom!.players.length) {
        _endRound();
      }

      notifyListeners();
      debugPrint('تم تسجيل صوت من $voterId لـ $targetId');
    } catch (e) {
      debugPrint('خطأ في التصويت: $e');
    }
  }

  // انتهاء الجولة مع تحسينات
  void _endRound() {
    if (_currentRoom == null) return;

    try {
      // العثور على اللاعب الأكثر تصويتاً
      if (_currentRoom!.players.isEmpty) return;

      final sortedPlayers = List<Player>.from(_currentRoom!.players);
      sortedPlayers.sort((a, b) => b.votes.compareTo(a.votes));
      final mostVoted = sortedPlayers.first;

      debugPrint('اللاعب الأكثر تصويتاً: ${mostVoted.name} (${mostVoted.votes} أصوات)');

      // إزالة اللاعب الأكثر تصويتاً
      _currentRoom!.players.removeWhere((p) => p.id == mostVoted.id);

      // إذا كان اللاعب المحذوف هو اللاعب الحالي
      if (_currentPlayer?.id == mostVoted.id) {
        _currentPlayer = null;
      }

      // التحقق من نتيجة اللعبة
      final remainingSpies = _currentRoom!.players.where((p) => p.role == PlayerRole.spy).toList();
      final normalPlayers = _currentRoom!.players.where((p) => p.role == PlayerRole.normal).toList();

      if (remainingSpies.isEmpty) {
        // الجاسوس تم إقصاؤه - فوز اللاعبين العاديين
        debugPrint('فوز اللاعبين العاديين - تم إقصاء الجاسوس');
        _currentRoom!.state = GameState.finished;
      } else if (normalPlayers.length <= 1) {
        // بقي الجاسوس مع لاعب واحد أو أقل - فوز الجاسوس
        debugPrint('فوز الجاسوس - بقي مع عدد قليل من اللاعبين');
        _currentRoom!.state = GameState.finished;
      } else if (_currentRoom!.currentRound >= _currentRoom!.totalRounds) {
        // انتهاء الجولات - فوز الجاسوس
        debugPrint('فوز الجاسوس - انتهاء الجولات');
        _currentRoom!.state = GameState.finished;
      } else {
        // جولة جديدة
        _currentRoom!.currentRound++;
        debugPrint('بدء جولة جديدة رقم ${_currentRoom!.currentRound}');
        _startNewRound();
      }

      notifyListeners();
    } catch (e) {
      debugPrint('خطأ في انتهاء الجولة: $e');
    }
  }

  // تحديث قائمة الغرف المتاحة
  void updateAvailableRooms(List<GameRoom> rooms) {
    _availableRooms = rooms;
    notifyListeners();
  }

  // مغادرة الغرفة مع تنظيف آمن
  void leaveRoom() {
    try {
      if (_currentRoom != null && _currentPlayer != null) {
        // إزالة اللاعب من قائمة اللاعبين
        _currentRoom!.players.removeWhere((p) => p.id == _currentPlayer!.id);

        // إذا كان مالك الغرفة، إزالة الغرفة من القائمة
        if (_currentRoom!.creatorId == _currentPlayer!.id) {
          _availableRooms.removeWhere((room) => room.id == _currentRoom!.id);
        }
      }

      _currentRoom = null;
      _currentPlayer = null;
      notifyListeners();
      debugPrint('تم مغادرة الغرفة');
    } catch (e) {
      debugPrint('خطأ في مغادرة الغرفة: $e');
    }
  }

  // معلومات الوقت المتبقي
  Duration? get remainingTime {
    if (_currentRoom?.roundStartTime == null) return null;

    try {
      final elapsed = DateTime.now().difference(_currentRoom!.roundStartTime!);
      final total = Duration(seconds: _currentRoom!.roundDuration);
      final remaining = total - elapsed;

      return remaining.isNegative ? Duration.zero : remaining;
    } catch (e) {
      debugPrint('خطأ في حساب الوقت المتبقي: $e');
      return null;
    }
  }

  // الحصول على الكلمة للاعب الحالي
  String? get currentWordForPlayer {
    if (_currentRoom == null || _currentPlayer == null) return null;

    try {
      return _currentPlayer!.role == PlayerRole.spy
          ? '??? أنت الجاسوس'
          : _currentRoom!.currentWord;
    } catch (e) {
      debugPrint('خطأ في الحصول على الكلمة: $e');
      return null;
    }
  }

  // التحقق من حالة اللعبة
  bool get isGameActive => _currentRoom != null && _currentPlayer != null;

  // التحقق من كون اللاعب جاسوساً
  bool get isCurrentPlayerSpy => _currentPlayer?.role == PlayerRole.spy;

  // الحصول على معلومات إحصائية
  Map<String, dynamic> get gameStats => {
    'totalPlayers': _currentRoom?.players.length ?? 0,
    'connectedPlayers': connectedPlayersCount,
    'currentRound': _currentRoom?.currentRound ?? 0,
    'totalRounds': _currentRoom?.totalRounds ?? 0,
    'gameState': _currentRoom?.state.toString() ?? 'unknown',
    'isPlayerSpy': isCurrentPlayerSpy,
  };

  // دالة لبدء اللعبة مع المزامنة مع الخادم
  Future<bool> startGameWithServer() async {
    if (_currentRoom == null || _currentPlayer == null) return false;

    try {
      final supabaseService = SupabaseService(); // يجب حقنه بدلاً من إنشاء instance جديد
      final success = await supabaseService.startGameByCreator(
          _currentRoom!.id,
          _currentPlayer!.id
      );

      if (success) {
        debugPrint('تم بدء اللعبة على الخادم');
        // التحديثات ستأتي من realtime
        return true;
      } else {
        debugPrint('فشل في بدء اللعبة على الخادم');
        return false;
      }
    } catch (e) {
      debugPrint('خطأ في بدء اللعبة على الخادم: $e');
      return false;
    }
  }

  // دالة لمزامنة التصويت مع الخادم
  Future<bool> votePlayerWithServer(String targetId) async {
    if (_currentRoom == null ||
        _currentPlayer == null ||
        _currentRoom!.state != GameState.voting ||
        _currentPlayer!.isVoted) {
      return false;
    }

    try {
      final supabaseService = SupabaseService(); // يجب حقنه
      await supabaseService.updateVote(_currentPlayer!.id, targetId);

      debugPrint('تم تسجيل الصوت على الخادم');
      // التحديثات ستأتي من realtime
      return true;
    } catch (e) {
      debugPrint('خطأ في التصويت على الخادم: $e');
      return false;
    }
  }

  // دالة للتحقق من حالة الاتصال بالخادم
  bool get isConnectedToServer => _currentRoom != null && _currentPlayer != null;

  // دالة لإعادة تعيين كل شيء (للاستخدام عند الأخطاء)
  void resetAll() {
    _currentRoom = null;
    _currentPlayer = null;
    _availableRooms.clear();
    notifyListeners();
    debugPrint('تم إعادة تعيين جميع بيانات اللعبة');
  }

  // دالة للتحقق من صحة البيانات
  bool validateGameState() {
    if (_currentRoom == null) {
      debugPrint('خطأ: لا توجد غرفة حالية');
      return false;
    }

    if (_currentPlayer == null) {
      debugPrint('خطأ: لا يوجد لاعب حالي');
      return false;
    }

    if (!_currentRoom!.players.any((p) => p.id == _currentPlayer!.id)) {
      debugPrint('خطأ: اللاعب الحالي غير موجود في قائمة اللاعبين');
      return false;
    }

    return true;
  }

  // إضافة هذه الدالة في GameProvider
  void updatePlayerConnectionStatus(String playerId, bool isConnected) {
    if (_currentRoom == null) return;

    bool updated = false;
    for (int i = 0; i < _currentRoom!.players.length; i++) {
      if (_currentRoom!.players[i].id == playerId) {
        _currentRoom!.players[i] = _currentRoom!.players[i].copyWith(
            isConnected: isConnected
        );
        updated = true;
        break;
      }
    }

    if (updated) {
      // تحديث اللاعب الحالي إذا كان هو المتأثر
      if (_currentPlayer?.id == playerId) {
        _currentPlayer = _currentRoom!.players.firstWhere(
                (p) => p.id == playerId,
            orElse: () => _currentPlayer!
        );
      }

      debugPrint('تم تحديث حالة الاتصال للاعب $playerId: $isConnected');
      notifyListeners();

      // إشعار إضافي للتأكد من التحديث
      Future.delayed(const Duration(milliseconds: 100), () {
        notifyListeners();
      });
    }
  }

  // إضافة دالة جديدة للتحديث المباشر:
  void notifyRoomUpdate() {
    notifyListeners();
    debugPrint('تم إشعار المستمعين بتحديث الغرفة');
  }

  // تنظيف الموارد
  @override
  void dispose() {
    _currentRoom = null;
    _currentPlayer = null;
    _availableRooms.clear();
    super.dispose();
  }
}