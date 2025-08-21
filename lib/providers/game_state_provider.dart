import 'dart:developer';
import 'package:flutter/material.dart';
import '../models/game_room_model.dart';
import '../models/player_model.dart';
import '../services/supabase_service.dart';
import 'game_state.dart'; // استخدام الـ Enum من الملف المنفصل

class GameStateProvider extends ChangeNotifier {
  GameRoom? _currentRoom;
  Player? _currentPlayer;
  SupabaseService? _supabaseService;

  // متغيرات التتبع
  GameState? _lastKnownState; // استخدام الـ Enum من الملف المنفصل
  int _lastPlayersCount = 0;
  bool _isTransitioning = false;

  // Getters
  GameRoom? get currentRoom => _currentRoom;
  Player? get currentPlayer => _currentPlayer;

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

  String? get currentWordForPlayer {
    if (_currentRoom == null || _currentPlayer == null) return null;
    try {
      return _currentPlayer!.role == PlayerRole.spy // استخدام الـ Enum من الملف المنفصل
          ? '??? أنت الجاسوس'
          : _currentRoom!.currentWord;
    } catch (e) {
      debugPrint('خطأ في الحصول على الكلمة: $e');
      return null;
    }
  }

  bool get isInContinueVoting => _currentRoom?.state == GameState.continueVoting; // استخدام الـ Enum من الملف المنفصل

