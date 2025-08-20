import 'dart:developer';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/game_room_model.dart';
import '../models/player_model.dart';
import '../providers/game_provider.dart';

/// خدمة إدارة الغرف - إنشاء، جلب، حذف الغرف
class RoomService {
  final SupabaseClient _client = Supabase.instance.client;

  /// إنشاء غرفة جديدة مع التحقق من الحالة الحالية
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

// في دالة getRoomById، أضف السطر التالي:
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
        revealedSpyId: response['revealed_spy_id'],
        winner: response['winner'], // *** إضافة الحقل الجديد ***
      );
    } catch (e) {
      log('خطأ في جلب معلومات الغرفة: $e');
      return null;
    }
  }

// في دالة getAvailableRooms، أضف السطر التالي في حلقة التكرار:
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
            revealedSpyId: roomData['revealed_spy_id'],
            winner: roomData['winner'], // *** إضافة الحقل الجديد ***
          ));
        } catch (e) {
          log('خطأ في معالجة غرفة: $e');
          continue;
        }
      }

      log('تم جلب ${rooms.length} غرفة من قاعدة البيانات');
      return rooms;
    } catch (e) {
      log('خطأ في جلب الغرف: $e');
      return [];
    }
  }

  /// حذف غرفة (للمالك فقط)
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

  /// تنظيف الغرف المنتهية
  Future<void> cleanupFinishedRoom(String roomId) async {
    try {
      await _client.from('players').delete().eq('room_id', roomId);
      await _client.from('rooms').delete().eq('id', roomId);
      log('تم تنظيف الغرفة المنتهية: $roomId');
    } catch (e) {
      log('خطأ في تنظيف الغرفة: $e');
    }
  }

  /// دالة جديدة لإشعار المنشئ باكتمال العدد
  Future<void> notifyRoomFull(String roomId, String creatorId) async {
    try {
      await _client.from('rooms').update({
        'ready_to_start': true,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', roomId);

      log('تم إشعار المنشئ $creatorId باكتمال العدد في الغرفة $roomId');
    } catch (e) {
      log('خطأ في إشعار اكتمال العدد: $e');
    }
  }

  GameState _parseGameState(String? state) {
    switch (state?.toLowerCase()) {
      case 'waiting':
        return GameState.waiting;
      case 'playing':
        return GameState.playing;
      case 'voting':
        return GameState.voting;
      case 'continue_voting':
        return GameState.continueVoting;
      case 'finished':
        return GameState.finished;
      default:
        log('حالة غير معروفة: $state');
        return GameState.waiting;
    }
  }
}