import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';

import '../../providers/game_provider.dart';
import '../../services/realtime_manager.dart';
import '../../services/webrtc_service.dart';
import '../../services/supabase_service.dart';

mixin GameScreenMixin {

  void setupWebRTCCallbacks(
      WebRTCService webrtcService,
      SupabaseService supabaseService,
      String playerId
      ) {
    webrtcService.setSignalingCallbacks(
      onIceCandidate: (peerId, candidate) async {
        final gameProvider = Provider.of<GameProvider>(
            navigatorKey.currentContext!,
            listen: false
        );
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
        }
      },
      onOffer: (peerId, offer) async {
        final gameProvider = Provider.of<GameProvider>(
            navigatorKey.currentContext!,
            listen: false
        );
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
      },
      onAnswer: (peerId, answer) async {
        final gameProvider = Provider.of<GameProvider>(
            navigatorKey.currentContext!,
            listen: false
        );
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
      },
    );

    // الاستماع للإشارات الواردة
    supabaseService.listenToSignals(playerId).listen((signal) {
      if (signal.isNotEmpty) {
        handleIncomingSignal(signal, webrtcService, supabaseService);
      }
    });
  }

  Future<void> handleIncomingSignal(
      Map<String, dynamic> signal,
      WebRTCService webrtcService,
      SupabaseService supabaseService
      ) async {
    try {
      final fromPeer = signal['from_peer'] as String;
      final type = signal['type'] as String;
      final data = signal['data'] as Map<String, dynamic>;

      switch (type) {
        case 'offer':
          await webrtcService.createPeerConnectionForPeer(fromPeer);
          await webrtcService.setRemoteDescription(
            fromPeer,
            RTCSessionDescription(data['sdp'], data['type']),
          );
          await webrtcService.createAnswer(fromPeer);
          break;

        case 'answer':
          await webrtcService.setRemoteDescription(
            fromPeer,
            RTCSessionDescription(data['sdp'], data['type']),
          );
          break;

        case 'ice-candidate':
          final candidate = RTCIceCandidate(
            data['candidate'],
            data['sdpMid'],
            data['sdpMLineIndex'],
          );
          await webrtcService.addIceCandidate(fromPeer, candidate);
          break;
      }

      // حذف الإشارة بعد المعالجة
      if (signal['id'] != null) {
        await supabaseService.deleteSignal(signal['id']);
      }
    } catch (e) {
      log('خطأ في معالجة الإشارة: $e');
    }
  }

  void checkConnectionAndRefresh(RealtimeManager realtimeManager, String playerId) {
    final gameProvider = Provider.of<GameProvider>(
        navigatorKey.currentContext!,
        listen: false
    );
    if (gameProvider.currentRoom != null) {
      gameProvider.updateConnectionStatus(playerId, true);
      realtimeManager.forceRefresh();
    }
  }

  void showLeaveGameDialog(
      BuildContext context,
      SupabaseService supabaseService,
      String playerId
      ) {
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
      case GameState.finished:
        return 'انتهت اللعبة';
    }
  }
}

// Global navigator key للوصول للـ context من خارج الـ widget
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();