import 'dart:developer';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';

import '../../providers/game_provider.dart';
import '../../providers/game_state.dart';
import '../../services/realtime_manager.dart';
import '../../services/webrtc_services/webrtc_service.dart';
import '../../services/supabase_service.dart';

mixin GameScreenMixin {
  final Set<String> _processedSignals = {};
  StreamSubscription<Map<String, dynamic>>? _signalSubscription;
  Timer? _signalCleanupTimer;

// التعديل الثالث: في game_screen_mixin.dart - تحسين setupWebRTCCallbacks:

  void setupWebRTCCallbacks(
      WebRTCService webrtcService,
      SupabaseService supabaseService,
      String playerId,
      BuildContext gameContext,
      ) {
    log('🔧 بدء تعيين WebRTC callbacks المحسن للاعب: $playerId');

    // إلغاء الاستماع السابق بأمان
    try {
      _signalSubscription?.cancel();
      _signalSubscription = null;
    } catch (e) {
      log('⚠️ خطأ في إلغاء الاستماع السابق: $e');
    }

    // مسح الإشارات المعالجة السابقة
    _processedSignals.clear();

    webrtcService.setSignalingCallbacks(
      onIceCandidate: (peerId, candidate) async {
        await _handleOutgoingSignal('ice-candidate', peerId, {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        }, supabaseService, playerId, gameContext);
      },

      onOffer: (peerId, offer) async {
        await _handleOutgoingSignal('offer', peerId, {
          'sdp': offer.sdp,
          'type': offer.type,
        }, supabaseService, playerId, gameContext);
      },

      onAnswer: (peerId, answer) async {
        await _handleOutgoingSignal('answer', peerId, {
          'sdp': answer.sdp,
          'type': answer.type,
        }, supabaseService, playerId, gameContext);
      },
    );

    log('✅ تم تعيين WebRTC callbacks بنجاح');

    // بدء الاستماع المحسن مع تأخير قصير لضمان التسجيل
    Future.delayed(const Duration(milliseconds: 200), () {
      _startEnhancedSignalListening(webrtcService, supabaseService, playerId, gameContext);
    });

    // بدء مؤقت التنظيف
    _startSignalCleanupTimer();
  }

// دالة محسنة لمعالجة الإشارات الصادرة
  Future<void> _handleOutgoingSignal(
      String signalType,
      String peerId,
      Map<String, dynamic> data,
      SupabaseService supabaseService,
      String playerId,
      BuildContext gameContext,
      ) async {
    try {
      log('📤 إرسال إشارة $signalType إلى $peerId');

      final gameProvider = Provider.of<GameProvider>(gameContext, listen: false);
      final currentRoom = gameProvider.currentRoom;

      if (currentRoom == null) {
        log('❌ لا توجد غرفة حالية لإرسال الإشارة');
        return;
      }

      // محاولة الإرسال مع إعادة المحاولة
      bool success = false;
      int attempts = 0;
      const maxAttempts = 3;

      while (!success && attempts < maxAttempts) {
        attempts++;

        try {
          success = await supabaseService.sendSignal(
            roomId: currentRoom.id,
            fromPeer: playerId,
            toPeer: peerId,
            type: signalType,
            data: data,
          ).timeout(const Duration(seconds: 5));

          if (success) {
            log('✅ تم إرسال إشارة $signalType إلى $peerId (محاولة $attempts)');
          } else if (attempts < maxAttempts) {
            log('⚠️ فشل إرسال إشارة $signalType إلى $peerId (محاولة $attempts) - إعادة المحاولة');
            await Future.delayed(Duration(milliseconds: 500 * attempts));
          }
        } catch (e) {
          if (attempts < maxAttempts) {
            log('❌ خطأ في إرسال إشارة $signalType إلى $peerId (محاولة $attempts): $e - إعادة المحاولة');
            await Future.delayed(Duration(milliseconds: 500 * attempts));
          } else {
            log('❌ فشل نهائي في إرسال إشارة $signalType إلى $peerId بعد $maxAttempts محاولات: $e');
          }
        }
      }

      if (!success) {
        log('💥 فشل في إرسال إشارة $signalType إلى $peerId بعد جميع المحاولات');
      }

    } catch (e) {
      log('❌ خطأ عام في معالجة إشارة صادرة $signalType: $e');
    }
  }

// تحسين دالة _startEnhancedSignalListening
  void _startEnhancedSignalListening(
      WebRTCService webrtcService,
      SupabaseService supabaseService,
      String playerId,
      BuildContext gameContext,
      ) {
    log('🎧 بدء الاستماع المحسن للإشارات للاعب: $playerId');

    try {
      _signalSubscription = supabaseService.listenToSignalsWithFallback(playerId)
          .timeout(const Duration(seconds: 15))
          .listen(
            (signal) async {
          if (signal.isNotEmpty && _isValidSignal(signal)) {
            await _processIncomingSignal(
              signal,
              webrtcService,
              supabaseService,
              playerId,
              gameContext,
            );
          }
        },
        onError: (error) {
          log('❌ خطأ في stream الإشارات: $error');
          _handleSignalStreamError(error, webrtcService, supabaseService, playerId, gameContext);
        },
        onDone: () {
          log('📡 انتهى stream الإشارات - جدولة إعادة الاستماع');
          _scheduleSignalReconnect(webrtcService, supabaseService, playerId, gameContext);
        },
      );

      log('✅ تم بدء الاستماع للإشارات بنجاح');
    } catch (e) {
      log('❌ خطأ في بدء الاستماع للإشارات: $e');
      _scheduleSignalReconnect(webrtcService, supabaseService, playerId, gameContext);
    }
  }

// دالة للتحقق من صحة الإشارة
  bool _isValidSignal(Map<String, dynamic> signal) {
    return signal.containsKey('type') &&
        signal.containsKey('from_peer') &&
        signal.containsKey('data') &&
        signal['type'] != null &&
        signal['from_peer'] != null &&
        signal['data'] != null;
  }

// دالة محسنة لمعالجة الإشارات الواردة
  Future<void> _processIncomingSignal(
      Map<String, dynamic> signal,
      WebRTCService webrtcService,
      SupabaseService supabaseService,
      String playerId,
      BuildContext gameContext,
      ) async {
    final signalId = _generateSignalId(signal);

    // تجنب معالجة الإشارات المكررة
    if (_processedSignals.contains(signalId)) {
      return;
    }

    _processedSignals.add(signalId);

    final fromPeer = signal['from_peer'] as String;
    final type = signal['type'] as String;

    // تجنب الإشارات من نفس اللاعب
    if (fromPeer == playerId) {
      return;
    }

    log('📨 معالجة إشارة $type من $fromPeer');

    try {
      await _handleIncomingSignalRobust(
        signal,
        webrtcService,
        supabaseService,
        playerId,
        gameContext,
      );

      // تنظيف الإشارة بعد المعالجة الناجحة
      await _cleanupSignalSafely(supabaseService, signal['id'], playerId);

    } catch (e) {
      log('❌ خطأ في معالجة إشارة $type من $fromPeer: $e');
      // تنظيف الإشارة حتى في حالة الخطأ لمنع التكرار
      await _cleanupSignalSafely(supabaseService, signal['id'], playerId);
    }
  }

// دالة لتوليد معرف فريد للإشارة
  String _generateSignalId(Map<String, dynamic> signal) {
    final fromPeer = signal['from_peer'] ?? '';
    final type = signal['type'] ?? '';
    final timestamp = signal['created_at'] ?? DateTime.now().toIso8601String();
    return '$fromPeer-$type-${timestamp.hashCode}';
  }

// دالة لمعالجة أخطاء stream الإشارات
  void _handleSignalStreamError(
      dynamic error,
      WebRTCService webrtcService,
      SupabaseService supabaseService,
      String playerId,
      BuildContext gameContext,
      ) {
    log('🔄 معالجة خطأ stream الإشارات: $error');

    // جدولة إعادة الاتصال بعد تأخير متزايد
    _scheduleSignalReconnect(webrtcService, supabaseService, playerId, gameContext, delay: 3);
  }

// دالة لجدولة إعادة الاتصال
  void _scheduleSignalReconnect(
      WebRTCService webrtcService,
      SupabaseService supabaseService,
      String playerId,
      BuildContext gameContext, {
        int delay = 2,
      }) {
    Future.delayed(Duration(seconds: delay), () {
      if (_signalSubscription?.isPaused != false) {
        log('🔄 إعادة تأسيس الاستماع للإشارات بعد $delay ثانية');
        _startEnhancedSignalListening(webrtcService, supabaseService, playerId, gameContext);
      }
    });
  }

// تحسين دالة تنظيف الإشارات المعالجة
  void _cleanupProcessedSignals() {
    if (_processedSignals.length > 100) {
      final signalsToKeep = _processedSignals.toList().sublist(_processedSignals.length - 50);
      _processedSignals.clear();
      _processedSignals.addAll(signalsToKeep);
      log('🧹 تم تنظيف قائمة الإشارات المعالجة - الاحتفاظ بآخر 50 إشارة');
    }
  }

// الحل النهائي: استبدال دالة _handleIncomingSignalRobust في game_screen_mixin.dart

  Future<void> _handleIncomingSignalRobust(
      Map<String, dynamic> signal,
      WebRTCService webrtcService,
      SupabaseService supabaseService,
      String currentPlayerId,
      BuildContext gameContext,
      ) async {
    final fromPeer = signal['from_peer'] as String?;
    final type = signal['type'] as String?;
    final data = signal['data'] as Map<String, dynamic>?;
    final signalId = signal['id'];

    if (fromPeer == null || type == null || data == null) {
      log('⚠️ إشارة ناقصة، تجاهل: $signal');
      return;
    }

    if (fromPeer == currentPlayerId) {
      log('⚠️ تجاهل إشارة من نفس اللاعب');
      return;
    }

    try {
      log('🔧 معالجة إشارة $type من $fromPeer');

      switch (type) {
        case 'offer':
          await _handleOfferRobust(fromPeer, data, webrtcService, gameContext);
          break;

        case 'answer':
          await _handleAnswerRobust(fromPeer, data, webrtcService);
          break;

        case 'ice-candidate':
          await _handleIceCandidateRobust(fromPeer, data, webrtcService);
          break;

        default:
          log('⚠️ نوع إشارة غير معروف: $type');
      }

      // تنظيف الإشارة بعد المعالجة الناجحة
      await _cleanupSignalSafely(supabaseService, signalId, currentPlayerId);
      log('✅ تمت معالجة الإشارة $type من $fromPeer بنجاح');

    } catch (e) {
      log('❌ خطأ في معالجة الإشارة $type من $fromPeer: $e');
      // تنظيف الإشارة حتى لو فشلت المعالجة لتجنب التكرار
      await _cleanupSignalSafely(supabaseService, signalId, currentPlayerId);
    }
  }

// استبدال _handleOffer بـ _handleOfferRobust:
  Future<void> _handleOfferRobust(
      String fromPeer,
      Map<String, dynamic> data,
      WebRTCService webrtcService,
      BuildContext gameContext,
      ) async {
    log('📥 معالجة offer من $fromPeer');

    try {
      // 1. إنشاء أو إعادة تعيين peer connection
      if (webrtcService.hasPeer(fromPeer)) {
        log('🔄 إغلاق peer connection موجود مع $fromPeer');
        await webrtcService.closePeerConnection(fromPeer);
        await Future.delayed(const Duration(milliseconds: 300));
      }

      log('🔧 إنشاء peer connection جديد لـ $fromPeer');
      await webrtcService.createPeerConnectionForPeer(fromPeer);

      // 2. انتظار استقرار الاتصال
      await Future.delayed(const Duration(milliseconds: 500));

      // 3. تعيين remote description
      final offer = RTCSessionDescription(data['sdp'], data['type']);
      await webrtcService.setRemoteDescription(fromPeer, offer);
      log('✅ تم تعيين remote description للعرض من $fromPeer');

      // 4. انتظار قبل إنشاء الإجابة
      await Future.delayed(const Duration(milliseconds: 300));

      // 5. إنشاء وإرسال الإجابة
      await webrtcService.createAnswer(fromPeer);
      log('✅ تم إنشاء وإرسال answer لـ $fromPeer');

    } catch (e) {
      log('❌ خطأ في معالجة offer من $fromPeer: $e');

      // محاولة إعادة الاتصال
      try {
        await webrtcService.closePeerConnection(fromPeer);
        await Future.delayed(const Duration(milliseconds: 500));
        await webrtcService.createPeerConnectionForPeer(fromPeer);
      } catch (retryError) {
        log('❌ فشل في إعادة الاتصال: $retryError');
      }
    }
  }

// استبدال _handleAnswer بـ _handleAnswerRobust:
  Future<void> _handleAnswerRobust(
      String fromPeer,
      Map<String, dynamic> data,
      WebRTCService webrtcService,
      ) async {
    log('📥 معالجة answer من $fromPeer');

    try {
      if (!webrtcService.hasPeer(fromPeer)) {
        log('⚠️ لا يوجد peer connection لـ $fromPeer عند استلام answer - إنشاء جديد');
        await webrtcService.createPeerConnectionForPeer(fromPeer);
        await Future.delayed(const Duration(milliseconds: 300));
      }

      // تعيين remote description للإجابة
      final answer = RTCSessionDescription(data['sdp'], data['type']);
      await webrtcService.setRemoteDescription(fromPeer, answer);
      log('✅ تم تعيين remote description للإجابة من $fromPeer');

      // انتظار استقرار الاتصال
      await Future.delayed(const Duration(milliseconds: 500));

      // التحقق من حالة الاتصال
      final isHealthy = await webrtcService.isPeerConnectionHealthy(fromPeer);
      log('🔍 حالة الاتصال مع $fromPeer بعد answer: $isHealthy');

      if (!isHealthy) {
        log('⚠️ الاتصال مع $fromPeer لا يزال غير صحي بعد answer');
      }

    } catch (e) {
      log('❌ خطأ في معالجة answer من $fromPeer: $e');
    }
  }

// استبدال _handleIceCandidate بـ _handleIceCandidateRobust:
  Future<void> _handleIceCandidateRobust(
      String fromPeer,
      Map<String, dynamic> data,
      WebRTCService webrtcService,
      ) async {
    final candidateStr = data['candidate'] as String?;

    if (candidateStr == null || candidateStr.isEmpty) {
      log('⚠️ ICE candidate فارغ من $fromPeer');
      return;
    }

    log('🧊 معالجة ICE candidate من $fromPeer');

    try {
      // إنشاء peer connection إذا لم يكن موجوداً
      if (!webrtcService.hasPeer(fromPeer)) {
        log('⚠️ لا يوجد peer connection لـ $fromPeer، إنشاء مؤقت');
        await webrtcService.createPeerConnectionForPeer(fromPeer);
        await Future.delayed(const Duration(milliseconds: 200));
      }

      final candidate = RTCIceCandidate(
        candidateStr,
        data['sdpMid'],
        data['sdpMLineIndex'],
      );

      await webrtcService.addIceCandidate(fromPeer, candidate);
      log('✅ تم إضافة ICE candidate من $fromPeer');

    } catch (e) {
      log('❌ فشل في إضافة ICE candidate من $fromPeer: $e');
    }
  }

// إضافة دالة مراقبة حالة الإشارات:
  void _monitorSignalHealth() {
    Timer.periodic(const Duration(seconds: 10), (timer) {
      try {
        if (_signalSubscription != null) {
          if (_signalSubscription!.isPaused) {
            log('⚠️ stream الإشارات متوقف، إعادة التشغيل');
            _signalSubscription?.cancel();
            _signalSubscription = null;

            // إعادة تشغيل الاستماع
            // يجب استدعاء setupWebRTCCallbacks مرة أخرى
          }
        }
      } catch (e) {
        log('❌ خطأ في مراقبة صحة الإشارات: $e');
      }
    });
  }

  Future<void> _handleOffer(
      String fromPeer,
      Map<String, dynamic> data,
      WebRTCService webrtcService,
      BuildContext gameContext,
      ) async {

    log('📥 معالجة offer من $fromPeer');

    // إنشاء peer connection إذا لم يكن موجوداً
    if (!webrtcService.hasPeer(fromPeer)) {
      log('🔧 إنشاء peer connection جديد لـ $fromPeer');
      await webrtcService.createPeerConnectionForPeer(fromPeer);

      // انتظار قصير للتأكد من إنشاء الاتصال
      await Future.delayed(const Duration(milliseconds: 300));
    }

    // تعيين remote description
    final offer = RTCSessionDescription(data['sdp'], data['type']);
    await webrtcService.setRemoteDescription(fromPeer, offer);
    log('✅ تم تعيين remote description للعرض من $fromPeer');

    // انتظار قصير قبل إنشاء الإجابة
    await Future.delayed(const Duration(milliseconds: 200));

    // إنشاء وإرسال الإجابة
    await webrtcService.createAnswer(fromPeer);
    log('✅ تم إنشاء وإرسال answer لـ $fromPeer');
  }

  Future<void> _handleAnswer(
      String fromPeer,
      Map<String, dynamic> data,
      WebRTCService webrtcService,
      ) async {

    log('📥 معالجة answer من $fromPeer');

    if (!webrtcService.hasPeer(fromPeer)) {
      log('⚠️ لا يوجد peer connection لـ $fromPeer عند استلام answer');
      return;
    }

    // تعيين remote description
    final answer = RTCSessionDescription(data['sdp'], data['type']);
    await webrtcService.setRemoteDescription(fromPeer, answer);
    log('✅ تم تعيين remote description للإجابة من $fromPeer');
  }

  Future<void> _handleIceCandidate(
      String fromPeer,
      Map<String, dynamic> data,
      WebRTCService webrtcService,
      ) async {

    final candidateStr = data['candidate'] as String?;

    if (candidateStr == null || candidateStr.isEmpty) {
      log('⚠️ ICE candidate فارغ من $fromPeer');
      return;
    }

    log('🧊 معالجة ICE candidate من $fromPeer');

    if (!webrtcService.hasPeer(fromPeer)) {
      log('⚠️ لا يوجد peer connection لـ $fromPeer، تأجيل ICE candidate');
      // يمكن إضافة منطق تأجيل هنا إذا لزم الأمر
      return;
    }

    try {
      final candidate = RTCIceCandidate(
        candidateStr,
        data['sdpMid'],
        data['sdpMLineIndex'],
      );

      await webrtcService.addIceCandidate(fromPeer, candidate);
      log('✅ تم إضافة ICE candidate من $fromPeer');

    } catch (e) {
      log('❌ فشل في إضافة ICE candidate من $fromPeer: $e');
    }
  }

  Future<void> _cleanupSignalSafely(
      SupabaseService supabaseService,
      dynamic signalId,
      String playerId,
      ) async {
    try {
      if (signalId != null) {
        await supabaseService.deleteSignalSafe(signalId, playerId);
      }
    } catch (e) {
      log('⚠️ خطأ في تنظيف الإشارة: $e');
    }
  }

// وفي دالة _startSignalCleanupTimer، استبدل:
  void _startSignalCleanupTimer() {
    _signalCleanupTimer?.cancel();
    _signalCleanupTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      // تنظيف دوري للإشارات القديمة
      try {
        // استخدام context محفوظ بدلاً من NavigationService
        final context = NavigationService.currentContext;
        if (context != null) {
          final gameProvider = Provider.of<GameProvider>(context, listen: false);
          if (gameProvider.currentRoom != null) {
            final supabaseService = SupabaseService();
            supabaseService.cleanupOldSignals(gameProvider.currentRoom!.id);
          }
        }
      } catch (e) {
        log('خطأ في تنظيف الإشارات: $e');
      }
    });
  }

  // الباقي من الدوال كما هي...
  void checkConnectionAndRefresh(RealtimeManager realtimeManager, String playerId, BuildContext context) {
    try {
      final gameProvider = Provider.of<GameProvider>(context, listen: false);
      if (gameProvider.currentRoom != null) {
        gameProvider.updateConnectionStatus(playerId, true);
        realtimeManager.forceRefresh();
      }
    } catch (e) {
      log('خطأ في checkConnectionAndRefresh: $e');
    }
  }

  void showLeaveGameDialog(BuildContext context, SupabaseService supabaseService, String playerId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('مغادرة اللعبة'),
        content: const Text('هل تريد مغادرة اللعبة؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              await supabaseService.leaveRoom(playerId);
              context.read<GameProvider>().leaveRoom();
              Navigator.popUntil(context, (route) => route.isFirst);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('مغادرة', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  String getStatusText(GameState state) {
    switch (state) {
      case GameState.waiting:
        return 'في انتظار اللاعبين';
      case GameState.playing:
        return 'اللعبة جارية';
      case GameState.voting:
        return 'وقت التصويت';
      case GameState.continueVoting:
        return 'التصويت على الإكمال';
      case GameState.finished:
        return 'انتهت اللعبة';
    }
  }

  // تنظيف الموارد
  void disposeMixin() {
    _signalSubscription?.cancel();
    _signalCleanupTimer?.cancel();
    _processedSignals.clear();
  }
}

// في نهاية الكلاس NavigationService، أضف:
class NavigationService {
  static GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  // إضافة هذا الجزء المفقود:
  static BuildContext? get currentContext => navigatorKey.currentContext;
}