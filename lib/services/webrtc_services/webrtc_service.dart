import 'dart:async';
import 'dart:developer';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:voice_rooms_app/services/webrtc_services/webrtc_audio_manager.dart';
import 'package:voice_rooms_app/services/webrtc_services/webrtc_connection_manager.dart';
import 'package:voice_rooms_app/services/webrtc_services/webrtc_diagnostics.dart';
import 'package:voice_rooms_app/services/webrtc_services/webrtc_signaling_callbacks.dart';

class WebRTCService {
  MediaStream? _localStream;
  final Map<String, RTCPeerConnection> _peers = {};
  final Map<String, MediaStream> _remoteStreams = {};
  final Map<String, List<RTCIceCandidate>> _pendingCandidates = {};

  late final WebRTCConnectionManager _connectionManager;
  late final WebRTCAudioManager _audioManager;
  late final WebRTCDiagnostics _diagnostics;
  late final WebRTCSignalingCallbacks _signalingCallbacks;
  // إضافة متغيرات للتحكم في التسلسل
  final Map<String, bool> _connectionInProgress = {};
  final Map<String, DateTime> _lastConnectionAttempt = {};

  WebRTCService() {
    _connectionManager = WebRTCConnectionManager(
      peers: _peers,
      remoteStreams: _remoteStreams,
      pendingCandidates: _pendingCandidates,
      getLocalStream: () => _localStream,
    );

    _audioManager = WebRTCAudioManager(
      peers: _peers,
      remoteStreams: _remoteStreams,
      getLocalStream: () => _localStream,
      setLocalStream: (stream) => _localStream = stream,
    );

    _diagnostics = WebRTCDiagnostics(
      peers: _peers,
      remoteStreams: _remoteStreams,
      getLocalStream: () => _localStream,
    );

    _signalingCallbacks = WebRTCSignalingCallbacks();
  }

  // Getters
  MediaStream? get localStream => _localStream;
  Map<String, MediaStream> get remoteStreams => _remoteStreams;
  bool get isMicrophoneEnabled => _audioManager.isMicrophoneEnabled;

  // Delegation methods
  bool hasPeer(String peerId) => _peers.containsKey(peerId);
  MediaStream? getRemoteStream(String peerId) => _remoteStreams[peerId];
  bool isPeerHealthy(String peerId) => _diagnostics.isPeerHealthy(peerId);

  // Audio methods
  Future<bool> requestPermissions() => _audioManager.requestPermissions();
  Future<void> initializeLocalAudio() => _audioManager.initializeLocalAudio();
  Future<void> toggleMicrophone() => _audioManager.toggleMicrophone();
  void enableRemoteAudio() => _audioManager.enableRemoteAudio();
  void checkAudioTracks() => _audioManager.checkAudioTracks();

  Future<void> connectToAllPeers(List<String> peerIds, String myId) {
    return _connectionManager.connectToAllPeers(peerIds, myId);
  }

  Future<RTCSessionDescription> createOffer(String peerId) {
    return _connectionManager.createOffer(peerId, _signalingCallbacks);
  }

  Future<RTCSessionDescription> createAnswer(String peerId) {
    return _connectionManager.createAnswer(peerId, _signalingCallbacks);
  }

  Future<void> setRemoteDescription(String peerId, RTCSessionDescription description) {
    return _connectionManager.setRemoteDescription(peerId, description);
  }

  Future<void> addIceCandidate(String peerId, RTCIceCandidate candidate) {
    return _connectionManager.addIceCandidate(peerId, candidate);
  }

  Future<void> closePeerConnection(String peerId) {
    return _connectionManager.closePeerConnection(peerId);
  }

  // Diagnostics methods
  Future<void> debugConnectionStates() => _diagnostics.debugConnectionStates();
  Future<void> diagnoseAndFixAudio() => _diagnostics.diagnoseAndFixAudio();
  void startConnectionHealthCheck() => _diagnostics.startConnectionHealthCheck();
  Future<void> restartFailedConnections() => _diagnostics.restartFailedConnections();
  Future<void> verifyAudioInAllConnections() => _diagnostics.verifyAudioInAllConnections();

  // Legacy methods (for backward compatibility)
  Future<void> recreateFailedConnections() => restartFailedConnections();
  Future<void> ensureAudioPlayback() => _audioManager.ensureAudioPlayback();
  Future<void> refreshAudioConnections() => _audioManager.refreshAudioConnections();

  // Signaling callbacks
  void setSignalingCallbacks({
    Function(String, RTCIceCandidate)? onIceCandidate,
    Function(String, RTCSessionDescription)? onOffer,
    Function(String, RTCSessionDescription)? onAnswer,
  }) {
    _signalingCallbacks.setCallbacks(
      onIceCandidate: onIceCandidate,
      onOffer: onOffer,
      onAnswer: onAnswer,
    );
  }

