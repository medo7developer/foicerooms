import 'dart:async';
import 'dart:developer';
import 'package:supabase_flutter/supabase_flutter.dart';

/// خدمة WebRTC signaling - إدارة إشارات الاتصال بين اللاعبين
class SignalingService {
  final SupabaseClient _client = Supabase.instance.client;

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

  Stream<Map<String, dynamic>> listenToSignalsWithFallback(String playerId) {
    log('🎧 بدء الاستماع المحسن للإشارات للاعب: $playerId');

    late StreamController<Map<String, dynamic>> controller;
    Timer? pollTimer;
    DateTime lastPollTime = DateTime.now().subtract(const Duration(seconds: 10));

    controller = StreamController<Map<String, dynamic>>(
      onListen: () {
        log('👂 بدء الاستماع النشط للإشارات');

        // الاستماع لـ Realtime updates
        _setupRealtimeSignalListener(controller, playerId);

        // إضافة polling كاحتياط
        pollTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
          _pollForSignals(controller, playerId, lastPollTime).then((_) {
            lastPollTime = DateTime.now();
          }).catchError((e) {
            log('❌ خطأ في polling للإشارات: $e');
          });
        });
      },
      onCancel: () {
        log('🛑 إيقاف الاستماع للإشارات');
        pollTimer?.cancel();
      },
    );

    return controller.stream;
  }

// دالة إعداد الاستماع المباشر
  void _setupRealtimeSignalListener(
      StreamController<Map<String, dynamic>> controller,
      String playerId) {

    try {
      _client
          .from('signaling')
          .stream(primaryKey: ['id'])
          .eq('to_peer', playerId)
          .order('created_at', ascending: true)
          .listen(
            (List<Map<String, dynamic>> data) {
          if (data.isNotEmpty && !controller.isClosed) {
            final signal = data.last;
            log('📨 استقبال إشارة realtime: ${signal['type']} من ${signal['from_peer']}');
            controller.add(signal);
          }
        },
        onError: (error) {
          log('❌ خطأ في realtime signals: $error');
          if (!controller.isClosed) {
            // لا نغلق controller، بل نعتمد على polling
            log('🔄 الاعتماد على polling بعد خطأ realtime');
          }
        },
      );
    } catch (e) {
      log('❌ فشل في إعداد realtime listener: $e');
      // نعتمد على polling فقط
    }
  }

// دالة polling للإشارات كحل احتياطي
  Future<void> _pollForSignals(
      StreamController<Map<String, dynamic>> controller,
      String playerId,
      DateTime lastPollTime) async {

    try {
      final signals = await _client
          .from('signaling')
          .select()
          .eq('to_peer', playerId)
          .gt('created_at', lastPollTime.toIso8601String())
          .order('created_at', ascending: true)
          .limit(10);

      for (final signal in signals) {
        if (!controller.isClosed) {
          log('📨 استقبال إشارة polling: ${signal['type']} من ${signal['from_peer']}');
          controller.add(signal);

          // حذف الإشارة بعد الإرسال
          _deleteSignalAsync(signal['id']);
        }
      }

    } catch (e) {
      log('❌ خطأ في polling للإشارات: $e');
    }
  }

// حذف إشارة بشكل غير متزامن
  void _deleteSignalAsync(dynamic signalId) {
    if (signalId != null) {
      Future.delayed(const Duration(milliseconds: 100), () {
        deleteSignal(signalId as int).catchError((e) {
          log('⚠️ خطأ في حذف إشارة $signalId: $e');
        });
      });
    }
  }

// تحسين دالة sendSignal لضمان التسليم:
  Future<bool> sendSignal({
    required String roomId,
    required String fromPeer,
    required String toPeer,
    required String type,
    required Map<String, dynamic> data,
  }) async {
    int maxRetries = 5; // زيادة عدد المحاولات
    int retryCount = 0;

    while (retryCount < maxRetries) {
      try {
        // محاولة الإرسال الأساسية
        final result = await _client.from('signaling').insert({
          'room_id': roomId,
          'from_peer': fromPeer,
          'to_peer': toPeer,
          'type': type,
          'data': data,
          'created_at': DateTime.now().toIso8601String(),
        }).select().timeout(const Duration(seconds: 8));

        if (result.isNotEmpty) {
          log('✅ تم إرسال إشارة $type من $fromPeer إلى $toPeer');

          // تأكيد إضافي بعد تأخير قصير
          Future.delayed(const Duration(milliseconds: 200), () {
            _verifySignalDelivery(roomId, fromPeer, toPeer, type);
          });

          return true;
        }

      } catch (e) {
        retryCount++;
        log('❌ فشل إرسال الإشارة (محاولة $retryCount/$maxRetries): $e');

        if (retryCount < maxRetries) {
          // انتظار متزايد مع jitter
          final delay = Duration(milliseconds: (retryCount * 1000) + (DateTime.now().millisecond % 500));
          await Future.delayed(delay);
        }
      }
    }

    // إذا فشلت جميع المحاولات، استخدم الحل البديل
    log('🔄 استخدام الحل البديل لإرسال إشارة $type');
    return await _sendSignalViaAlternativeMethod(roomId, fromPeer, toPeer, type, data);
  }

// التحقق من تسليم الإشارة
  Future<void> _verifySignalDelivery(String roomId, String fromPeer, String toPeer, String type) async {
    try {
      final recent = await _client
          .from('signaling')
          .select('id')
          .eq('room_id', roomId)
          .eq('from_peer', fromPeer)
          .eq('to_peer', toPeer)
          .eq('type', type)
          .gte('created_at', DateTime.now().subtract(const Duration(seconds: 5)).toIso8601String())
          .limit(1);

      if (recent.isEmpty) {
        log('⚠️ لم يتم العثور على الإشارة المرسلة، قد تحتاج إعادة الإرسال');
      } else {
        log('✅ تأكيد تسليم الإشارة $type');
      }
    } catch (e) {
      log('⚠️ خطأ في التحقق من تسليم الإشارة: $e');
    }
  }

// الحل البديل المحسن
  Future<bool> _sendSignalViaAlternativeMethod(
      String roomId,
      String fromPeer,
      String toPeer,
      String type,
      Map<String, dynamic> data,
      ) async {
    try {
      // استخدام جدول players كوسيط
      final signalPayload = {
        'signal_type': type,
        'signal_data': data,
        'from_peer': fromPeer,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'room_id': roomId,
      };

      // تحديث custom_data للمستقبل
      final result = await _client
          .from('players')
          .update({
        'custom_data': signalPayload,
        'updated_at': DateTime.now().toIso8601String(),
      })
          .eq('id', toPeer)
          .eq('room_id', roomId)
          .select();

      if (result.isNotEmpty) {
        log('✅ تم إرسال إشارة $type عبر الحل البديل');
        return true;
      }

    } catch (e) {
      log('❌ فشل الحل البديل أيضاً: $e');
    }

    return false;
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