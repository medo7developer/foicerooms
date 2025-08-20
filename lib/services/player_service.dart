import 'dart:developer';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/game_provider.dart';
import 'room_service.dart';

/// خدمة إدارة اللاعبين - انضمام، مغادرة، حالة اللاعبين
class PlayerService {
  final SupabaseClient _client = Supabase.instance.client;
  final RoomService _roomService = RoomService();

  /// التحقق من حالة المستخدم الحالية
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
        await _roomService.cleanupFinishedRoom(roomId);
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

  /// انضمام لاعب للغرفة مع التحقق من الشروط
  Future<JoinResult> joinRoom(String roomId, String playerId, String playerName) async {
    try {
      final userStatus = await checkUserStatus(playerId);
      if (userStatus.inRoom) {
        log('المستخدم موجود بالفعل في غرفة: ${userStatus.roomId}');
        return JoinResult(
          success: false,
          reason: 'أنت موجود بالفعل في غرفة "${userStatus.roomName}"',
          existingRoomId: userStatus.roomId,
        );
      }

      final roomData = await _client
          .from('rooms')
          .select('id, max_players, state, creator_id, players(*)')
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

      // إضافة اللاعب باستخدام upsert لتجنب duplicate key
      await _client.from('players').upsert({
        'id': playerId,
        'name': playerName,
        'room_id': roomId,
        'is_connected': true,
        'is_voted': false,
        'votes': 0,
        'role': 'normal',
      }, onConflict: 'id'); // تحديد العمود المتصادم

      // التحقق من اكتمال العدد وإشعار المنشئ
      final updatedCount = currentPlayers + 1;
      if (updatedCount >= maxPlayers) {
        await _roomService.notifyRoomFull(roomId, roomData['creator_id']);
      }

      log('انضم اللاعب $playerName للغرفة $roomId (${updatedCount}/$maxPlayers)');
      return JoinResult(success: true, reason: 'تم الانضمام بنجاح');

    } catch (e) {
      log('خطأ في الانضمام للغرفة: $e');
      return JoinResult(success: false, reason: 'خطأ في الاتصال، حاول مرة أخرى');
    }
  }

  /// إضافة دالة لتنظيف بيانات اللاعبين المنقطعين
  Future<void> cleanupDisconnectedPlayers() async {
    try {
      // حذف اللاعبين من الغرف المنتهية أو المحذوفة
      await _client.rpc('cleanup_orphaned_players');
      log('تم تنظيف بيانات اللاعبين المنقطعين');
    } catch (e) {
      log('خطأ في تنظيف بيانات اللاعبين: $e');
    }
  }

  /// مغادرة اللاعب للغرفة
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

  /// الاستماع لتحديثات اللاعبين
  Stream<List<Map<String, dynamic>>> listenToPlayers(String roomId) {
    return _client
        .from('players')
        .stream(primaryKey: ['id'])
        .eq('room_id', roomId);
  }
}

/// كلاسات مساعدة لإدارة حالة المستخدم
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