  // إضافة دالة للتحقق من صحة الاتصال
  Future<bool> isPeerConnectionHealthy(String peerId) async {
    final pc = _peers[peerId];
    if (pc == null) return false;

    try {
      final connectionState = await pc.getConnectionState();
      final iceState = await pc.getIceConnectionState();
      final signalingState = await pc.getSignalingState();

      final isHealthy = connectionState == RTCPeerConnectionState.RTCPeerConnectionStateConnected ||
          iceState == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          iceState == RTCIceConnectionState.RTCIceConnectionStateCompleted;

      log('🔍 صحة الاتصال مع $peerId:');
      log('   Connection: $connectionState');
      log('   ICE: $iceState');
      log('   Signaling: $signalingState');
      log('   صحي: $isHealthy');

      return isHealthy;
    } catch (e) {
      log('❌ خطأ في فحص صحة الاتصال مع $peerId: $e');
      return false;
    }
  }

  // دالة محسنة لإنشاء peer connection مع حماية من التكرار
  @override
  Future<RTCPeerConnection> createPeerConnectionForPeer(String peerId) async {
    // التحقق من وجود اتصال في التقدم
    if (_connectionInProgress[peerId] == true) {
      log('⚠️ اتصال مع $peerId قيد التنفيذ، انتظار...');

      // انتظار انتهاء المحاولة الحالية
      while (_connectionInProgress[peerId] == true) {
        await Future.delayed(const Duration(milliseconds: 200));
      }

      // إرجاع الاتصال إذا تم إنشاؤه
      if (_peers.containsKey(peerId)) {
        return _peers[peerId]!;
      }
    }

    // التحقق من آخر محاولة اتصال
    final lastAttempt = _lastConnectionAttempt[peerId];
    if (lastAttempt != null) {
      final timeDiff = DateTime.now().difference(lastAttempt).inSeconds;
      if (timeDiff < 5) {
        log('⚠️ محاولة اتصال مع $peerId قريبة جداً، انتظار...');
        await Future.delayed(Duration(seconds: 5 - timeDiff));
      }
    }

    _connectionInProgress[peerId] = true;
    _lastConnectionAttempt[peerId] = DateTime.now();

    try {
      // إغلاق الاتصال القديم إن وجد
      await _safeClosePeerConnection(peerId);

      log('🔧 إنشاء peer connection جديد لـ $peerId');
      final pc = await _connectionManager.createPeerConnectionForPeer(
        peerId,
        _signalingCallbacks,
      );

      _peers[peerId] = pc;
      log('✅ تم إنشاء peer connection لـ $peerId بنجاح');

      return pc;

    } catch (e) {
      log('❌ خطأ في إنشاء peer connection لـ $peerId: $e');
      rethrow;
    } finally {
      _connectionInProgress[peerId] = false;
    }
  }

  // دالة لإغلاق الاتصال بأمان
  Future<void> _safeClosePeerConnection(String peerId) async {
    try {
      final oldPc = _peers[peerId];
      if (oldPc != null) {
        log('🗑️ إغلاق peer connection قديم لـ $peerId');
        await oldPc.close();
        _peers.remove(peerId);
        _remoteStreams.remove(peerId);
        _pendingCandidates.remove(peerId);
      }
    } catch (e) {
      log('⚠️ خطأ في إغلاق peer connection قديم لـ $peerId: $e');
    }
  }

  // دالة محسنة للتشخيص الشامل
  Future<void> performComprehensiveDiagnosis() async {
    try {
      log('🔍 === بدء التشخيص الشامل ===');

      // فحص المجرى المحلي
      if (_localStream == null) {
        log('❌ لا يوجد مجرى صوتي محلي!');
        await _audioManager.initializeLocalAudio();
      } else {
        final audioTracks = _localStream!.getAudioTracks();
        log('🎤 مسارات صوتية محلية: ${audioTracks.length}');

        for (final track in audioTracks) {
          if (!track.enabled) {
            track.enabled = true;
            log('🔧 تم تفعيل مسار محلي: ${track.id}');
          }
        }
      }

      // فحص كل peer connection
      final peersToCheck = List<String>.from(_peers.keys);

      for (final peerId in peersToCheck) {
        final isHealthy = await isPeerConnectionHealthy(peerId);

        if (!isHealthy) {
          log('🔧 محاولة إصلاح الاتصال مع $peerId');

          try {
            await _repairConnection(peerId);
          } catch (e) {
            log('❌ فشل إصلاح الاتصال مع $peerId: $e');

            // إعادة إنشاء الاتصال كملاذ أخير
            await _recreateConnection(peerId);
          }
        }

        // التحقق من المجارى البعيدة
        final remoteStream = _remoteStreams[peerId];
        if (remoteStream != null) {
          final remoteTracks = remoteStream.getAudioTracks();
          log('🔊 مسارات بعيدة من $peerId: ${remoteTracks.length}');

          for (final track in remoteTracks) {
            if (!track.enabled) {
              track.enabled = true;
              log('🔧 تم تفعيل مسار بعيد من $peerId: ${track.id}');
            }
          }
        } else {
          log('⚠️ لا يوجد مجرى بعيد من $peerId');
        }
      }

      log('🔍 === انتهاء التشخيص الشامل ===');

    } catch (e) {
      log('❌ خطأ في التشخيص الشامل: $e');
    }
  }

