import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';

import '../../providers/game_provider.dart';
import '../../services/realtime_manager.dart';
import '../../services/webrtc_services/webrtc_service.dart';
import '../../services/supabase_service.dart';

mixin GameScreenMixin {
  final Set<int> _processedSignals = {};

  void setupWebRTCCallbacks(
      WebRTCService webrtcService,
      SupabaseService supabaseService,
      String playerId,
      BuildContext gameContext,
      ) {
    webrtcService.setSignalingCallbacks(
      onIceCandidate: (peerId, candidate) async {
        try {
          final gameProvider = Provider.of<GameProvider>(gameContext, listen: false);
          if (gameProvider.currentRoom != null) {
            // استخدام الدالة المحسنة التي ترجع bool
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

            if (!success) {
              log('⚠️ فشل إرسال ICE candidate - إعادة المحاولة بعد ثانية');
              Future.delayed(const Duration(seconds: 1), () async {
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
          log('✗ خطأ في إرسال ICE candidate: $e');
        }
      },
      onOffer: (peerId, offer) async {
        try {
          final gameProvider = Provider.of<GameProvider>(gameContext, listen: false);
          if (gameProvider.currentRoom != null) {
            await supabaseService.sendSignal(
              roomId: gameProvider.currentRoom!.id,
              fromPeer: playerId,
              toPeer: peerId,
              type: 'offer',
              data: {
                'sdp': offer.sdp,
                'type': offer.type,
              },
            );
          }
        } catch (e) {
          log('✗ خطأ في إرسال العرض: $e');
        }
      },
      onAnswer: (peerId, answer) async {
        try {
          final gameProvider = Provider.of<GameProvider>(gameContext, listen: false);
          if (gameProvider.currentRoom != null) {
            await supabaseService.sendSignal(
              roomId: gameProvider.currentRoom!.id,
              fromPeer: playerId,
              toPeer: peerId,
              type: 'answer',
              data: {
                'sdp': answer.sdp,
                'type': answer.type,
              },
            );
          }
        } catch (e) {
          log('✗ خطأ في إرسال الإجابة: $e');
        }
      },
    );

    // استخدام الدالة المحسنة للاستماع
    supabaseService.listenToSignalsWithFallback(playerId).listen(
          (signal) {
        if (signal.isNotEmpty && signal['type'] != null) {
          final signalId = signal['id'];

          // معالجة الإشارة بغض النظر عن نوع المعرف
          if (signalId != null && !_processedSignals.contains(signalId)) {
            _processedSignals.add(signalId);
            handleIncomingSignalEnhanced(signal, webrtcService, supabaseService, playerId);

            if (_processedSignals.length > 100) {
              _processedSignals.clear();
            }
          }
        }
      },
      onError: (error) {
        log('❌ خطأ في الاستماع للإشارات: $error');
        // إعادة تأسيس الاستماع بعد تأخير
        Future.delayed(const Duration(seconds: 3), () {
          setupWebRTCCallbacks(webrtcService, supabaseService, playerId, gameContext);
        });
      },
    );
  }

// نسخة محسنة من handleIncomingSignal
  Future<void> handleIncomingSignalEnhanced(
      Map<String, dynamic> signal,
      WebRTCService webrtcService,
      SupabaseService supabaseService,
      String currentPlayerId,
      ) async {
    try {
      final fromPeer = signal['from_peer'] as String;
      final type = signal['type'] as String;
      final data = signal['data'] as Map<String, dynamic>;
      final signalId = signal['id'];

      log('📨 معالجة إشارة $type من $fromPeer');

      switch (type) {
        case 'offer':
        // إنشاء peer connection إذا لم يكن موجوداً
          if (!webrtcService.hasPeer(fromPeer)) {
            await webrtcService.createPeerConnectionForPeer(fromPeer);
            log('✅ تم إنشاء peer connection جديد لـ $fromPeer');
          }

          // تعيين remote description
          await webrtcService.setRemoteDescription(
            fromPeer,
            RTCSessionDescription(data['sdp'], data['type']),
          );

          // إنشاء إجابة
          await webrtcService.createAnswer(fromPeer);
          log('✅ تمت معالجة العرض وإرسال الإجابة لـ $fromPeer');
          break;

        case 'answer':
          if (webrtcService.hasPeer(fromPeer)) {
            await webrtcService.setRemoteDescription(
              fromPeer,
              RTCSessionDescription(data['sdp'], data['type']),
            );
            log('✅ تم تعيين الإجابة من $fromPeer');
          } else {
            log('⚠️ لا يوجد peer connection لـ $fromPeer عند استقبال answer');
          }
          break;

        case 'ice-candidate':
          if (data['candidate'] != null &&
              data['candidate'].toString().isNotEmpty &&
              webrtcService.hasPeer(fromPeer)) {

            final candidate = RTCIceCandidate(
              data['candidate'],
              data['sdpMid'],
              data['sdpMLineIndex'],
            );
            await webrtcService.addIceCandidate(fromPeer, candidate);
            log('✅ تم إضافة ICE candidate من $fromPeer');
          } else {
            log('⚠️ ICE candidate غير صالح أو لا يوجد peer connection');
          }
          break;

        default:
          log('⚠ نوع إشارة غير معروف: $type');
      }

      // تنظيف الإشارة بعد المعالجة الناجحة
      await supabaseService.deleteSignalSafe(signalId, currentPlayerId);

    } catch (e) {
      log('✗ خطأ في معالجة الإشارة: $e');

      // تنظيف الإشارة حتى لو فشلت المعالجة لتجنب التكرار
      try {
        await supabaseService.deleteSignalSafe(signal['id'], currentPlayerId);
      } catch (deleteError) {
        log('خطأ في تنظيف الإشارة: $deleteError');
      }
    }
  }

// تحديث handleIncomingSignal لمعالجة الحل البديل
  Future<void> handleIncomingSignal(
      Map<String, dynamic> signal,
      WebRTCService webrtcService,
      SupabaseService supabaseService,
      ) async {
    try {
      final fromPeer = signal['from_peer'] as String;
      final type = signal['type'] as String;
      final data = signal['data'] as Map<String, dynamic>;
      final signalId = signal['id'];

      log('📨 معالجة إشارة $type من $fromPeer');

      switch (type) {
        case 'offer':
          if (!webrtcService.hasPeer(fromPeer)) {
            await webrtcService.createPeerConnectionForPeer(fromPeer);
            log('تم إنشاء peer connection جديد لـ $fromPeer');
          }

          await webrtcService.setRemoteDescription(
            fromPeer,
            RTCSessionDescription(data['sdp'], data['type']),
          );

          await webrtcService.createAnswer(fromPeer);
          log('✓ تمت معالجة العرض وإرسال الإجابة لـ $fromPeer');
          break;

        case 'answer':
          await webrtcService.setRemoteDescription(
            fromPeer,
            RTCSessionDescription(data['sdp'], data['type']),
          );
          log('✓ تم تعيين الإجابة من $fromPeer');
          break;

        case 'ice-candidate':
          if (data['candidate'] != null && data['candidate'].toString().isNotEmpty) {
            final candidate = RTCIceCandidate(
              data['candidate'],
              data['sdpMid'],
              data['sdpMLineIndex'],
            );
            await webrtcService.addIceCandidate(fromPeer, candidate);
            log('✓ تم إضافة ICE candidate من $fromPeer');
          }
          break;

        default:
          log('⚠ نوع إشارة غير معروف: $type');
      }

      // تنظيف الإشارة بعد المعالجة
      if (signalId != null) {
        if (signalId is int) {
          // إشارة من الجدول الأصلي
          await supabaseService.deleteSignal(signalId);
        } else {
          // إشارة من الحل البديل - تنظيف custom_data
          await supabaseService.clearReceivedSignal(signal['to_peer']);
        }
        log('🗑️ تم تنظيف الإشارة');
      }

    } catch (e) {
      log('✗ خطأ في معالجة الإشارة: $e');

      // تنظيف الإشارة حتى لو فشلت المعالجة
      final signalId = signal['id'];
      if (signalId != null) {
        try {
          if (signalId is int) {
            await supabaseService.deleteSignal(signalId);
          } else {
            await supabaseService.clearReceivedSignal(signal['to_peer']);
          }
        } catch (deleteError) {
          log('خطأ في تنظيف الإشارة: $deleteError');
        }
      }
    }
  }

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
}