  Map<String, int> get continueVotingResults {
    if (_currentRoom == null ||
        _currentRoom!.state != GameState.continueVoting) { // استخدام الـ Enum من الملف المنفصل
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

  Map<String, dynamic> get gameStats => {
    'totalPlayers': _currentRoom?.players.length ?? 0,
    'currentRound': _currentRoom?.currentRound ?? 0,
    'totalRounds': _currentRoom?.totalRounds ?? 0,
    'gameState': _currentRoom?.state.toString() ?? 'unknown',
  };

  Map<String, dynamic> get enhancedGameStats => {
    'totalPlayers': _currentRoom?.players.length ?? 0,
    'currentRound': _currentRoom?.currentRound ?? 0,
    'totalRounds': _currentRoom?.totalRounds ?? 0,
    'gameState': _currentRoom?.state.toString() ?? 'unknown',
    'roomId': _currentRoom?.id,
    'playerId': _currentPlayer?.id,
    'lastUpdate': DateTime.now().millisecondsSinceEpoch,
    'stateChanged': hasStateChanged(),
  };

  Map<String, dynamic> get lastUpdateInfo => {
    'roomId': _currentRoom?.id,
    'state': _currentRoom?.state.toString(),
    'playersCount': _currentRoom?.players.length ?? 0,
    'lastStateChange': _lastKnownState.toString(),
    'timestamp': DateTime.now().toIso8601String(),
  };

  // Setters
  set currentRoom(GameRoom? room) {
    _currentRoom = room;
    notifyListeners();
  }

  set currentPlayer(Player? player) {
    _currentPlayer = player;
    notifyListeners();
  }

  // إعداد الخدمات
  void setSupabaseService(SupabaseService service) {
    _supabaseService = service;
  }

  // وظائف التحقق من التغييرات
  bool hasStateChanged() {
    return _lastKnownState != _currentRoom?.state;
  }

  // وظائف بدء اللعبة
  bool canStartGame(GameRoom? room, Player? player) {
    if (room == null || player == null) return false;
    // التحقق من أن اللاعب الحالي هو المنشئ
    if (room.creatorId != player.id) return false;
    // التحقق من حالة الغرفة
    if (room.state != GameState.waiting) return false; // استخدام الـ Enum من الملف المنفصل
    // التحقق من العدد الأدنى للاعبين
    final connectedPlayers = room.players.where((p) => p.isConnected).length;
    return connectedPlayers >= 3; // الحد الأدنى 3 لاعبين
  }

  void startGame(GameRoom? room, Player? player, List<String> gameWords) {
    if (room == null || room.players.isEmpty) {
      debugPrint('لا توجد غرفة أو لاعبين لبدء اللعبة');
      return;
    }

    _currentRoom = room;
    _currentPlayer = player;

    _startGame(gameWords);
  }

  bool startGameManually(GameRoom? room, Player? player) {
    if (!canStartGame(room, player)) {
      debugPrint('لا يمكن بدء اللعبة - شروط غير مكتملة');
      return false;
    }

    _currentRoom = room;
    _currentPlayer = player;

    _startGame([]);
    return true;
  }

  Future<bool> startGameWithServer(
      GameRoom? room,
      Player? player,
      SupabaseService? supabaseService,
      ) async {
    if (room == null || player == null) return false;
    try {
      final success = await supabaseService?.startGameByCreator(
          room.id,
          player.id
      ) ?? false;

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

  void _startGame(List<String> gameWords) {
    if (_currentRoom == null || _currentRoom!.players.isEmpty) {
      debugPrint('لا توجد غرفة أو لاعبين لبدء اللعبة');
      return;
    }

    _currentRoom!.state = GameState.playing; // استخدام الـ Enum من الملف المنفصل
    _currentRoom!.currentRound = 1;
    _startNewRound(gameWords);
  }

  void _startNewRound(List<String> gameWords) {
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
          role: isSpyPlayer ? PlayerRole.spy : PlayerRole.normal, // استخدام الـ Enum من الملف المنفصل
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
      final shuffledWords = gameWords.isNotEmpty ? List<String>.from(gameWords) : [
        'مدرسة', 'مستشفى', 'مطعم', 'مكتبة', 'حديقة',
        'بنك', 'صيدلية', 'سوق', 'سينما', 'متحف',
        'شاطئ', 'جبل', 'غابة', 'صحراء', 'نهر',
        'طائرة', 'سيارة', 'قطار', 'سفينة', 'دراجة',
        'طبيب', 'مدرس', 'مهندس', 'طباخ', 'فنان',
        'مطار', 'قطب', 'فندق', 'مخبز', 'ملعب',
        'جامعة', 'مصنع', 'محطة', 'حمام سباحة', 'مزرعة'
      ];
      shuffledWords.shuffle();
      _currentRoom!.currentWord = shuffledWords.first;
      _currentRoom!.roundStartTime = DateTime.now();

      debugPrint('بدأت جولة جديدة - الجاسوس: ${_currentRoom!.spyId}, الكلمة: ${_currentRoom!.currentWord}');
      notifyListeners();

      // انتهاء الجولة تلقائياً
      Future.delayed(Duration(seconds: _currentRoom!.roundDuration), () {
        if (_currentRoom?.state == GameState.playing && // استخدام الـ Enum من الملف المنفصل
            _currentRoom?.currentRound == _currentRoom?.currentRound) {
          startVoting();
        }
      });
    } catch (e) {
      debugPrint('خطأ في بدء الجولة الجديدة: $e');
    }
  }

  // وظائف التصويت
  void votePlayer(GameRoom? room, String voterId, String targetId) {
    if (room == null || room.state != GameState.voting) { // استخدام الـ Enum من الملف المنفصل
      debugPrint('لا يمكن التصويت في هذا الوقت');
      return;
    }

    _currentRoom = room;

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

  Future<bool> votePlayerWithServer(
      GameRoom? room,
      Player? player,
      String targetId,
      SupabaseService? supabaseService,
      ) async {
    if (room == null ||
        player == null ||
        room.state != GameState.voting || // استخدام الـ Enum من الملف المنفصل
        player.isVoted) {
      return false;
    }

    try {
      await supabaseService?.updateVote(player.id, targetId);
      debugPrint('تم تسجيل الصوت على الخادم');
      // التحديثات ستأتي من realtime
      return true;
    } catch (e) {
      debugPrint('خطأ في التصويت على الخادم: $e');
      return false;
    }
  }

  Future<bool> voteToContinueWithServer(
      GameRoom? room,
      Player? player,
      bool continuePlaying,
      SupabaseService? supabaseService,
      ) async {
    if (supabaseService == null || player == null) return false;

    try {
      await supabaseService.voteToContinue(player.id, continuePlaying);
      // تحديث حالة اللاعب محلياً
      if (room != null) {
        final playerIndex = room.players.indexWhere((p) => p.id == player.id);
        if (playerIndex != -1) {
          room.players[playerIndex].isVoted = true;
          room.players[playerIndex].votes = continuePlaying ? 1 : 0;
          notifyListeners();
        }
      }
      return true;
    } catch (e) {
      log('خطأ في التصويت على الإكمال: $e');
      return false;
    }
  }

  void startVoting() {
    if (_currentRoom == null || _isTransitioning) return;
    // هذه الدالة لن تستخدم مباشرة، سيتم استخدام الخادم
    debugPrint('تم استدعاء startVoting - يجب استخدام الخادم');
  }

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
      final remainingSpies = _currentRoom!.players.where((p) => p.role == PlayerRole.spy).toList(); // استخدام الـ Enum من الملف المنفصل
      final normalPlayers = _currentRoom!.players.where((p) => p.role == PlayerRole.normal).toList(); // استخدام الـ Enum من الملف المنفصل

      if (remainingSpies.isEmpty) {
        // الجاسوس تم إقصاؤه - فوز اللاعبين العاديين
        debugPrint('فوز اللاعبين العاديين - تم إقصاء الجاسوس');
        _currentRoom!.state = GameState.finished; // استخدام الـ Enum من الملف المنفصل
      } else if (normalPlayers.length <= 1) {
        // بقي الجاسوس مع لاعب واحد أو أقل - فوز الجاسوس
        debugPrint('فوز الجاسوس - بقي مع عدد قليل من اللاعبين');
        _currentRoom!.state = GameState.finished; // استخدام الـ Enum من الملف المنفصل
      } else if (_currentRoom!.currentRound >= _currentRoom!.totalRounds) {
        // انتهاء الجولات - فوز الجاسوس
        debugPrint('فوز الجاسوس - انتهاء الجولات');
        _currentRoom!.state = GameState.finished; // استخدام الـ Enum من الملف المنفصل
      } else {
        // جولة جديدة
        _currentRoom!.currentRound++;
        debugPrint('بدء جولة جديدة رقم ${_currentRoom!.currentRound}');
        _startNewRound([]);
      }

      notifyListeners();
    } catch (e) {
      debugPrint('خطأ في انتهاء الجولة: $e');
    }
  }

  // وظائف الوقت والجولات
  void checkRoundTimeout(GameRoom? room) {
    if (room == null ||
        room.state != GameState.playing || // استخدام الـ Enum من الملف المنفصل
        _isTransitioning) return;

    _currentRoom = room;

    final remainingTime = this.remainingTime;
    if (remainingTime != null && remainingTime.inSeconds <= 0) {
      _isTransitioning = true;
      debugPrint('انتهى وقت الجولة - بدء التصويت');
      // استخدام الخادم لإنهاء الجولة
      _endRoundOnServer();
    }
  }

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

  // وظائف التحديث من الخادم
  void updateStateFromServer(GameRoom serverRoom) {
    _currentRoom = serverRoom;
    _lastKnownState = serverRoom.state;
    notifyListeners();
  }

  void updateStateFromRealtime(GameRoom updatedRoom) {
    if (_currentRoom == null) return;

    final oldState = _currentRoom!.state;
    _currentRoom = updatedRoom;
    _lastKnownState = updatedRoom.state;

    // معالجة انتقالات الحالة
    _handleStateTransition(oldState, updatedRoom.state);

    notifyListeners();
  }

  void _handleStateTransition(GameState oldState, GameState newState) { // استخدام الـ Enum من الملف المنفصل
    switch (newState) {
      case GameState.voting: // استخدام الـ Enum من الملف المنفصل
        if (oldState == GameState.playing) { // استخدام الـ Enum من الملف المنفصل
          log('⏰ انتهت الجولة - بدء التصويت');
          _isTransitioning = false; // إعادة تعيين حالة التبديل
        }
        break;
      case GameState.continueVoting: // استخدام الـ Enum من الملف المنفصل
        if (oldState == GameState.voting) { // استخدام الـ Enum من الملف المنفصل
          log('🗳️ انتهى التصويت العادي - بدء تصويت الإكمال');
        }
        break;
      case GameState.playing: // استخدام الـ Enum من الملف المنفصل
        if (oldState == GameState.continueVoting || oldState == GameState.waiting) { // استخدام الـ Enum من الملف المنفصل
          log('▶️ بدء جولة جديدة');
        }
        break;
      case GameState.finished: // استخدام الـ Enum من الملف المنفصل
        log('🏁 انتهت اللعبة');
        break;
      default:
        break;
    }
  }

  // وظائف التحقق والتحقق من الصحة
  bool validateGameState(GameRoom? room, Player? player) {
    if (room == null) {
      debugPrint('خطأ: لا توجد غرفة حالية');
      return false;
    }
    if (player == null) {
      debugPrint('خطأ: لا يوجد لاعب حالي');
      return false;
    }
    if (!room.players.any((p) => p.id == player.id)) {
      debugPrint('خطأ: اللاعب الحالي غير موجود في قائمة اللاعبين');
      return false;
    }
    return true;
  }

  // إعادة تعيين الحالة
  void resetState() {
    _currentRoom = null;
    _currentPlayer = null;
    _lastKnownState = null;
    _lastPlayersCount = 0;
    _isTransitioning = false;
    notifyListeners();
  }

  // تنظيف الموارد
  @override
  void dispose() {
    _currentRoom = null;
    _currentPlayer = null;
    super.dispose();
  }
}