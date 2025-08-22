import 'dart:developer';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:voice_rooms_app/services/user_services/online_users_service.dart';
import '../models/game_room_model.dart';
import '../providers/game_provider.dart';

// استيراد الخدمات المقسمة
import '../providers/game_state.dart';
import 'room_service.dart';
import 'player_service.dart';
import 'game_logic_service.dart';
import 'voting_service.dart';
import 'signaling_service.dart';

/// الخدمة الرئيسية التي تجمع جميع خدمات Supabase
class SupabaseService {
  // الخدمات المختصة
  final RoomService _roomService = RoomService();
  final PlayerService _playerService = PlayerService();
  final GameLogicService _gameLogicService = GameLogicService();
  final VotingService _votingService = VotingService();
  final SignalingService _signalingService = SignalingService();
  final OnlineUsersService _onlineUsersService = OnlineUsersService();

  // ===== خدمات الغرف =====

  /// إنشاء غرفة جديدة
  Future<String?> createRoom({
    required String name,
    required String creatorId,
    required int maxPlayers,
    required int totalRounds,
    required int roundDuration,
    String? creatorName, // إضافة معامل اسم المنشئ
  }) async {
    return await _roomService.createRoom(
      name: name,
      creatorId: creatorId,
      maxPlayers: maxPlayers,
      totalRounds: totalRounds,
      roundDuration: roundDuration,
      creatorName: creatorName ?? 'منشئ الغرفة', // تمرير الاسم
    );
  }

  /// تحديث حالة المستخدم
  Future<void> updateUserOnlineStatus(String playerId, String playerName, bool isOnline, {String? roomId, String? roomName}) async {
    return await _onlineUsersService.updateUserStatus(playerId, playerName, isOnline, roomId: roomId, roomName: roomName);
  }

  /// الحصول على المستخدمين المتصلين
  Future<List<OnlineUser>> getOnlineUsers(String excludePlayerId) async {
    return await _onlineUsersService.getOnlineUsers(excludePlayerId);
  }

  /// الاستماع للمستخدمين المتصلين
  Stream<List<OnlineUser>> listenToOnlineUsers(String excludePlayerId) {
    return _onlineUsersService.listenToOnlineUsers(excludePlayerId);
  }

  /// إرسال دعوة
  Future<bool> sendInvitation({
    required String fromPlayerId,
    required String fromPlayerName,
    required String toPlayerId,
    required String roomId,
    required String roomName,
  }) async {
    return await _onlineUsersService.sendInvitation(
      fromPlayerId: fromPlayerId,
      fromPlayerName: fromPlayerName,
      toPlayerId: toPlayerId,
      roomId: roomId,
      roomName: roomName,
    );
  }

  /// الاستماع للدعوات
  Stream<List<Invitation>> listenToInvitations(String playerId) {
    return _onlineUsersService.listenToInvitations(playerId);
  }

  /// الرد على الدعوة
  Future<bool> respondToInvitation(String invitationId, String status) async {
    return await _onlineUsersService.respondToInvitation(invitationId, status);
  }

  /// تنظيف الدعوات القديمة
  Future<void> cleanupOldInvitations() async {
    return await _onlineUsersService.cleanupOldInvitations();
  }

  /// الحصول على الغرف المتاحة
  Future<List<GameRoom>> getAvailableRooms() async {
    return await _roomService.getAvailableRooms();
  }

  /// الحصول على معلومات غرفة بالمعرف
  Future<GameRoom?> getRoomById(String roomId) async {
    return await _roomService.getRoomById(roomId);
  }

  /// حذف غرفة (للمالك فقط)
  Future<bool> deleteRoom(String roomId, String userId) async {
    return await _roomService.deleteRoom(roomId, userId);
  }

  // ===== خدمات اللاعبين =====

  /// التحقق من حالة المستخدم
  Future<UserStatus> checkUserStatus(String playerId) async {
    return await _playerService.checkUserStatus(playerId);
  }

  /// الانضمام للغرفة
  Future<JoinResult> joinRoom(String roomId, String playerId, String playerName) async {
    return await _playerService.joinRoom(roomId, playerId, playerName);
  }

  /// مغادرة الغرفة
  Future<void> leaveRoom(String playerId) async {
    return await _playerService.leaveRoom(playerId);
  }

  /// الاستماع لتحديثات اللاعبين
  Stream<List<Map<String, dynamic>>> listenToPlayers(String roomId) {
    return _playerService.listenToPlayers(roomId);
  }

  // ===== خدمات منطق اللعبة =====

