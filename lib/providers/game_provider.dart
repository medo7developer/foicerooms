import 'dart:developer';
import 'package:flutter/material.dart';
import '../models/experience_models.dart';
import '../models/game_room_model.dart';
import '../models/player_model.dart';
import '../services/experience_service.dart';
import '../services/supabase_service.dart';
import 'game_state_provider.dart';
import 'game_room_provider.dart';
import 'game_player_provider.dart';
import 'game_sound_provider.dart';
import 'game_rewards_provider.dart';

class GameProvider extends ChangeNotifier {
  // مزودي الخدمة
  final GameStateProvider _gameStateProvider = GameStateProvider();
  final GameRoomProvider _gameRoomProvider = GameRoomProvider();
  final GamePlayerProvider _gamePlayerProvider = GamePlayerProvider();
  final GameSoundProvider _gameSoundProvider = GameSoundProvider();
  final GameRewardsProvider _gameRewardsProvider = GameRewardsProvider();

  // الخدمات الخارجية
  SupabaseService? _supabaseService;
  ExperienceService? _experienceService;

  // Getters للوصول إلى المزودين
  GameStateProvider get gameState => _gameStateProvider;
  GameRoomProvider get gameRoom => _gameRoomProvider;
  GamePlayerProvider get gamePlayer => _gamePlayerProvider;
  GameSoundProvider get gameSound => _gameSoundProvider;
  GameRewardsProvider get gameRewards => _gameRewardsProvider;

  // Getters للخدمات
  SupabaseService? get supabaseService => _supabaseService;
  ExperienceService? get experienceService => _experienceService;

  // Getters للوصول المباشر للبيانات
  GameRoom? get currentRoom => _gameRoomProvider.currentRoom;
  Player? get currentPlayer => _gamePlayerProvider.currentPlayer;
  List<GameRoom> get availableRooms => _gameRoomProvider.availableRooms;
  PlayerStats? get currentPlayerStats => _gameRewardsProvider.currentPlayerStats;
  List<GameReward>? get lastGameRewards => _gameRewardsProvider.lastGameRewards;
  Duration? get remainingTime => _gameStateProvider.remainingTime;
  String? get currentWordForPlayer => _gameStateProvider.currentWordForPlayer;
  bool get isCurrentPlayerSpy => _gamePlayerProvider.isCurrentPlayerSpy;
  bool get isCurrentPlayerCreator => _gamePlayerProvider.isCurrentPlayerCreator;
  bool get isCurrentPlayerEliminated => _gamePlayerProvider.isCurrentPlayerEliminated;
  int get connectedPlayersCount => _gameRoomProvider.connectedPlayersCount;
  bool get hasEnoughPlayers => _gameRoomProvider.hasEnoughPlayers;
  bool get isInContinueVoting => _gameStateProvider.isInContinueVoting;
  Map<String, int> get continueVotingResults => _gameStateProvider.continueVotingResults;
  Map<String, dynamic> get gameStats => _gameStateProvider.gameStats;
  Map<String, dynamic> get enhancedGameStats => _gameStateProvider.enhancedGameStats;
  Map<String, dynamic> get lastUpdateInfo => _gameStateProvider.lastUpdateInfo;

  // إضافة getter المطلوب
  int get minimumPlayersRequired => 3; // الحد الأدنى لعدد اللاعبين المطلوبين لبدء اللعبة

  // Setters
  set currentRoom(GameRoom? room) {
    _gameRoomProvider.currentRoom = room;
    notifyListeners();
  }

  set currentPlayer(Player? player) {
    _gamePlayerProvider.currentPlayer = player;
    notifyListeners();
  }

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

  List<String> get gameWords => _gameWords;

  // إعداد الخدمات
  void setSupabaseService(SupabaseService service) {
    _supabaseService = service;
    _gameStateProvider.setSupabaseService(service);
    _gameRoomProvider.setSupabaseService(service);
    _gamePlayerProvider.setSupabaseService(service);
  }

  void setExperienceService(ExperienceService service) {
    _experienceService = service;
    _gameRewardsProvider.setExperienceService(service);
  }

  // وظائف اللعبة الرئيسية
  bool joinRoom(String roomId, String playerId, String playerName) {
    final result = _gameRoomProvider.joinRoom(roomId, playerId, playerName);
    if (result) {
      _gamePlayerProvider.currentPlayer = _gameRoomProvider.currentRoom?.players.firstWhere(
            (p) => p.id == playerId,
        orElse: () => _gamePlayerProvider.currentPlayer!,
      );
      notifyListeners();
    }
    return result;
  }

  void updateRoomFromServer(GameRoom serverRoom, String playerId) {
    _gameRoomProvider.updateRoomFromServer(serverRoom, playerId);
    _gamePlayerProvider.updatePlayerFromServer(serverRoom, playerId);
    _gameStateProvider.updateStateFromServer(serverRoom);
    notifyListeners();
  }

  GameRoom createRoom({
    required String name,
    required String creatorId,
    required String creatorName,
    required int maxPlayers,
    required int totalRounds,
    required int roundDuration,
    String? roomId,
  }) {
    final room = _gameRoomProvider.createRoom(
      name: name,
      creatorId: creatorId,
      creatorName: creatorName,
      maxPlayers: maxPlayers,
      totalRounds: totalRounds,
      roundDuration: roundDuration,
      roomId: roomId,
    );

    _gamePlayerProvider.currentPlayer = room.players.firstWhere((p) => p.id == creatorId);
    notifyListeners();
    return room;
  }

