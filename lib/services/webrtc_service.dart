import 'dart:developer';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

class WebRTCService {
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  final Map<String, RTCPeerConnection> _peers = {};
  final Map<String, MediaStream> _remoteStreams = {};

  // Ice servers configuration
  final Map<String, dynamic> _configuration = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
    'sdpSemantics': 'unified-plan',
  };

  final Map<String, dynamic> _constraints = {
    'mandatory': {},
    'optional': [
      {'DtlsSrtpKeyAgreement': true},
    ],
  };

  // طلب الصلاحيات
  Future<bool> requestPermissions() async {
    try {
      final status = await Permission.microphone.request();
      return status == PermissionStatus.granted;
    } catch (e) {
      log('خطأ في طلب الصلاحيات: $e');
      return false;
    }
  }

  // تهيئة الصوت المحلي
  Future<void> initializeLocalAudio() async {
    try {
      if (!await requestPermissions()) {
        throw Exception('صلاحيات الميكروفون غير متاحة');
      }

      final Map<String, dynamic> mediaConstraints = {
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': false,
      };

      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      log('تم تهيئة الصوت المحلي بنجاح');
    } catch (e) {
      log('خطأ في تهيئة الصوت المحلي: $e');
      rethrow;
    }
  }

  // إنشاء اتصال peer
  Future<RTCPeerConnection> createPeerConnection(String peerId) async {
    try {
      final pc = await RTCPeerConnection.create(_configuration, _constraints);

      // إضافة المسار الصوتي المحلي
      if (_localStream != null) {
        _localStream!.getTracks().forEach((track) {
          pc.addTrack(track, _localStream!);
        });
      }

      // معالجة الأحداث
      pc.onIceCandidate = (RTCIceCandidate candidate) {
        _onIceCandidate(peerId, candidate);
      };

      pc.onAddStream = (MediaStream stream) {
        _onAddRemoteStream(peerId, stream);
      };

      pc.onRemoveStream = (MediaStream stream) {
        _onRemoveRemoteStream(peerId, stream);
      };

      pc.onConnectionState = (RTCPeerConnectionState state) {
        log('حالة الاتصال مع $peerId: $state');
      };

      _peers[peerId] = pc;
      return pc;
    } catch (e) {
      log('خطأ في إنشاء peer connection: $e');
      rethrow;
    }
  }

  // إنشاء عرض (offer)
  Future<RTCSessionDescription> createOffer(String peerId) async {
    try {
      final pc = _peers[peerId];
      if (pc == null) throw Exception('لا يوجد peer connection للمعرف $peerId');

      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);

      log('تم إنشاء العرض للـ peer $peerId');
      return offer;
    } catch (e) {
      log('خطأ في إنشاء العرض: $e');
      rethrow;
    }
  }

  // إنشاء إجابة (answer)
  Future<RTCSessionDescription> createAnswer(String peerId) async {
    try {
      final pc = _peers[peerId];
      if (pc == null) throw Exception('لا يوجد peer connection للمعرف $peerId');

      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);

      log('تم إنشاء الإجابة للـ peer $peerId');
      return answer;
    } catch (e) {
      log('خطأ في إنشاء الإجابة: $e');
      rethrow;
    }
  }

  // تعيين الوصف البعيد
  Future<void> setRemoteDescription(String peerId, RTCSessionDescription description) async {
    try {
      final pc = _peers[peerId];
      if (pc == null) throw Exception('لا يوجد peer connection للمعرف $peerId');

      await pc.setRemoteDescription(description);
      log('تم تعيين الوصف البعيد للـ peer $peerId');
    } catch (e) {
      log('خطأ في تعيين الوصف البعيد: $e');
      rethrow;
    }
  }

  // إضافة مرشح ICE
  Future<void> addIceCandidate(String peerId, RTCIceCandidate candidate) async {
    try {
      final pc = _peers[peerId];
      if (pc == null) throw Exception('لا يوجد peer connection للمعرف $peerId');

      await pc.addCandidate(candidate);
      log('تم إضافة ICE candidate للـ peer $peerId');
    } catch (e) {
      log('خطأ في إضافة ICE candidate: $e');
      rethrow;
    }
  }

  // كتم/إلغاء كتم الميكروفون
  void toggleMicrophone() {
    if (_localStream != null) {
      final audioTracks = _localStream!.getAudioTracks();
      if (audioTracks.isNotEmpty) {
        final isEnabled = audioTracks.first.enabled;
        audioTracks.first.enabled = !isEnabled;
        log('الميكروفون ${!isEnabled ? 'مفعل' : 'مكتوم'}');
      }
    }
  }

  // التحقق من حالة الميكروفون
  bool get isMicrophoneEnabled {
    if (_localStream != null) {
      final audioTracks = _localStream!.getAudioTracks();
      if (audioTracks.isNotEmpty) {
        return audioTracks.first.enabled;
      }
    }
    return false;
  }

  // الحصول على المجرى البعيد
  MediaStream? getRemoteStream(String peerId) {
    return _remoteStreams[peerId];
  }

  // إغلاق اتصال peer محدد
  Future<void> closePeerConnection(String peerId) async {
    try {
      final pc = _peers[peerId];
      if (pc != null) {
        await pc.close();
        _peers.remove(peerId);
        _remoteStreams.remove(peerId);
        log('تم إغلاق الاتصال مع $peerId');
      }
    } catch (e) {
      log('خطأ في إغلاق الاتصال: $e');
    }
  }

  // إغلاق جميع الاتصالات
  Future<void> dispose() async {
    try {
      // إغلاق جميع peer connections
      for (final pc in _peers.values) {
        await pc.close();
      }
      _peers.clear();
      _remoteStreams.clear();

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

  // معالج أحداث ICE candidate
  void _onIceCandidate(String peerId, RTCIceCandidate candidate) {
    log('ICE candidate جديد للـ peer $peerId');
    // هنا يجب إرسال candidate إلى الخادم/Supabase
  }

  // معالج إضافة المجرى البعيد
  void _onAddRemoteStream(String peerId, MediaStream stream) {
    log('تم إضافة مجرى صوتي بعيد من $peerId');
    _remoteStreams[peerId] = stream;
  }

  // معالج إزالة المجرى البعيد
  void _onRemoveRemoteStream(String peerId, MediaStream stream) {
    log('تم إزالة مجرى صوتي بعيد من $peerId');
    _remoteStreams.remove(peerId);
  }
}