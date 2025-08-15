import 'dart:developer';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/game_provider.dart';

class SupabaseService {
  final SupabaseClient _client = Supabase.instance.client;

  // إنشاء غرفة جديدة مع التحقق من الحالة الحالية
  Future<String?> createRoom({
    required String name,
    required String creatorId,
    required int maxPlayers,
    required int totalRounds,
    required int roundDuration,
  }) async {
    try {
      // التحقق من وجود المستخدم في غرفة أخرى أولاً
      final existingPlayer = await _client
          .from('players')
          .select('room_id, rooms!inner(state)')
          .eq('id', creatorId)
          .maybeSingle();

      if (existingPlayer != null) {
        final roomState = existingPlayer['rooms']['state'];
        if (roomState == 'waiting' || roomState == 'playing' || roomState == 'voting') {
          log('المستخدم موجود بالفعل في غرفة نشطة');
          return null; // المستخدم في غرفة نشطة
        }
      }

      final roomId = DateTime.now().millisecondsSinceEpoch.toString();

      // إنشاء الغرفة
      await _client.from('rooms').insert({
        'id': roomId,
        'name': name,
        'creator_id': creatorId,
        'max_players': maxPlayers,
        'total_rounds': totalRounds,
        'round_duration': roundDuration,
        'state': 'waiting',
        'created_at': DateTime.now().toIso8601String(),
      });

      // إضافة المنشئ كلاعب في الغرفة
      await _client.from('players').insert({
        'id': creatorId,
        'name': 'منشئ الغرفة', // سيتم تحديثه لاحقاً
        'room_id': roomId,
        'is_connected': true,
        'is_voted': false,
        'votes': 0,
        'role': 'normal',
      });

      log('تم إنشاء الغرفة: $roomId بواسطة $creatorId');
      return roomId;
    } catch (e) {
      log('خطأ في إنشاء الغرفة: $e');
      return null;
    }
  }

  // الحصول على الغرف المتاحة مع فلترة أفضل
  Future<List<GameRoom>> getAvailableRooms() async {
    try {
      final response = await _client
          .from('rooms')
          .select('*, players(*)')
          .inFilter('state', ['waiting', 'playing', 'voting'])
          .order('created_at', ascending: false);

      final List<GameRoom> rooms = [];

      for (final roomData in response) {
        try {
          final players = (roomData['players'] as List? ?? [])
              .map((p) => Player(
            id: p['id'] ?? '',
            name: p['name'] ?? 'لاعب',
            isConnected: p['is_connected'] ?? false,
            isVoted: p['is_voted'] ?? false,
            votes: p['votes'] ?? 0,
            role: (p['role'] == 'spy') ? PlayerRole.spy : PlayerRole.normal,
          ))
              .toList();

          rooms.add(GameRoom(
            id: roomData['id'] ?? '',
            name: roomData['name'] ?? 'غرفة بدون اسم',
            creatorId: roomData['creator_id'] ?? '',
            maxPlayers: roomData['max_players'] ?? 4,
            totalRounds: roomData['total_rounds'] ?? 3,
            roundDuration: roomData['round_duration'] ?? 300,
            players: players,
            state: _parseGameState(roomData['state']),
            currentRound: roomData['current_round'] ?? 0,
            currentWord: roomData['current_word'],
            spyId: roomData['spy_id'],
          ));
        } catch (e) {
          log('خطأ في معالجة غرفة: $e');
          continue; // تخطي الغرفة المعطوبة
        }
      }

      log('تم جلب ${rooms.length} غرفة من قاعدة البيانات');
      return rooms;
    } catch (e) {
      log('خطأ في جلب الغرف: $e');
      return [];
    }
  }

  // التحقق من حالة المستخدم الحالية
  Future<UserStatus> checkUserStatus(String playerId) async {
    try {
      final playerData = await _client
          .from('players')
          .select('room_id, rooms!inner(id, name, state, creator_id)')
          .eq('id', playerId)
          .maybeSingle();

      if (playerData == null) {
        return UserStatus.free;
      }

      final roomState = playerData['rooms']['state'];
      final roomId = playerData['rooms']['id'];
      final creatorId = playerData['rooms']['creator_id'];

      if (roomState == 'finished') {
        // تنظيف الغرف المنتهية
        await _cleanupFinishedRoom(roomId);
        return UserStatus.free;
      }

      if (roomState == 'waiting' || roomState == 'playing' || roomState == 'voting') {
        return UserStatus(
          inRoom: true,
          roomId: roomId,
          roomName: playerData['rooms']['name'],
          isOwner: creatorId == playerId,
          roomState: roomState,
        );
      }

      return UserStatus.free;
    } catch (e) {
      log('خطأ في التحقق من حالة المستخدم: $e');
      return UserStatus.free;
    }
  }

