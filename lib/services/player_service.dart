import 'dart:developer';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'room_service.dart';

/// خدمة إدارة اللاعبين - انضمام، مغادرة، حالة اللاعبين
class PlayerService {
  final SupabaseClient _client = Supabase.instance.client;
  final RoomService _roomService = RoomService();

  /// انضمام لاعب للغرفة مع التحقق من الشروط والمزامنة المحسنة
  Future<JoinResult> joinRoom(String roomId, String playerId, String playerName) async {
    try {
      log('🔄 محاولة انضمام اللاعب $playerName للغرفة $roomId');

      // التحقق من حالة المستخدم مع إعادة المحاولة
      UserStatus userStatus;
      int retryCount = 0;
      do {
        userStatus = await checkUserStatus(playerId);
        if (userStatus.inRoom && retryCount < 2) {
          // محاولة تنظيف البيانات القديمة
          await _cleanupPlayerData(playerId);
          retryCount++;
          await Future.delayed(const Duration(milliseconds: 300));
        } else {
          break;
        }
      } while (retryCount < 3);

      if (userStatus.inRoom) {
        log('❌ المستخدم موجود بالفعل في غرفة: ${userStatus.roomId}');
        return JoinResult(
          success: false,
          reason: 'أنت موجود بالفعل في غرفة "${userStatus.roomName}"',
          existingRoomId: userStatus.roomId,
        );
      }

      // جلب معلومات الغرفة مع إعادة المحاولة
      Map<String, dynamic>? roomData;
      for (int i = 0; i < 3; i++) {
        try {
          roomData = await _client
              .from('rooms')
              .select('id, name, max_players, state, creator_id, players(*)')
              .eq('id', roomId)
              .maybeSingle();

          if (roomData != null) break;

          if (i < 2) await Future.delayed(const Duration(milliseconds: 300));
        } catch (e) {
          log('محاولة ${i + 1} فشلت في جلب معلومات الغرفة: $e');
          if (i == 2) rethrow;
        }
      }

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

      // إضافة اللاعب مع المزامنة المحسنة
      try {
        await _client.from('players').upsert({
          'id': playerId,
          'name': playerName,
          'room_id': roomId,
          'is_connected': true,
          'is_voted': false,
          'votes': 0,
          'role': 'normal',
        }, onConflict: 'id');

        log('✅ تم إضافة اللاعب في قاعدة البيانات');

        // انتظار قصير للتأكد من المزامنة
        await Future.delayed(const Duration(milliseconds: 200));

        // التحقق من نجاح الإضافة
        final verificationData = await _client
            .from('players')
            .select('id, room_id')
            .eq('id', playerId)
            .maybeSingle();

        if (verificationData == null || verificationData['room_id'] != roomId) {
          log('❌ فشل التحقق من إضافة اللاعب');
          return JoinResult(success: false, reason: 'فشل في التأكد من الانضمام');
        }

        log('✅ تم التحقق من نجاح الانضمام');

      } catch (e) {
        log('❌ خطأ في إضافة اللاعب: $e');
        return JoinResult(success: false, reason: 'خطأ في حفظ البيانات');
      }

      // التحقق من اكتمال العدد وإشعار المنشئ
      final updatedCount = currentPlayers + 1;
      if (updatedCount >= maxPlayers) {
        try {
          await _roomService.notifyRoomFull(roomId, roomData['creator_id']);
        } catch (e) {
          log('تحذير: فشل في إشعار اكتمال العدد: $e');
        }
      }

      log('✅ انضم اللاعب $playerName للغرفة $roomId (${updatedCount}/$maxPlayers)');
      return JoinResult(success: true, reason: 'تم الانضمام بنجاح');

    } catch (e) {
      log('❌ خطأ عام في الانضمام للغرفة: $e');
      return JoinResult(success: false, reason: 'خطأ في الاتصال، حاول مرة أخرى');
    }
  }

  /// دالة محسنة لتنظيف بيانات اللاعب
  Future<void> _cleanupPlayerData(String playerId) async {
    try {
      log('🧹 تنظيف بيانات اللاعب القديمة: $playerId');

      // الحصول على معلومات اللاعب الحالية
      final playerData = await _client
          .from('players')
          .select('room_id, rooms(state)')
          .eq('id', playerId)
          .maybeSingle();

      if (playerData != null) {
        final roomState = playerData['rooms']?['state'];

        // حذف اللاعب من الغرف المنتهية أو غير النشطة
        if (roomState == null || roomState == 'finished' || roomState == 'cancelled') {
          await _client.from('players').delete().eq('id', playerId);
          log('✅ تم حذف اللاعب من غرفة منتهية');
        }
      }
    } catch (e) {
      log('تحذير: خطأ في تنظيف بيانات اللاعب: $e');
    }
  }

  /// دالة محسنة للتحقق من حالة المستخدم
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

      final roomData = playerData['rooms'];
      final roomState = roomData['state'];
      final roomId = roomData['id'];
      final creatorId = roomData['creator_id'];

      // تنظيف الغرف المنتهية تلقائياً
      if (roomState == 'finished' || roomState == 'cancelled') {
        await _roomService.cleanupFinishedRoom(roomId);
        return UserStatus.free;
      }

      // التحقق من الحالات النشطة
      if (roomState == 'waiting' || roomState == 'playing' ||
          roomState == 'voting' || roomState == 'continue_voting') {
        return UserStatus(
          inRoom: true,
          roomId: roomId,
          roomName: roomData['name'],
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

  /// دالة محسنة لمغادرة الغرفة
  Future<void> leaveRoom(String playerId) async {
    try {
      log('🚪 محاولة مغادرة اللاعب $playerId للغرفة');

      // الحصول على معلومات الغرفة قبل المغادرة
      final playerData = await _client
          .from('players')
          .select('room_id, rooms!inner(creator_id, state)')
          .eq('id', playerId)
          .maybeSingle();

      if (playerData != null) {
        final roomId = playerData['room_id'];
        final roomData = playerData['rooms'];
        final creatorId = roomData['creator_id'];
        final roomState = roomData['state'];

        // حذف اللاعب
        await _client.from('players').delete().eq('id', playerId);
        log('✅ تم حذف اللاعب من قاعدة البيانات');

        // إذا كان منشئ الغرفة، احذف الغرفة كاملة
        if (creatorId == playerId) {
          await _client.from('rooms').delete().eq('id', roomId);
          log('✅ تم حذف الغرفة $roomId لأن المنشئ غادر');
        } else if (roomState == 'playing' || roomState == 'voting') {
          // في حالة اللعب، تحقق من عدد اللاعبين المتبقين
          final remainingPlayers = await _client
              .from('players')
              .select('id')
              .eq('room_id', roomId);

          if (remainingPlayers.length < 3) {
            // إنهاء اللعبة لعدم كفاية اللاعبين - إزالة updated_at
            await _client.from('rooms').update({
              'state': 'finished',
              'winner': 'cancelled',
            }).eq('id', roomId);
            log('⚠️ تم إنهاء اللعبة لعدم كفاية اللاعبين');
          }
        }

        // انتظار قصير للتأكد من المزامنة
        await Future.delayed(const Duration(milliseconds: 200));
      }

      log('✅ تمت مغادرة اللاعب $playerId بنجاح');
    } catch (e) {
      log('❌ خطأ في مغادرة الغرفة: $e');
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