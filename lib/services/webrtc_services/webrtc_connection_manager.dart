import 'dart:developer';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'webrtc_audio_manager.dart';
import 'webrtc_signaling_callbacks.dart';

class WebRTCConnectionManager {
  final Map<String, RTCPeerConnection> peers;
  final Map<String, MediaStream> remoteStreams;
  final Map<String, List<RTCIceCandidate>> pendingCandidates;
  final MediaStream? Function() getLocalStream;

  late final WebRTCAudioManager _audioManager;

  WebRTCConnectionManager({
    required this.peers,
    required this.remoteStreams,
    required this.pendingCandidates,
    required this.getLocalStream,
  }) {
    _audioManager = WebRTCAudioManager(
      peers: peers,
      remoteStreams: remoteStreams,
      getLocalStream: getLocalStream,
      setLocalStream: (stream) {}, // Not used in this context
    );
  }

  // الاتصال بجميع اللاعبين في الغرفة
  Future<void> connectToAllPeers(List<String> peerIds, String myId) async {
    for (final peerId in peerIds) {
      if (peerId != myId) {
        await createPeerConnectionForPeer(peerId, WebRTCSignalingCallbacks());
        // إنشاء offer للاعبين الآخرين
        await createOffer(peerId, WebRTCSignalingCallbacks());
      }
    }
  }