  void rejoinRoom(GameRoom room, String playerId) {
    _gameRoomProvider.rejoinRoom(room, playerId);
    _gamePlayerProvider.rejoinRoom(room, playerId);
    _gameStateProvider.updateStateFromServer(room);
    notifyListeners();
  }

  void updateConnectionStatus(String playerId, bool isConnected) {
    _gameRoomProvider.updateConnectionStatus(playerId, isConnected);
    _gamePlayerProvider.updateConnectionStatus(playerId, isConnected);
    notifyListeners();
  }

  void updateRoomFromRealtime(GameRoom updatedRoom, String playerId) {
    _gameRoomProvider.updateRoomFromRealtime(updatedRoom, playerId);
    _gamePlayerProvider.updatePlayerFromRealtime(updatedRoom, playerId);
    _gameStateProvider.updateStateFromRealtime(updatedRoom);
    _gameRewardsProvider.checkGameEndRewards(updatedRoom, _gamePlayerProvider.currentPlayer);
    notifyListeners();
  }

  void leaveRoom() {
    _gameRoomProvider.leaveRoom();
    _gamePlayerProvider.leaveRoom();
    _gameStateProvider.resetState();
    _gameSoundProvider.stopAllSounds();
    notifyListeners();
  }

  void resetAll() {
    _gameRoomProvider.resetAll();
    _gamePlayerProvider.resetAll();
    _gameStateProvider.resetState();
    _gameSoundProvider.stopAllSounds();
    _gameRewardsProvider.resetRewards();
    notifyListeners();
  }

  // وظائف بدء اللعبة
  bool canStartGame() {
    return _gameStateProvider.canStartGame(
      _gameRoomProvider.currentRoom,
      _gamePlayerProvider.currentPlayer,
    );
  }

  void startGame() {
    _gameStateProvider.startGame(
      _gameRoomProvider.currentRoom,
      _gamePlayerProvider.currentPlayer,
      _gameWords,
    );
    notifyListeners();
  }

  bool startGameManually() {
    final result = _gameStateProvider.startGameManually(
      _gameRoomProvider.currentRoom,
      _gamePlayerProvider.currentPlayer,
    );
    if (result) {
      notifyListeners();
    }
    return result;
  }

  Future<bool> startGameWithServer() async {
    final result = await _gameStateProvider.startGameWithServer(
      _gameRoomProvider.currentRoom,
      _gamePlayerProvider.currentPlayer,
      _supabaseService,
    );
    if (result) {
      notifyListeners();
    }
    return result;
  }

  // وظائف التصويت
  void votePlayer(String voterId, String targetId) {
    _gameStateProvider.votePlayer(
      _gameRoomProvider.currentRoom,
      voterId,
      targetId,
    );
    notifyListeners();
  }

  Future<bool> votePlayerWithServer(String targetId) async {
    final result = await _gameStateProvider.votePlayerWithServer(
      _gameRoomProvider.currentRoom,
      _gamePlayerProvider.currentPlayer,
      targetId,
      _supabaseService,
    );
    if (result) {
      notifyListeners();
    }
    return result;
  }

  Future<bool> voteToContinueWithServer(bool continuePlaying) async {
    final result = await _gameStateProvider.voteToContinueWithServer(
      _gameRoomProvider.currentRoom,
      _gamePlayerProvider.currentPlayer,
      continuePlaying,
      _supabaseService,
    );
    if (result) {
      notifyListeners();
    }
    return result;
  }

  // وظائف الوقت والجولات
  void checkRoundTimeout() {
    _gameStateProvider.checkRoundTimeout(_gameRoomProvider.currentRoom);
    notifyListeners();
  }

  // وظائف المكافآت والإحصائيات
  Future<void> loadPlayerStats(String playerId) async {
    await _gameRewardsProvider.loadPlayerStats(
      playerId,
      _gamePlayerProvider.currentPlayer?.name ?? 'لاعب مجهول',
      _experienceService,
    );
    notifyListeners();
  }

  Future<void> processGameEndWithRewards() async {
    await _gameRewardsProvider.processGameEndWithRewards(
      _gameRoomProvider.currentRoom,
      _experienceService,
    );
    notifyListeners();
  }

  void clearLastGameRewards() {
    _gameRewardsProvider.clearLastGameRewards();
    notifyListeners();
  }

  void checkAndProcessGameRewards() {
    _gameRewardsProvider.checkAndProcessGameRewards(
      _gameRoomProvider.currentRoom,
    );
    notifyListeners();
  }

  // وظائف التحقق والتحقق من الصحة
  bool validateGameState() {
    return _gameStateProvider.validateGameState(
      _gameRoomProvider.currentRoom,
      _gamePlayerProvider.currentPlayer,
    );
  }

  bool validateAndFixGameState() {
    final result = _gameRoomProvider.validateAndFixGameState(
      _gamePlayerProvider.currentPlayer,
    );
    if (result) {
      notifyListeners();
    }
    return result;
  }

  bool hasStateChanged() {
    return _gameStateProvider.hasStateChanged();
  }

  bool hasPlayersCountChanged() {
    return _gameRoomProvider.hasPlayersCountChanged();
  }

  // وظائف الإشعارات والتحديثات
  void forceUpdate() {
    notifyListeners();
  }

  void notifyRoomUpdate() {
    notifyListeners();
  }

  // تنظيف الموارد
  @override
  void dispose() {
    _gameRoomProvider.dispose();
    _gamePlayerProvider.dispose();
    _gameStateProvider.dispose();
    _gameSoundProvider.dispose();
    _gameRewardsProvider.dispose();
    super.dispose();
  }
}