import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';

import '../../providers/game_provider.dart';
import '../../services/realtime_manager.dart';
import '../../services/webrtc_service.dart';
import '../../services/supabase_service.dart';

mixin GameScreenMixin {
  final Set<int> _processedSignals = {};

  void setupWebRTCCallbacks(
      WebRTCService webrtcService,
      SupabaseService supabaseService,
      String playerId,
      BuildContext gameContext, // إضافة context كمعامل
      ) {
    webrtcService.setSignalingCallbacks(
      onIceCandidate: (peerId, candidate) async {
        try {
          final gameProvider = Provider.of<GameProvider>(gameContext, listen: false);
          if (gameProvider.currentRoom != null) {
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
            log('✓ تم إرسال ICE candidate إلى $peerId');
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
            log('✓ تم إرسال العرض إلى $peerId');
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
            log('✓ تم إرسال الإجابة إلى $peerId');
          }
        } catch (e) {
          log('✗ خطأ في إرسال الإجابة: $e');
        }
      },
    );

    // تحسين الاستماع للإشارات الواردة
    supabaseService.listenToSignals(playerId).listen((signal) {
      if (signal.isNotEmpty && signal['id'] != null) {
        final signalId = signal['id'] as int;

        if (!_processedSignals.contains(signalId)) {
          _processedSignals.add(signalId);
          handleIncomingSignal(signal, webrtcService, supabaseService);

          if (_processedSignals.length > 100) {
            _processedSignals.clear();
          }
        }
      }
    });
  }

  Future<void> handleIncomingSignal(
      Map<String, dynamic> signal,
      WebRTCService webrtcService,
      SupabaseService supabaseService,
      ) async {
    try {
      final fromPeer = signal['from_peer'] as String;
      final type = signal['type'] as String;
      final data = signal['data'] as Map<String, dynamic>;
      final signalId = signal['id'] as int?;

      log('📨 معالجة إشارة $type من $fromPeer');

      switch (type) {
        case 'offer':
        // إنشاء peer connection إذا لم يكن موجوداً
          if (!webrtcService.hasPeer(fromPeer)) {
            await webrtcService.createPeerConnectionForPeer(fromPeer);
            log('تم إنشاء peer connection جديد لـ $fromPeer');
          }

          await webrtcService.setRemoteDescription(
            fromPeer,
            RTCSessionDescription(data['sdp'], data['type']),
          );

          // إنشاء إجابة
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

      // حذف الإشارة بعد المعالجة
      if (signalId != null) {
        await supabaseService.deleteSignal(signalId);
        log('🗑️ تم حذف الإشارة $signalId');
      }
    } catch (e) {
      log('✗ خطأ في معالجة الإشارة: $e');

      // حذف الإشارة حتى لو فشلت المعالجة
      final signalId = signal['id'] as int?;
      if (signalId != null) {
        try {
          await supabaseService.deleteSignal(signalId);
        } catch (deleteError) {
          log('خطأ في حذف الإشارة: $deleteError');
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