  // إصلاح الاتصال
  Future<void> _repairConnection(String peerId) async {
    final pc = _peers[peerId];
    if (pc == null) return;

    try {
      log('🔧 محاولة إصلاح اتصال $peerId');

      // إعادة تشغيل ICE
      await pc.restartIce();
      log('🔄 تم إعادة تشغيل ICE لـ $peerId');

      // انتظار لاستقرار الحالة
      await Future.delayed(const Duration(seconds: 2));

      // التحقق من التحسن
      final isFixed = await isPeerConnectionHealthy(peerId);
      if (isFixed) {
        log('✅ تم إصلاح الاتصال مع $peerId');
      } else {
        log('⚠️ لم يتم إصلاح الاتصال مع $peerId');
        throw Exception('فشل الإصلاح');
      }

    } catch (e) {
      log('❌ خطأ في إصلاح الاتصال مع $peerId: $e');
      rethrow;
    }
  }

  // إعادة إنشاء الاتصال
  Future<void> _recreateConnection(String peerId) async {
    try {
      log('🔄 إعادة إنشاء اتصال كامل مع $peerId');

      // إغلاق الاتصال القديم
      await _safeClosePeerConnection(peerId);

      // انتظار قصير
      await Future.delayed(const Duration(seconds: 1));

      // إنشاء اتصال جديد
      await createPeerConnectionForPeer(peerId);

      // انتظار الاستقرار
      await Future.delayed(const Duration(milliseconds: 500));

      // إنشاء عرض جديد
      await createOffer(peerId);

      log('✅ تم إعادة إنشاء الاتصال مع $peerId');

    } catch (e) {
      log('❌ خطأ في إعادة إنشاء الاتصال مع $peerId: $e');
    }
  }

  // دالة للحصول على إحصائيات مفصلة
  Future<Map<String, dynamic>> getDetailedStats() async {
    final stats = <String, dynamic>{};

    try {
      // إحصائيات عامة
      stats['localStreamActive'] = _localStream != null;
      stats['totalPeers'] = _peers.length;
      stats['remoteStreams'] = _remoteStreams.length;
      stats['pendingCandidates'] = _pendingCandidates.length;

      // إحصائيات لكل peer
      final peerStats = <String, dynamic>{};

      for (final peerId in _peers.keys) {
        final pc = _peers[peerId];
        if (pc != null) {
          final connectionState = await pc.getConnectionState();
          final iceState = await pc.getIceConnectionState();
          final signalingState = await pc.getSignalingState();
          final hasRemoteStream = _remoteStreams.containsKey(peerId);

          peerStats[peerId] = {
            'connectionState': connectionState.toString(),
            'iceState': iceState.toString(),
            'signalingState': signalingState.toString(),
            'hasRemoteStream': hasRemoteStream,
            'isHealthy': await isPeerConnectionHealthy(peerId),
          };
        }
      }

      stats['peers'] = peerStats;

      return stats;

    } catch (e) {
      log('❌ خطأ في جمع الإحصائيات: $e');
      return {'error': e.toString()};
    }
  }

  // تنظيف محسن
  @override
  Future<void> dispose() async {
    try {
      log('🧹 بدء تنظيف موارد WebRTC');

      // مسح حالات التتبع
      _connectionInProgress.clear();
      _lastConnectionAttempt.clear();

      // إغلاق جميع peer connections
      final peerIds = List<String>.from(_peers.keys);
      for (final peerId in peerIds) {
        await _safeClosePeerConnection(peerId);
      }

      // إغلاق المجرى المحلي
      if (_localStream != null) {
        _localStream!.getTracks().forEach((track) => track.stop());
        await _localStream!.dispose();
        _localStream = null;
      }

      log('✅ تم تنظيف جميع موارد WebRTC');
    } catch (e) {
      log('❌ خطأ في تنظيف الموارد: $e');
    }
  }
}