  // إنشاء peer connection
  Future<RTCPeerConnection> createPeerConnectionForPeer(
      String peerId,
      WebRTCSignalingCallbacks signalingCallbacks,
      ) async {
    try {
      // إعدادات محسنة مع TURN servers إضافية
      final Map<String, dynamic> configuration = {
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
          {'urls': 'stun:stun1.l.google.com:19302'},
          {'urls': 'stun:stun2.l.google.com:19302'},
          // إضافة TURN servers مجانية
          {
            'urls': 'turn:openrelay.metered.ca:80',
            'username': 'openrelayproject',
            'credential': 'openrelayproject',
          },
          {
            'urls': 'turn:openrelay.metered.ca:443',
            'username': 'openrelayproject',
            'credential': 'openrelayproject',
          },
        ],
        'sdpSemantics': 'unified-plan',
        'iceCandidatePoolSize': 10,
        'bundlePolicy': 'max-bundle',
        'rtcpMuxPolicy': 'require',
        'iceTransportPolicy': 'all', // السماح بجميع أنواع الاتصال
      };

      log('🔧 إنشاء peer connection لـ $peerId مع إعدادات محسنة');
      final pc = await createPeerConnection(configuration);

      // إعداد معالجات الأحداث قبل إضافة المسارات
      _setupPeerConnectionHandlers(pc, peerId, signalingCallbacks);

      // إضافة المسارات الصوتية المحلية
      await _audioManager.addLocalTracksToConnection(pc, peerId);

      peers[peerId] = pc;
      log('✅ تم إنشاء peer connection للـ $peerId بنجاح');

      return pc;

    } catch (e) {
      log('❌ خطأ في إنشاء peer connection لـ $peerId: $e');
      rethrow;
    }
  }

  // إعداد معالجات الأحداث
  void _setupPeerConnectionHandlers(
      RTCPeerConnection pc,
      String peerId,
      WebRTCSignalingCallbacks signalingCallbacks,
      ) {
    // معالجة ICE candidates
    pc.onIceCandidate = (RTCIceCandidate candidate) {
      if (candidate.candidate != null && candidate.candidate!.isNotEmpty) {
        log('🧊 ICE candidate جديد للـ peer $peerId: ${candidate.candidate?.substring(0, 50)}...');
        signalingCallbacks.onIceCandidateGenerated?.call(peerId, candidate);
      }
    };

    // معالجة المسارات البعيدة
    pc.onTrack = (RTCTrackEvent event) {
      log('🎵 تم استقبال مسار من $peerId - النوع: ${event.track.kind}');

      if (event.streams.isNotEmpty && event.track.kind == 'audio') {
        final remoteStream = event.streams.first;
        remoteStreams[peerId] = remoteStream;

        // تفعيل المسار فوراً
        event.track.enabled = true;

        // إعداد معالجات أحداث المسار
        event.track.onEnded = () => log('🔇 انتهى المسار الصوتي من $peerId');
        event.track.onMute = () => log('🔇 تم كتم المسار من $peerId');
        event.track.onUnMute = () => log('🔊 تم إلغاء كتم المسار من $peerId');

        log('✅ تم تسجيل مسار صوتي بعيد من $peerId - ID: ${event.track.id}');

        // تأكيد تفعيل الصوت بعد تأخير
        Future.delayed(const Duration(milliseconds: 200), () {
          _audioManager.ensureRemoteAudioEnabled(peerId);
        });
      }
    };

    // معالجة تغييرات حالة الاتصال
    pc.onConnectionState = (RTCPeerConnectionState state) {
      log('🔗 حالة الاتصال مع $peerId: $state');

      switch (state) {
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          log('✅ تم الاتصال بنجاح مع $peerId');
          _onPeerConnected(peerId);
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          log('❌ فشل الاتصال مع $peerId');
          _onPeerFailed(peerId);
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
          log('⚠️ انقطع الاتصال مع $peerId');
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
          log('🔄 جاري الاتصال مع $peerId');
          break;
        default:
          log('ℹ️ حالة اتصال أخرى مع $peerId: $state');
      }
    };

    // معالجة ICE connection state
    pc.onIceConnectionState = (RTCIceConnectionState state) {
      log('🧊 حالة ICE مع $peerId: $state');

      switch (state) {
        case RTCIceConnectionState.RTCIceConnectionStateConnected:
          log('✅ تم تأسيس ICE connection مع $peerId');
          break;
        case RTCIceConnectionState.RTCIceConnectionStateCompleted:
          log('🎉 اكتمل ICE connection مع $peerId');
          break;
        case RTCIceConnectionState.RTCIceConnectionStateFailed:
          log('❌ فشل ICE connection مع $peerId');
          break;
        case RTCIceConnectionState.RTCIceConnectionStateDisconnected:
          log('⚠️ انقطع ICE connection مع $peerId');
          break;
        default:
          log('ℹ️ حالة ICE أخرى مع $peerId: $state');
      }
    };

    // معالجة Signaling state
    pc.onSignalingState = (RTCSignalingState state) {
      log('📡 حالة Signaling مع $peerId: $state');
    };

    // معالجة ICE gathering state
    pc.onIceGatheringState = (RTCIceGatheringState state) {
      log('🔍 حالة ICE Gathering مع $peerId: $state');
    };
  }

  // معالجات الأحداث
  void _onPeerConnected(String peerId) {
    // تفعيل الصوت عند الاتصال
    Future.delayed(const Duration(milliseconds: 500), () {
      _audioManager.ensureRemoteAudioEnabled(peerId);
    });
  }

  void _onPeerFailed(String peerId) {
    // إعادة المحاولة بعد تأخير
    Future.delayed(const Duration(seconds: 3), () {
      if (peers.containsKey(peerId)) {
        log('🔄 إعادة محاولة الاتصال مع $peerId بعد فشل');
        _retryConnection(peerId);
      }
    });
  }

  // إنشاء عرض
  Future<RTCSessionDescription> createOffer(
      String peerId,
      WebRTCSignalingCallbacks signalingCallbacks,
      ) async {
    try {
      final pc = peers[peerId];
      if (pc == null) {
        throw Exception('لا يوجد peer connection للمعرف $peerId');
      }

      // التأكد من وجود مسارات صوتية
      await _audioManager.verifyLocalTracks(pc, peerId);

      // إعدادات العرض المحسنة
      final Map<String, dynamic> offerOptions = {
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': false,
        'iceRestart': false,
        'voiceActivityDetection': true,
      };

      log('📤 إنشاء عرض لـ $peerId...');
      final offer = await pc.createOffer(offerOptions);

      // تعيين Local Description
      await pc.setLocalDescription(offer);
      log('✅ تم تعيين Local Description لـ $peerId');

      // إرسال العرض
      signalingCallbacks.onOfferCreated?.call(peerId, offer);
      log('📨 تم إرسال العرض لـ $peerId');

      return offer;
    } catch (e) {
      log('❌ خطأ في إنشاء العرض لـ $peerId: $e');
      rethrow;
    }
  }

  // إنشاء إجابة
  Future<RTCSessionDescription> createAnswer(
      String peerId,
      WebRTCSignalingCallbacks signalingCallbacks,
      ) async {
    try {
      final pc = peers[peerId];
      if (pc == null) {
        throw Exception('لا يوجد peer connection للمعرف $peerId');
      }

      // التحقق من وجود remote description
      final remoteDesc = await pc.getRemoteDescription();
      if (remoteDesc == null) {
        throw Exception('لا يوجد remote description للـ peer $peerId');
      }

      // التأكد من وجود مسارات صوتية محلية
      await _audioManager.verifyLocalTracks(pc, peerId);

      // إعدادات الإجابة
      final Map<String, dynamic> answerOptions = {
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': false,
        'voiceActivityDetection': true,
      };

      log('📥 إنشاء إجابة لـ $peerId...');
      final answer = await pc.createAnswer(answerOptions);

      // تعيين Local Description
      await pc.setLocalDescription(answer);
      log('✅ تم تعيين Local Description للإجابة لـ $peerId');

      // إرسال الإجابة
      signalingCallbacks.onAnswerCreated?.call(peerId, answer);
      log('📨 تم إرسال الإجابة لـ $peerId');

      return answer;
    } catch (e) {
      log('❌ خطأ في إنشاء الإجابة لـ $peerId: $e');
      rethrow;
    }
  }

  // تعيين Remote Description
  Future<void> setRemoteDescription(String peerId, RTCSessionDescription description) async {
    try {
      RTCPeerConnection? pc = peers[peerId];
      if (pc == null) {
        // إنشاء peer connection جديد إذا لم يكن موجوداً
        log('⚠️ لا يوجد peer connection لـ $peerId، إنشاء جديد...');
        pc = await createPeerConnectionForPeer(peerId, WebRTCSignalingCallbacks());
      }

      log('📝 تعيين Remote Description لـ $peerId - النوع: ${description.type}');

      // تعيين Remote Description
      await pc.setRemoteDescription(description);
      log('✅ تم تعيين Remote Description لـ $peerId');

      // إضافة ICE candidates المؤجلة إذا وجدت
      await _processPendingCandidates(peerId);

      // إذا كان العرض، نحتاج لإنشاء إجابة
      if (description.type == 'offer') {
        log('📥 استقبال عرض من $peerId، إنشاء إجابة...');

        // تأخير قصير للتأكد من استقرار الحالة
        await Future.delayed(const Duration(milliseconds: 100));

        await createAnswer(peerId, WebRTCSignalingCallbacks());
      }

    } catch (e) {
      log('❌ خطأ في تعيين Remote Description لـ $peerId: $e');
      rethrow;
    }
  }

  // إضافة ICE candidate
  Future<void> addIceCandidate(String peerId, RTCIceCandidate candidate) async {
    try {
      final pc = peers[peerId];
      if (pc == null) {
        log('⚠️ لا يوجد peer connection لـ $peerId، تأجيل ICE candidate');
        _addPendingCandidate(peerId, candidate);
        return;
      }

      // التحقق من حالة الـ peer connection
      final remoteDesc = await pc.getRemoteDescription();
      if (remoteDesc == null) {
        log('⚠️ لا يوجد remote description لـ $peerId، تأجيل ICE candidate');
        _addPendingCandidate(peerId, candidate);
        return;
      }

      // إضافة الـ candidate
      await pc.addCandidate(candidate);
      log('✅ تم إضافة ICE candidate لـ $peerId');

    } catch (e) {
      log('❌ خطأ في إضافة ICE candidate لـ $peerId: $e');

      // محاولة تأجيل الـ candidate للمعالجة لاحقاً
      _addPendingCandidate(peerId, candidate);
    }
  }

  // إغلاق اتصال peer محدد
  Future<void> closePeerConnection(String peerId) async {
    try {
      final pc = peers[peerId];
      if (pc != null) {
        await pc.close();
        peers.remove(peerId);
        remoteStreams.remove(peerId);
        pendingCandidates.remove(peerId);
        log('تم إغلاق الاتصال مع $peerId');
      }
    } catch (e) {
      log('خطأ في إغلاق الاتصال: $e');
    }
  }

  // إضافة candidate مؤجل
  void _addPendingCandidate(String peerId, RTCIceCandidate candidate) {
    pendingCandidates[peerId] ??= [];
    pendingCandidates[peerId]!.add(candidate);

    log('📋 تم تأجيل ICE candidate لـ $peerId (المجموع: ${pendingCandidates[peerId]!.length})');

    // محاولة المعالجة بعد تأخير
    Future.delayed(const Duration(milliseconds: 2000), () {
      _processPendingCandidates(peerId);
    });
  }

  // معالجة candidates المؤجلة
  Future<void> _processPendingCandidates(String peerId) async {
    final candidates = pendingCandidates[peerId];
    if (candidates == null || candidates.isEmpty) return;

    final pc = peers[peerId];
    if (pc == null) return;

    // التحقق من وجود remote description
    final remoteDesc = await pc.getRemoteDescription();
    if (remoteDesc == null) {
      log('⚠️ لا يزال لا يوجد remote description لـ $peerId، الانتظار...');
      return;
    }

    log('📋 معالجة ${candidates.length} ICE candidates مؤجلة لـ $peerId');

    for (int i = 0; i < candidates.length; i++) {
      try {
        await pc.addCandidate(candidates[i]);
        log('✅ تم إضافة candidate مؤجل ${i + 1}/${candidates.length} لـ $peerId');

        // تأخير صغير بين الـ candidates
        if (i < candidates.length - 1) {
          await Future.delayed(const Duration(milliseconds: 50));
        }

      } catch (e) {
        log('❌ فشل في إضافة candidate مؤجل لـ $peerId: $e');
      }
    }

    // مسح الـ candidates المعالجة
    pendingCandidates.remove(peerId);
    log('🗑️ تم مسح الـ candidates المؤجلة لـ $peerId');
  }

  // إعادة محاولة الاتصال
  Future<void> _retryConnection(String peerId) async {
    try {
      log('🔄 إعادة محاولة الاتصال مع $peerId');

      // إغلاق الاتصال الحالي
      await closePeerConnection(peerId);

      // إعادة إنشاء الاتصال بعد تأخير
      await Future.delayed(const Duration(seconds: 2));

      await createPeerConnectionForPeer(peerId, WebRTCSignalingCallbacks());
      await createOffer(peerId, WebRTCSignalingCallbacks());

      log('✅ تمت إعادة محاولة الاتصال مع $peerId');
    } catch (e) {
      log('❌ فشل في إعادة محاولة الاتصال مع $peerId: $e');
    }
  }
}