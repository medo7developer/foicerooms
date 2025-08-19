import 'dart:developer';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

class WebRTCService {
  MediaStream? _localStream;
  final Map<String, RTCPeerConnection> _peers = {};
  final Map<String, MediaStream> _remoteStreams = {};

  Function(String, RTCIceCandidate)? onIceCandidateGenerated;
  Function(String, RTCSessionDescription)? onOfferCreated;
  Function(String, RTCSessionDescription)? onAnswerCreated;

  bool hasPeer(String peerId) {
    return _peers.containsKey(peerId);
  }

  // Ice servers configuration
  final Map<String, dynamic> _configuration = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
    'sdpSemantics': 'unified-plan',
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

  // تعديل معالج أحداث ICE candidate
  void _onIceCandidate(String peerId, RTCIceCandidate candidate) {
    log('ICE candidate جديد للـ peer $peerId');
    onIceCandidateGenerated?.call(peerId, candidate);
  }

// إضافة دالة لربط الخدمة مع Supabase
  void setSignalingCallbacks({
    Function(String, RTCIceCandidate)? onIceCandidate,
    Function(String, RTCSessionDescription)? onOffer,
    Function(String, RTCSessionDescription)? onAnswer,
  }) {
    onIceCandidateGenerated = onIceCandidate;
    onOfferCreated = onOffer;
    onAnswerCreated = onAnswer;
  }

// إضافة دالة للاتصال بجميع اللاعبين في الغرفة
  Future<void> connectToAllPeers(List<String> peerIds, String myId) async {
    for (final peerId in peerIds) {
      if (peerId != myId) {
        await createPeerConnectionForPeer(peerId);
        // إنشاء offer للاعبين الآخرين
        await createOffer(peerId);
      }
    }
  }

// 3. تعديل دالة createPeerConnectionForPeer بالكامل:
  Future<RTCPeerConnection> createPeerConnectionForPeer(String peerId) async {
    try {
      // تحديث إعدادات ICE servers
      final Map<String, dynamic> configuration = {
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
          {'urls': 'stun:stun1.l.google.com:19302'},
          {'urls': 'stun:stun2.l.google.com:19302'},
          {'urls': 'stun:stun3.l.google.com:19302'},
          {'urls': 'stun:stun4.l.google.com:19302'},
        ],
        'sdpSemantics': 'unified-plan',
        'iceCandidatePoolSize': 10,
      };

      final pc = await createPeerConnection(configuration);

      // إضافة المسارات الصوتية المحلية أولاً
      if (_localStream != null) {
        final audioTracks = _localStream!.getAudioTracks();
        for (final track in audioTracks) {
          await pc.addTrack(track, _localStream!);
          log('تم إضافة مسار صوتي للـ peer $peerId');
        }
      }

      // معالجة ICE candidates
      pc.onIceCandidate = (RTCIceCandidate candidate) {
        if (candidate.candidate != null && candidate.candidate!.isNotEmpty) {
          log('ICE candidate جديد للـ peer $peerId: ${candidate.candidate}');
          onIceCandidateGenerated?.call(peerId, candidate);
        }
      };

      // معالجة المسارات البعيدة
      pc.onTrack = (RTCTrackEvent event) {
        log('تم استقبال مسار من $peerId - النوع: ${event.track.kind}');
        if (event.streams.isNotEmpty) {
          final remoteStream = event.streams.first;
          _remoteStreams[peerId] = remoteStream;

          // تفعيل تشغيل الصوت البعيد
          final audioTracks = remoteStream.getAudioTracks();
          for (final track in audioTracks) {
            track.enabled = true;
            log('تم تفعيل مسار صوتي بعيد من $peerId');
          }

          log('تم حفظ المجرى البعيد لـ $peerId');
        }
      };

      // معالجة حالات الاتصال
      pc.onConnectionState = (RTCPeerConnectionState state) {
        log('حالة الاتصال مع $peerId: $state');
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          log('✓ تم الاتصال بنجاح مع $peerId');
        } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
          log('✗ فشل الاتصال مع $peerId');
        }
      };

      // معالجة ICE connection state
      pc.onIceConnectionState = (RTCIceConnectionState state) {
        log('حالة ICE مع $peerId: $state');
      };

      _peers[peerId] = pc;
      log('تم إنشاء peer connection للـ $peerId');
      return pc;
    } catch (e) {
      log('خطأ في إنشاء peer connection: $e');
      rethrow;
    }
  }

  // 4. إضافة دالة للتحقق من المسارات الصوتية:
  void checkAudioTracks() {
    if (_localStream != null) {
      final tracks = _localStream!.getAudioTracks();
      log('المسارات الصوتية المحلية: ${tracks.length}');
      for (int i = 0; i < tracks.length; i++) {
        final track = tracks[i];
        log('المسار $i: enabled=${track.enabled}, kind=${track.kind}, id=${track.id}');
      }
    }

    for (final entry in _remoteStreams.entries) {
      final tracks = entry.value.getAudioTracks();
      log('المسارات البعيدة من ${entry.key}: ${tracks.length}');
    }
  }

