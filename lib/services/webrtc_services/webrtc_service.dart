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

  // Connection methods
  Future<RTCPeerConnection> createPeerConnectionForPeer(String peerId) {
    return _connectionManager.createPeerConnectionForPeer(
      peerId,
      _signalingCallbacks,
    );
  }

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

  // Cleanup
  Future<void> dispose() async {
    try {
      // إغلاق جميع peer connections
      for (final pc in _peers.values) {
        await pc.close();
      }
      _peers.clear();
      _remoteStreams.clear();
      _pendingCandidates.clear();

      // إغلاق المجرى المحلي
      if (_localStream != null) {
        _localStream!.getTracks().forEach((track) => track.stop());
        await _localStream!.dispose();
        _localStream = null;
      }

      log('تم تنظيف جميع موارد WebRTC');
    } catch (e) {
      log('خطأ في تنظيف الموارد: $e');
    }
  }
}