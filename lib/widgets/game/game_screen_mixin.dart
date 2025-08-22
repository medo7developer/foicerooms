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

  void setupWebRTCCallbacks(
      WebRTCService webrtcService,
      SupabaseService supabaseService,
      String playerId,
      BuildContext gameContext,
      ) {

    // إلغاء الاستماع السابق إذا كان موجوداً
    _signalSubscription?.cancel();

    webrtcService.setSignalingCallbacks(
      onIceCandidate: (peerId, candidate) async {
        try {
          final gameProvider = Provider.of<GameProvider>(gameContext, listen: false);
          if (gameProvider.currentRoom != null) {
            log('🧊 إرسال ICE candidate إلى $peerId');

            final success = await supabaseService.sendSignal(
              roomId: gameProvider.currentRoom!.id,
              fromPeer: playerId,
              toPeer: peerId,
              type: 'ice-candidate',
              data: {
                'candidate': candidate.candidate,
                'sdpMid': candidate.sdpMid,
                'sdpMLineIndex': candidate.sdpMLineIndex,
              },
            );

            if (success) {
              log('✅ تم إرسال ICE candidate بنجاح إلى $peerId');
            } else {
              log('❌ فشل إرسال ICE candidate إلى $peerId');
              // إعادة المحاولة بعد تأخير قصير
              Future.delayed(const Duration(milliseconds: 500), () async {
                await supabaseService.sendSignal(
                  roomId: gameProvider.currentRoom!.id,
                  fromPeer: playerId,
                  toPeer: peerId,
                  type: 'ice-candidate',
                  data: {
                    'candidate': candidate.candidate,
                    'sdpMid': candidate.sdpMid,
                    'sdpMLineIndex': candidate.sdpMLineIndex,
                  },
                );
              });
            }
          }
        } catch (e) {
          log('❌ خطأ في إرسال ICE candidate: $e');
        }
      },

      onOffer: (peerId, offer) async {
        try {
          final gameProvider = Provider.of<GameProvider>(gameContext, listen: false);
          if (gameProvider.currentRoom != null) {
            log('📤 إرسال offer إلى $peerId');

            final success = await supabaseService.sendSignal(
              roomId: gameProvider.currentRoom!.id,
              fromPeer: playerId,
              toPeer: peerId,
              type: 'offer',
              data: {
                'sdp': offer.sdp,
                'type': offer.type,
              },
            );

            if (success) {
              log('✅ تم إرسال offer بنجاح إلى $peerId');
            } else {
              log('❌ فشل إرسال offer إلى $peerId');
            }
          }
        } catch (e) {
          log('❌ خطأ في إرسال العرض: $e');
        }
      },

      onAnswer: (peerId, answer) async {
        try {
          final gameProvider = Provider.of<GameProvider>(gameContext, listen: false);
          if (gameProvider.currentRoom != null) {
            log('📤 إرسال answer إلى $peerId');

            final success = await supabaseService.sendSignal(
              roomId: gameProvider.currentRoom!.id,
              fromPeer: playerId,
              toPeer: peerId,
              type: 'answer',
              data: {
                'sdp': answer.sdp,
                'type': answer.type,
              },
            );

            if (success) {
              log('✅ تم إرسال answer بنجاح إلى $peerId');
            } else {
              log('❌ فشل إرسال answer إلى $peerId');
            }
          }
        } catch (e) {
          log('❌ خطأ في إرسال الإجابة: $e');
        }
      },
    );

    // بدء الاستماع المحسن للإشارات
    _startEnhancedSignalListening(webrtcService, supabaseService, playerId, gameContext);

    // بدء مؤقت التنظيف
    _startSignalCleanupTimer();
  }

  void _startEnhancedSignalListening(
      WebRTCService webrtcService,
      SupabaseService supabaseService,
      String playerId,
      BuildContext gameContext,
      ) {

    log('🎧 بدء الاستماع المحسن للإشارات للاعب: $playerId');

    _signalSubscription = supabaseService.listenToSignalsWithFallback(playerId)
        .timeout(const Duration(seconds: 10))
        .listen(
          (signal) async {
        if (signal.isNotEmpty && signal['type'] != null && signal['from_peer'] != null) {
          final signalId = '${signal['from_peer']}_${signal['type']}_${DateTime.now().millisecondsSinceEpoch}';

          // تجنب معالجة الإشارات المكررة
          if (!_processedSignals.contains(signalId)) {
            _processedSignals.add(signalId);

            log('📨 استلام إشارة جديدة: ${signal['type']} من ${signal['from_peer']}');

            await _handleIncomingSignalRobust(
              signal,
              webrtcService,
              supabaseService,
              playerId,
              gameContext,
            );

            // تنظيف قائمة الإشارات المعالجة إذا أصبحت كبيرة
            if (_processedSignals.length > 50) {
              _processedSignals.clear();
              log('🧹 تم تنظيف قائمة الإشارات المعالجة');
            }
          }
        }
      },
      onError: (error) {
        log('❌ خطأ في الاستماع للإشارات: $error');
        // إعادة تأسيس الاستماع بعد تأخير
        Future.delayed(const Duration(seconds: 3), () {
          if (_signalSubscription?.isPaused != false) {
            log('🔄 إعادة تأسيس الاستماع للإشارات...');
            _startEnhancedSignalListening(webrtcService, supabaseService, playerId, gameContext);
          }
        });
      },
      onDone: () {
        log('📡 انتهى stream الإشارات - إعادة تأسيس...');
        Future.delayed(const Duration(seconds: 2), () {
          _startEnhancedSignalListening(webrtcService, supabaseService, playerId, gameContext);
        });
      },
    );
  }

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
          await _handleOffer(fromPeer, data, webrtcService, gameContext);
          break;

        case 'answer':
          await _handleAnswer(fromPeer, data, webrtcService);
          break;

        case 'ice-candidate':
          await _handleIceCandidate(fromPeer, data, webrtcService);
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