// 5. تحديث دالة createOffer:
  Future<RTCSessionDescription> createOffer(String peerId) async {
    try {
      final pc = _peers[peerId];
      if (pc == null) throw Exception('لا يوجد peer connection للمعرف $peerId');

      // إعدادات SDP محسنة
      final Map<String, dynamic> offerOptions = {
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': false,
        'iceRestart': false,
      };

      final offer = await pc.createOffer(offerOptions);
      await pc.setLocalDescription(offer);

      log('تم إنشاء العرض للـ peer $peerId');
      log('SDP Offer: ${offer.sdp?.substring(0, 100)}...');

      onOfferCreated?.call(peerId, offer);
      return offer;
    } catch (e) {
      log('خطأ في إنشاء العرض: $e');
      rethrow;
    }
  }

// 6. تحديث دالة createAnswer:
  Future<RTCSessionDescription> createAnswer(String peerId) async {
    try {
      final pc = _peers[peerId];
      if (pc == null) throw Exception('لا يوجد peer connection للمعرف $peerId');

      final Map<String, dynamic> answerOptions = {
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': false,
      };

      final answer = await pc.createAnswer(answerOptions);
      await pc.setLocalDescription(answer);

      log('تم إنشاء الإجابة للـ peer $peerId');
      log('SDP Answer: ${answer.sdp?.substring(0, 100)}...');

      onAnswerCreated?.call(peerId, answer);
      return answer;
    } catch (e) {
      log('خطأ في إنشاء الإجابة: $e');
      rethrow;
    }
  }

// 7. تحديث دالة setRemoteDescription:
  Future<void> setRemoteDescription(String peerId, RTCSessionDescription description) async {
    try {
      final pc = _peers[peerId];
      if (pc == null) {
        // إنشاء peer connection إذا لم يكن موجوداً
        await createPeerConnectionForPeer(peerId);
        final newPc = _peers[peerId];
        if (newPc == null) throw Exception('فشل في إنشاء peer connection');
      }

      await _peers[peerId]!.setRemoteDescription(description);
      log('تم تعيين الوصف البعيد للـ peer $peerId - النوع: ${description.type}');
    } catch (e) {
      log('خطأ في تعيين الوصف البعيد: $e');
      rethrow;
    }
  }

// 8. تحديث دالة toggleMicrophone:
  void toggleMicrophone() {
    if (_localStream != null) {
      final audioTracks = _localStream!.getAudioTracks();
      if (audioTracks.isNotEmpty) {
        final track = audioTracks.first;
        track.enabled = !track.enabled;
        log('الميكروفون ${track.enabled ? 'مفعل' : 'مكتوم'}');

        // إشعار جميع الـ peers بتغيير حالة الصوت
        for (final entry in _peers.entries) {
          log('تحديث حالة الصوت للـ peer ${entry.key}');
        }
      }
    }
  }

// 9. إضافة دوال مساعدة للتشخيص:
  void debugConnectionStates() {
    log('=== حالة الاتصالات WebRTC ===');
    log('عدد الـ peers: ${_peers.length}');
    log('عدد المجاري البعيدة: ${_remoteStreams.length}');

    for (final entry in _peers.entries) {
      final pc = entry.value;
      log('Peer ${entry.key}: connectionState=${pc.connectionState}, iceConnectionState=${pc.iceConnectionState}');
    }

    checkAudioTracks();
  }

// 10. دالة لإعادة تشغيل الصوت البعيد:
  void enableRemoteAudio() {
    for (final entry in _remoteStreams.entries) {
      final stream = entry.value;
      final audioTracks = stream.getAudioTracks();
      for (final track in audioTracks) {
        track.enabled = true;
      }
      log('تم تفعيل الصوت البعيد لـ ${entry.key}');
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