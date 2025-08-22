// lib/services/online_users_service.dart
import 'dart:async';
import 'dart:developer';
import 'package:supabase_flutter/supabase_flutter.dart';

class OnlineUser {
  final String id;
  final String name;
  final bool isOnline;
  final String? currentRoomId;
  final String? currentRoomName;
  final bool isInGame;
  final DateTime lastSeen;

  OnlineUser({
    required this.id,
    required this.name,
    required this.isOnline,
    this.currentRoomId,
    this.currentRoomName,
    required this.isInGame,
    required this.lastSeen,
  });

  factory OnlineUser.fromMap(Map<String, dynamic> map) {
    return OnlineUser(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      isOnline: map['is_online'] ?? false,
      currentRoomId: map['current_room_id'],
      currentRoomName: map['current_room_name'],
      isInGame: map['is_in_game'] ?? false,
      lastSeen: DateTime.tryParse(map['last_seen'] ?? '') ?? DateTime.now(),
    );
  }
}

class Invitation {
  final String id;
  final String fromPlayerId;
  final String fromPlayerName;
  final String toPlayerId;
  final String roomId;
  final String roomName;
  final DateTime createdAt;
  final String status; // 'pending', 'accepted', 'declined'

  Invitation({
    required this.id,
    required this.fromPlayerId,
    required this.fromPlayerName,
    required this.toPlayerId,
    required this.roomId,
    required this.roomName,
    required this.createdAt,
    required this.status,
  });

  factory Invitation.fromMap(Map<String, dynamic> map) {
    return Invitation(
      id: map['id'] ?? '',
      fromPlayerId: map['from_player_id'] ?? '',
      fromPlayerName: map['from_player_name'] ?? '',
      toPlayerId: map['to_player_id'] ?? '',
      roomId: map['room_id'] ?? '',
      roomName: map['room_name'] ?? '',
      createdAt: DateTime.tryParse(map['created_at'] ?? '') ?? DateTime.now(),
      status: map['status'] ?? 'pending',
    );
  }
}

class OnlineUsersService {
  final SupabaseClient _client = Supabase.instance.client;
  StreamSubscription? _onlineUsersSubscription;
  StreamSubscription? _invitationsSubscription;

  /// تحديث حالة المستخدم (متصل/غير متصل)
  Future<void> updateUserStatus(String playerId, String playerName, bool isOnline, {String? roomId, String? roomName}) async {
    try {
      await _client.from('online_users').upsert({
        'id': playerId,
        'name': playerName,
        'is_online': isOnline,
        'current_room_id': roomId,
        'current_room_name': roomName,
        'is_in_game': roomId != null,
        'last_seen': DateTime.now().toIso8601String(),
      });

      log('تم تحديث حالة المستخدم: $playerName - متصل: $isOnline');
    } catch (e) {
      log('خطأ في تحديث حالة المستخدم: $e');
    }
  }

  /// الحصول على المستخدمين المتصلين
  Future<List<OnlineUser>> getOnlineUsers(String excludePlayerId) async {
    try {
      final response = await _client
          .from('online_users')
          .select('*')
          .neq('id', excludePlayerId)
          .eq('is_online', true)
          .gte('last_seen', DateTime.now().subtract(const Duration(minutes: 5)).toIso8601String())
          .order('last_seen', ascending: false);

      return response.map<OnlineUser>((data) => OnlineUser.fromMap(data)).toList();
    } catch (e) {
      log('خطأ في جلب المستخدمين المتصلين: $e');
      return [];
    }
  }

  /// الاستماع للمستخدمين المتصلين
  Stream<List<OnlineUser>> listenToOnlineUsers(String excludePlayerId) {
    return _client
        .from('online_users')
        .stream(primaryKey: ['id'])
        .asyncMap((data) async {
      // تصفية البيانات يدويًا بعد استلامها
      final filteredData = data.where((user) =>
      user['id'] != excludePlayerId &&
          user['is_online'] == true
      ).toList();

      return filteredData.map<OnlineUser>((user) =>
          OnlineUser.fromMap(user)
      ).toList();
    });
  }

  /// إرسال دعوة للعب
  Future<bool> sendInvitation({
    required String fromPlayerId,
    required String fromPlayerName,
    required String toPlayerId,
    required String roomId,
    required String roomName,
  }) async {
    try {
      // التحقق من عدم وجود دعوة معلقة مسبقاً
      final existingInvitation = await _client
          .from('invitations')
          .select('id')
          .eq('from_player_id', fromPlayerId)
          .eq('to_player_id', toPlayerId)
          .eq('status', 'pending')
          .maybeSingle();

      if (existingInvitation != null) {
        log('توجد دعوة معلقة مسبقاً');
        return false;
      }

      await _client.from('invitations').insert({
        'from_player_id': fromPlayerId,
        'from_player_name': fromPlayerName,
        'to_player_id': toPlayerId,
        'room_id': roomId,
        'room_name': roomName,
        'status': 'pending',
        'created_at': DateTime.now().toIso8601String(),
      });

      log('تم إرسال دعوة من $fromPlayerName إلى $toPlayerId');
      return true;
    } catch (e) {
      log('خطأ في إرسال الدعوة: $e');
      return false;
    }
  }

  /// الاستماع للدعوات الواردة
  Stream<List<Invitation>> listenToInvitations(String playerId) {
    return _client
        .from('invitations')
        .stream(primaryKey: ['id'])
        .asyncMap((data) async {
      // تصفية البيانات يدويًا بعد استلامها
      final filteredData = data.where((invitation) =>
      invitation['to_player_id'] == playerId &&
          invitation['status'] == 'pending'
      ).toList();

      return filteredData.map<Invitation>((invitation) =>
          Invitation.fromMap(invitation)
      ).toList();
    });
  }

  /// الرد على الدعوة
  Future<bool> respondToInvitation(String invitationId, String status) async {
    try {
      await _client
          .from('invitations')
          .update({'status': status})
          .eq('id', invitationId);

      log('تم الرد على الدعوة: $status');
      return true;
    } catch (e) {
      log('خطأ في الرد على الدعوة: $e');
      return false;
    }
  }

  /// حذف الدعوات القديمة
  Future<void> cleanupOldInvitations() async {
    try {
      final cutoffTime = DateTime.now().subtract(const Duration(minutes: 10)).toIso8601String();

      await _client
          .from('invitations')
          .delete()
          .lt('created_at', cutoffTime);

      log('تم تنظيف الدعوات القديمة');
    } catch (e) {
      log('خطأ في تنظيف الدعوات القديمة: $e');
    }
  }

  /// تنظيف الموارد
  void dispose() {
    _onlineUsersSubscription?.cancel();
    _invitationsSubscription?.cancel();
  }
}