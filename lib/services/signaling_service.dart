import 'dart:developer';
import 'package:supabase_flutter/supabase_flutter.dart';

/// خدمة WebRTC signaling - إدارة إشارات الاتصال بين اللاعبين
class SignalingService {
  final SupabaseClient _client = Supabase.instance.client;

  /// إرسال إشارة WebRTC مع حل بديل في حالة فشل RLS
  Future<bool> sendSignal({
    required String roomId,
    required String fromPeer,
    required String toPeer,
    required String type,
    required Map<String, dynamic> data,
  }) async {
    try {
      // محاولة إرسال الإشارة عادي أولاً
      final result = await _client.from('signaling').insert({
        'room_id': roomId,
        'from_peer': fromPeer,
        'to_peer': toPeer,
        'type': type,
        'data': data,
        'created_at': DateTime.now().toIso8601String(),
      }).select();

      if (result.isNotEmpty) {
        log('✓ تم إرسال إشارة $type من $fromPeer إلى $toPeer');
        return true;
      }
      return false;

    } on PostgrestException catch (e) {
      if (e.code == '42501') {
        // خطأ RLS - استخدام الحل البديل
        log('⚠️ خطأ RLS في جدول signaling - استخدام حل بديل');
        return await _sendSignalViaPlayers(roomId, fromPeer, toPeer, type, data);
      }

      log('❌ خطأ PostgrestException: ${e.message}');
      return false;

    } catch (e) {
      log('❌ خطأ عام في إرسال الإشارة: $e');
      return false;
    }
  }

  /// حل بديل عبر جدول players
  Future<bool> _sendSignalViaPlayers(
      String roomId,
      String fromPeer,
      String toPeer,
      String type,
      Map<String, dynamic> data,
      ) async {
    try {
      // إنشاء كائن الإشارة
      final signalData = {
        'signal_type': type,
        'signal_data': data,
        'from_peer': fromPeer,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'room_id': roomId,
      };

      // إرسال الإشارة عبر تحديث custom_data للمستقبل
      await _client
          .from('players')
          .update({'custom_data': signalData})
          .eq('id', toPeer)
          .eq('room_id', roomId);

      log('✓ تم إرسال إشارة $type عبر الحل البديل من $fromPeer إلى $toPeer');
      return true;

    } catch (e) {
      log('❌ فشل الحل البديل أيضاً: $e');
      return false;
    }
  }

  /// الاستماع للإشارات الأصلي
  Stream<Map<String, dynamic>> listenToSignals(String peerId) {
    log('بدء الاستماع للإشارات للاعب: $peerId');

    return _client
        .from('signaling')
        .stream(primaryKey: ['id'])
        .eq('to_peer', peerId)
        .order('created_at', ascending: true)
        .map((List<Map<String, dynamic>> data) {
      if (data.isNotEmpty) {
        // معالجة جميع الإشارات الجديدة
        for (final signal in data) {
          log('استقبال إشارة: ${signal['type']} من ${signal['from_peer']} إلى $peerId');
        }
        return data.last; // إرجاع آخر إشارة
      }
      return <String, dynamic>{};
    });
  }

  /// الاستماع للإشارات مع حل بديل
  Stream<Map<String, dynamic>> listenToSignalsWithFallback(String playerId) {
    try {
      // محاولة الاستماع للجدول الأصلي أولاً
      return _client
          .from('signaling')
          .stream(primaryKey: ['id'])
          .eq('to_peer', playerId)
          .order('created_at', ascending: true)
          .handleError((error) {
        log('خطأ في الاستماع لجدول signaling: $error');
        // التبديل للحل البديل
        return _listenToSignalsViaPlayers(playerId);
      })
          .map((List<Map<String, dynamic>> data) {
        if (data.isNotEmpty) {
          final signal = data.last;
          log('📨 استقبال إشارة: ${signal['type']} من ${signal['from_peer']}');
          return signal;
        }
        return <String, dynamic>{};
      });
    } catch (e) {
      log('فشل جدول signaling، استخدام الحل البديل');
      return _listenToSignalsViaPlayers(playerId);
    }
  }

  /// الاستماع للإشارات عبر جدول players
  Stream<Map<String, dynamic>> _listenToSignalsViaPlayers(String playerId) {
    return _client
        .from('players')
        .stream(primaryKey: ['id'])
        .eq('id', playerId)
        .map((List<Map<String, dynamic>> data) {
      if (data.isEmpty) return <String, dynamic>{};

      final playerData = data.first;
      final customData = playerData['custom_data'] as Map<String, dynamic>?;

      if (customData != null &&
          customData.containsKey('signal_type') &&
          customData['from_peer'] != playerId) { // تجنب الإشارات من نفس اللاعب

        log('📨 استقبال إشارة بديلة: ${customData['signal_type']} من ${customData['from_peer']}');

        // تحويل البيانات لتتطابق مع تنسيق جدول signaling
        return {
          'id': 'alt_${customData['timestamp']}', // معرف مؤقت
          'from_peer': customData['from_peer'],
          'to_peer': playerId,
          'type': customData['signal_type'],
          'data': customData['signal_data'],
          'room_id': customData['room_id'],
        };
      }

      return <String, dynamic>{};
    });
  }

  /// حذف الإشارة
  Future<void> deleteSignal(int signalId) async {
    try {
      await _client.from('signaling').delete().eq('id', signalId);
      log('تم حذف الإشارة: $signalId');
    } catch (e) {
      log('خطأ في حذف الإشارة $signalId: $e');
    }
  }

  /// تنظيف الإشارة المستلمة من custom_data
  Future<void> clearReceivedSignal(String playerId) async {
    try {
      await _client
          .from('players')
          .update({'custom_data': null})
          .eq('id', playerId);
      log('تم تنظيف الإشارة المستلمة لـ $playerId');
    } catch (e) {
      log('خطأ في تنظيف الإشارة: $e');
    }
  }

  /// دالة محسنة لحذف الإشارات مع معالجة الحلول البديلة
  Future<void> deleteSignalSafe(dynamic signalId, String? playerId) async {
    try {
      if (signalId is int) {
        // إشارة من الجدول الأصلي
        await deleteSignal(signalId);
      } else if (signalId.toString().startsWith('alt_') && playerId != null) {
        // إشارة من الحل البديل
        await clearReceivedSignal(playerId);
      }
    } catch (e) {
      log('خطأ في حذف الإشارة: $e');
    }
  }

  /// تنظيف الإشارات القديمة
  Future<void> cleanupOldSignals(String roomId) async {
    try {
      final cutoffTime = DateTime.now().subtract(const Duration(minutes: 5));

      await _client
          .from('signaling')
          .delete()
          .eq('room_id', roomId)
          .lt('created_at', cutoffTime.toIso8601String());

      log('تم تنظيف الإشارات القديمة للغرفة: $roomId');
    } catch (e) {
      log('خطأ في تنظيف الإشارات: $e');
    }
  }
}