  // الانضمام لغرفة مع حماية محسنة
  Future<JoinResult> joinRoom(String roomId, String playerId, String playerName) async {
    try {
      // التحقق من حالة المستخدم أولاً
      final userStatus = await checkUserStatus(playerId);
      if (userStatus.inRoom) {
        log('المستخدم موجود بالفعل في غرفة: ${userStatus.roomId}');
        return JoinResult(
          success: false,
          reason: 'أنت موجود بالفعل في غرفة "${userStatus.roomName}"',
          existingRoomId: userStatus.roomId,
        );
      }

      // التحقق من حالة الغرفة وعدد اللاعبين
      final roomData = await _client
          .from('rooms')
          .select('id, max_players, state, players(*)')
          .eq('id', roomId)
          .maybeSingle();

      if (roomData == null) {
        return JoinResult(success: false, reason: 'الغرفة غير موجودة');
      }

      final roomState = roomData['state'];
      if (roomState != 'waiting') {
        return JoinResult(success: false, reason: 'الغرفة غير متاحة للانضمام');
      }

      final currentPlayers = (roomData['players'] as List? ?? []).length;
      final maxPlayers = roomData['max_players'] ?? 4;

      if (currentPlayers >= maxPlayers) {
        return JoinResult(success: false, reason: 'الغرفة ممتلئة');
      }

      // التحقق من عدم وجود اللاعب مسبقاً في هذه الغرفة
      final existingInRoom = await _client
          .from('players')
          .select('id')
          .eq('id', playerId)
          .eq('room_id', roomId)
          .maybeSingle();

      if (existingInRoom != null) {
        // تحديث حالة الاتصال فقط
        await _client.from('players').update({
          'is_connected': true,
          'name': playerName,
        }).eq('id', playerId).eq('room_id', roomId);

        log('تم تحديث حالة اللاعب $playerName في الغرفة $roomId');
        return JoinResult(success: true, reason: 'تم الانضمام بنجاح');
      }

      // إضافة اللاعب للغرفة
      await _client.from('players').insert({
        'id': playerId,
        'name': playerName,
        'room_id': roomId,
        'is_connected': true,
        'is_voted': false,
        'votes': 0,
        'role': 'normal',
      });

      log('انضم اللاعب $playerName للغرفة $roomId');
      return JoinResult(success: true, reason: 'تم الانضمام بنجاح');

    } catch (e) {
      log('خطأ في الانضمام للغرفة: $e');

      if (e.toString().contains('duplicate key')) {
        try {
          await _client.from('players').update({
            'room_id': roomId,
            'name': playerName,
            'is_connected': true,
            'is_voted': false,
            'votes': 0,
            'role': 'normal',
          }).eq('id', playerId);

          return JoinResult(success: true, reason: 'تم الانضمام بنجاح');
        } catch (updateError) {
          log('فشل في حل التعارض: $updateError');
        }
      }

      return JoinResult(success: false, reason: 'خطأ في الاتصال، حاول مرة أخرى');
    }
  }

  // تنظيف الغرف المنتهية
  Future<void> _cleanupFinishedRoom(String roomId) async {
    try {
      await _client.from('players').delete().eq('room_id', roomId);
      await _client.from('rooms').delete().eq('id', roomId);
      log('تم تنظيف الغرفة المنتهية: $roomId');
    } catch (e) {
      log('خطأ في تنظيف الغرفة: $e');
    }
  }

  // بدء اللعبة
  Future<void> startGame(String roomId, String spyId, String word) async {
    try {
      await _client.from('rooms').update({
        'state': 'playing',
        'current_round': 1,
        'spy_id': spyId,
        'current_word': word,
        'round_start_time': DateTime.now().toIso8601String(),
      }).eq('id', roomId);

      log('تم بدء اللعبة في الغرفة $roomId');
    } catch (e) {
      log('خطأ في بدء اللعبة: $e');
    }
  }

  // تحديث التصويت
  Future<void> updateVote(String playerId, String targetId) async {
    try {
      // تحديث حالة التصويت للاعب
      await _client.from('players').update({
        'is_voted': true,
      }).eq('id', playerId);

      // زيادة عدد الأصوات للهدف
      final currentVotes = await _client
          .from('players')
          .select('votes')
          .eq('id', targetId)
          .maybeSingle();

      if (currentVotes != null) {
        await _client.from('players').update({
          'votes': (currentVotes['votes'] ?? 0) + 1,
        }).eq('id', targetId);
      }

      log('تم تسجيل صوت من $playerId لـ $targetId');
    } catch (e) {
      log('خطأ في تسجيل التصويت: $e');
    }
  }

  // إرسال إشارة WebRTC
  Future<void> sendSignal({
    required String roomId,
    required String fromPeer,
    required String toPeer,
    required String type,
    required Map<String, dynamic> data,
  }) async {
    try {
      await _client.from('signaling').insert({
        'room_id': roomId,
        'from_peer': fromPeer,
        'to_peer': toPeer,
        'type': type,
        'data': data,
        'created_at': DateTime.now().toIso8601String(),
      });

      log('تم إرسال إشارة $type من $fromPeer إلى $toPeer');
    } catch (e) {
      log('خطأ في إرسال الإشارة: $e');
    }
  }