  /// التحقق من إمكانية بدء اللعبة
  Future<bool> canStartGame(String roomId, String creatorId) async {
    return await _gameLogicService.canStartGame(roomId, creatorId);
  }

  /// بدء اللعبة بواسطة المنشئ
  Future<bool> startGameByCreator(String roomId, String creatorId) async {
    return await _gameLogicService.startGameByCreator(roomId, creatorId);
  }

  /// بدء اللعبة (دالة أساسية)
  Future<void> startGame(String roomId, String spyId, String word) async {
    return await _gameLogicService.startGame(roomId, spyId, word);
  }

  /// انتهاء الجولة والانتقال للتصويت
  Future<bool> endRoundAndStartVoting(String roomId) async {
    return await _gameLogicService.endRoundAndStartVoting(roomId);
  }

  /// الاستماع لتحديثات الغرفة
  Stream<Map<String, dynamic>> listenToRoom(String roomId) {
    return _gameLogicService.listenToRoom(roomId);
  }

  // ===== خدمات التصويت =====

  /// تحديث التصويت
  Future<void> updateVote(String playerId, String targetId) async {
    return await _votingService.updateVote(playerId, targetId);
  }

  /// التحقق من انتهاء التصويت
  Future<void> checkVotingComplete(String roomId) async {
    return await _votingService.checkVotingComplete(roomId);
  }

  /// التصويت على إكمال الجولات
  Future<void> voteToContinue(String playerId, bool continuePlaying) async {
    return await _votingService.voteToContinue(playerId, continuePlaying);
  }

  // ===== خدمات WebRTC Signaling =====

  /// إرسال إشارة WebRTC
  Future<bool> sendSignal({
    required String roomId,
    required String fromPeer,
    required String toPeer,
    required String type,
    required Map<String, dynamic> data,
  }) async {
    try {
      final signalingService = SignalingService();
      return await signalingService.sendSignal(
        roomId: roomId,
        fromPeer: fromPeer,
        toPeer: toPeer,
        type: type,
        data: data,
      );
    } catch (e) {
      log('خطأ في إرسال الإشارة: $e');
      return false;
    }
  }

  /// الاستماع للإشارات مع fallback
  Stream<Map<String, dynamic>> listenToSignalsWithFallback(String playerId) {
    final signalingService = SignalingService();
    return signalingService.listenToSignalsWithFallback(playerId);
  }

  /// حذف إشارة بأمان
  Future<void> deleteSignalSafe(dynamic signalId, String? playerId) async {
    try {
      final signalingService = SignalingService();
      await signalingService.deleteSignalSafe(signalId, playerId);
    } catch (e) {
      log('خطأ في حذف الإشارة: $e');
    }
  }

  /// تنظيف الإشارات القديمة
  Future<void> cleanupOldSignals(String roomId) async {
    try {
      final signalingService = SignalingService();
      await signalingService.cleanupOldSignals(roomId);
    } catch (e) {
      log('خطأ في تنظيف الإشارات: $e');
    }
  }

  /// الاستماع للإشارات
  Stream<Map<String, dynamic>> listenToSignals(String peerId) {
    return _signalingService.listenToSignals(peerId);
  }

  /// حذف إشارة
  Future<void> deleteSignal(int signalId) async {
    return await _signalingService.deleteSignal(signalId);
  }

  /// تنظيف الإشارة المستلمة
  Future<void> clearReceivedSignal(String playerId) async {
    return await _signalingService.clearReceivedSignal(playerId);
  }

  /// إنهاء اللعبة مع عرض الجاسوس الحقيقي
  Future<void> endGameAndRevealSpy(String roomId, String winner, String? spyId) async {
    return await _gameLogicService.endGameAndRevealSpy(roomId, winner, spyId);
  }

  /// التحقق من عدد اللاعبين المتبقين وإنهاء اللعبة إذا لزم الأمر
  Future<bool> checkAndHandleInsufficientPlayers(String roomId) async {
    try {
      final roomData = await _roomService.getRoomById(roomId);
      if (roomData == null) return false;

      final connectedPlayers = roomData.players.where((p) => p.isConnected).length;

      if (connectedPlayers < 3) {
        // إنهاء اللعبة تلقائياً
        final remainingSpies = roomData.players.where((p) => p.role == PlayerRole.spy && p.isConnected).toList();
        final winner = remainingSpies.isNotEmpty ? 'spy' : 'normal_players';

        await endGameAndRevealSpy(roomId, winner, roomData.spyId);
        return true; // تم إنهاء اللعبة
      }

      return false; // اللعبة مستمرة
    } catch (e) {
      log('خطأ في فحص عدد اللاعبين: $e');
      return false;
    }
  }

}