  // الاستماع للإشارات
  Stream<Map<String, dynamic>> listenToSignals(String peerId) {
    return _client
        .from('signaling')
        .stream(primaryKey: ['id'])
        .eq('to_peer', peerId)
        .map((List<Map<String, dynamic>> data) => data.isNotEmpty ? data.last : {});
  }

  // الاستماع لتحديثات الغرفة
  Stream<Map<String, dynamic>> listenToRoom(String roomId) {
    return _client
        .from('rooms')
        .stream(primaryKey: ['id'])
        .eq('id', roomId)
        .map((List<Map<String, dynamic>> data) => data.isNotEmpty ? data.first : {});
  }

  // الاستماع لتحديثات اللاعبين
  Stream<List<Map<String, dynamic>>> listenToPlayers(String roomId) {
    return _client
        .from('players')
        .stream(primaryKey: ['id'])
        .eq('room_id', roomId);
  }

  // مغادرة الغرفة
  Future<void> leaveRoom(String playerId) async {
    try {
      // الحصول على معلومات الغرفة قبل المغادرة
      final playerData = await _client
          .from('players')
          .select('room_id, rooms!inner(creator_id)')
          .eq('id', playerId)
          .maybeSingle();

      if (playerData != null) {
        final roomId = playerData['room_id'];
        final creatorId = playerData['rooms']['creator_id'];

        // حذف اللاعب
        await _client.from('players').delete().eq('id', playerId);

        // إذا كان منشئ الغرفة، احذف الغرفة كاملة
        if (creatorId == playerId) {
          await _client.from('rooms').delete().eq('id', roomId);
          log('تم حذف الغرفة $roomId لأن المنشئ غادر');
        }
      }

      log('غادر اللاعب $playerId الغرفة');
    } catch (e) {
      log('خطأ في مغادرة الغرفة: $e');
    }
  }

  // حذف إشارة بعد المعالجة
  Future<void> deleteSignal(int signalId) async {
    try {
      await _client.from('signaling').delete().eq('id', signalId);
    } catch (e) {
      log('خطأ في حذف الإشارة: $e');
    }
  }

  // حذف غرفة (للمالك فقط)
  Future<bool> deleteRoom(String roomId, String userId) async {
    try {
      // التحقق من أن المستخدم هو مالك الغرفة
      final room = await _client
          .from('rooms')
          .select('creator_id')
          .eq('id', roomId)
          .maybeSingle();

      if (room == null || room['creator_id'] != userId) {
        log('المستخدم غير مخول لحذف هذه الغرفة');
        return false;
      }

      // حذف الغرفة (سيتم حذف اللاعبين تلقائياً بسبب cascade)
      await _client.from('rooms').delete().eq('id', roomId);
      log('تم حذف الغرفة: $roomId');
      return true;
    } catch (e) {
      log('خطأ في حذف الغرفة: $e');
      return false;
    }
  }

  // الحصول على معلومات الغرفة بأمان
  Future<GameRoom?> getRoomById(String roomId) async {
    try {
      final response = await _client
          .from('rooms')
          .select('*, players(*)')
          .eq('id', roomId)
          .maybeSingle();

      if (response == null) {
        log('الغرفة $roomId غير موجودة');
        return null;
      }

      final players = (response['players'] as List? ?? [])
          .map((p) => Player(
        id: p['id'] ?? '',
        name: p['name'] ?? 'لاعب',
        isConnected: p['is_connected'] ?? false,
        isVoted: p['is_voted'] ?? false,
        votes: p['votes'] ?? 0,
        role: (p['role'] == 'spy') ? PlayerRole.spy : PlayerRole.normal,
      ))
          .toList();

      return GameRoom(
        id: response['id'] ?? '',
        name: response['name'] ?? 'غرفة',
        creatorId: response['creator_id'] ?? '',
        maxPlayers: response['max_players'] ?? 4,
        totalRounds: response['total_rounds'] ?? 3,
        roundDuration: response['round_duration'] ?? 300,
        players: players,
        state: _parseGameState(response['state']),
        currentRound: response['current_round'] ?? 0,
        currentWord: response['current_word'],
        spyId: response['spy_id'],
      );
    } catch (e) {
      log('خطأ في جلب معلومات الغرفة: $e');
      return null;
    }
  }

  GameState _parseGameState(String? state) {
    switch (state) {
      case 'waiting':
        return GameState.waiting;
      case 'playing':
        return GameState.playing;
      case 'voting':
        return GameState.voting;
      case 'finished':
        return GameState.finished;
      default:
        return GameState.waiting;
    }
  }
}

// كلاسات مساعدة لإدارة حالة المستخدم
class UserStatus {
  final bool inRoom;
  final String? roomId;
  final String? roomName;
  final bool isOwner;
  final String? roomState;

  UserStatus({
    this.inRoom = false,
    this.roomId,
    this.roomName,
    this.isOwner = false,
    this.roomState,
  });

  static UserStatus get free => UserStatus();
}

class JoinResult {
  final bool success;
  final String reason;
  final String? existingRoomId;

  JoinResult({
    required this.success,
    required this.reason,
    this.existingRoomId,
  });
}