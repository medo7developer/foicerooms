import 'dart:async';
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
      // إعدادات محسنة للإصدارات الحديثة من flutter_webrtc 1.1.0+
      final Map<String, dynamic> configuration = {
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
          {'urls': 'stun:stun1.l.google.com:19302'},
          {'urls': 'stun:stun2.l.google.com:19302'},
          {'urls': 'stun:stun.cloudflare.com:3478'}, // إضافة Cloudflare STUN
          // إضافة TURN servers مجانية محدثة
          {
            'urls': [
              'turn:openrelay.metered.ca:80',
              'turn:openrelay.metered.ca:443',
              'turns:openrelay.metered.ca:443'
            ],
            'username': 'openrelayproject',
            'credential': 'openrelayproject',
          },
        ],
        'sdpSemantics': 'unified-plan',
        'iceCandidatePoolSize': 10,
        'bundlePolicy': 'max-bundle',
        'rtcpMuxPolicy': 'require',
        'iceTransportPolicy': 'all',
        // إضافة إعدادات جديدة للإصدارات الحديثة
        'enableDtlsSrtp': true,
        'enableRtpDataChannel': false,
        'enableDscp': true,
        'enableImplicitRollback': true,
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

  void _onPeerFailed(String peerId) {
    // إعادة المحاولة بعد تأخير
    Future.delayed(const Duration(seconds: 3), () {
      if (peers.containsKey(peerId)) {
        log('🔄 إعادة محاولة الاتصال مع $peerId بعد فشل');
        _retryConnection(peerId);
      }
    });
  }

// في WebRTCConnectionManager - تحديث createOffer
  Future<RTCSessionDescription> createOffer(
      String peerId,
      WebRTCSignalingCallbacks signalingCallbacks,
      ) async {
    try {
      final pc = peers[peerId];
      if (pc == null) {
        throw Exception('لا يوجد peer connection للمعرف $peerId');
      }

      // إضافة timeout
      final offer = await pc.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': false,
      }).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          log('⏰ timeout في إنشاء العرض لـ $peerId');
          throw TimeoutException('timeout في إنشاء العرض');
        },
      );

      await pc.setLocalDescription(offer).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          log('⏰ timeout في تعيين local description لـ $peerId');
          throw TimeoutException('timeout في تعيين local description');
        },
      );

      signalingCallbacks.onOfferCreated?.call(peerId, offer);
      log('📨 تم إرسال العرض لـ $peerId');

      return offer;
    } catch (e) {
      log('❌ خطأ في إنشاء العرض لـ $peerId: $e');
      rethrow;
    }
  }

// **أضف هذه الدالة الجديدة**
  Future<void> _resetPeerConnection(String peerId, WebRTCSignalingCallbacks signalingCallbacks) async {
    try {
      log('🔄 إعادة تعيين peer connection لـ $peerId');

      // احفظ المعلومات المهمة
      final oldPc = peers[peerId];
      if (oldPc != null) {
        await oldPc.close();
      }

      // إزالة من الخرائط
      peers.remove(peerId);
      remoteStreams.remove(peerId);

      // إنشاء اتصال جديد
      await createPeerConnectionForPeer(peerId, signalingCallbacks);

      log('✅ تم إعادة تعيين peer connection لـ $peerId');

    } catch (e) {
      log('❌ خطأ في إعادة التعيين لـ $peerId: $e');
      rethrow;
    }
  }

  Future<void> setRemoteDescription(String peerId, RTCSessionDescription description) async {
    try {
      RTCPeerConnection? pc = peers[peerId];
      if (pc == null) {
        log('⚠️ لا يوجد peer connection لـ $peerId، إنشاء جديد...');
        pc = await createPeerConnectionForPeer(peerId, WebRTCSignalingCallbacks());
      }

      log('📝 تعيين Remote Description لـ $peerId - النوع: ${description.type}');

      // التحقق من الحالة الحالية قبل التعيين
      final currentState = await pc.getSignalingState();
      log('📡 الحالة الحالية لـ $peerId: $currentState');

      // تعيين Remote Description
      await pc.setRemoteDescription(description);
      log('✅ تم تعيين Remote Description لـ $peerId');

      // معالجة خاصة حسب نوع الوصف
      if (description.type == 'offer') {
        log('📥 استقبال offer من $peerId');

        // انتظار قصير للاستقرار
        await Future.delayed(const Duration(milliseconds: 100));

        // التحقق من الحالة قبل إنشاء الإجابة
        final signalingState = await pc.getSignalingState();
        if (signalingState == RTCSignalingState.RTCSignalingStateHaveRemoteOffer) {
          log('📝 الحالة مناسبة لإنشاء answer');
          await createAnswer(peerId, WebRTCSignalingCallbacks());
        } else {
          log('⚠️ حالة signaling غير مناسبة: $signalingState');
        }

      } else if (description.type == 'answer') {
        log('📥 استقبال answer من $peerId');

        // التحقق من الحالة النهائية
        final finalState = await pc.getSignalingState();
        log('📡 الحالة النهائية لـ $peerId: $finalState');

        if (finalState == RTCSignalingState.RTCSignalingStateStable) {
          log('✅ تم تأسيس اتصال مستقر مع $peerId');

          // معالجة ICE candidates المؤجلة بعد الاستقرار
          await Future.delayed(const Duration(milliseconds: 200));
          await _processPendingCandidates(peerId);
        }
      }

    } catch (e) {
      log('❌ خطأ في تعيين Remote Description لـ $peerId: $e');

      // في حالة الخطأ، نحاول إعادة تأسيس الاتصال
      await Future.delayed(const Duration(seconds: 1));
      await _retryConnection(peerId);

      rethrow;
    }
  }

// تحسين دالة createAnswer
  Future<RTCSessionDescription> createAnswer(
      String peerId,
      WebRTCSignalingCallbacks signalingCallbacks,
      ) async {
    try {
      final pc = peers[peerId];
      if (pc == null) {
        throw Exception('لا يوجد peer connection للمعرف $peerId');
      }

      // التحقق من حالة الـ signaling
      final signalingState = await pc.getSignalingState();
      log('📡 حالة signaling عند إنشاء answer: $signalingState');

      if (signalingState != RTCSignalingState.RTCSignalingStateHaveRemoteOffer) {
        throw Exception('حالة signaling غير مناسبة لإنشاء answer: $signalingState');
      }

      // التحقق من وجود remote description
      final remoteDesc = await pc.getRemoteDescription();
      if (remoteDesc == null) {
        throw Exception('لا يوجد remote description للـ peer $peerId');
      }

      // التأكد من وجود مسارات صوتية محلية
      await _audioManager.verifyLocalTracks(pc, peerId);

      // إعدادات الإجابة المحسنة
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

      // التحقق من الحالة بعد تعيين الإجابة
      final finalState = await pc.getSignalingState();
      log('📡 حالة signaling بعد إنشاء answer: $finalState');

      // إرسال الإجابة
      signalingCallbacks.onAnswerCreated?.call(peerId, answer);
      log('📨 تم إرسال الإجابة لـ $peerId');

      return answer;
    } catch (e) {
      log('❌ خطأ في إنشاء الإجابة لـ $peerId: $e');
      rethrow;
    }
  }

// تحسين دالة addIceCandidate
  Future<void> addIceCandidate(String peerId, RTCIceCandidate candidate) async {
    try {
      final pc = peers[peerId];
      if (pc == null) {
        log('⚠️ لا يوجد peer connection لـ $peerId، تأجيل ICE candidate');
        _addPendingCandidate(peerId, candidate);
        return;
      }

      // التحقق من حالة الـ signaling
      final signalingState = await pc.getSignalingState();

      // التحقق من وجود remote description
      final remoteDesc = await pc.getRemoteDescription();
      if (remoteDesc == null) {
        log('⚠️ لا يوجد remote description لـ $peerId (حالة: $signalingState)، تأجيل ICE candidate');
        _addPendingCandidate(peerId, candidate);
        return;
      }

      // التحقق من أن الحالة مناسبة لإضافة candidates
      if (signalingState == RTCSignalingState.RTCSignalingStateHaveLocalOffer ||
          signalingState == RTCSignalingState.RTCSignalingStateHaveRemoteOffer) {
        log('⚠️ حالة signaling غير مستقرة ($signalingState)، تأجيل ICE candidate لـ $peerId');
        _addPendingCandidate(peerId, candidate);
        return;
      }

      // إضافة الـ candidate إذا كانت الحالة مناسبة
      await pc.addCandidate(candidate);
      log('✅ تم إضافة ICE candidate لـ $peerId (حالة: $signalingState)');

    } catch (e) {
      log('❌ خطأ في إضافة ICE candidate لـ $peerId: $e');
      // تأجيل الـ candidate للمعالجة لاحقاً في حالة الخطأ
      _addPendingCandidate(peerId, candidate);
    }
  }

// تحسين معالجة الـ candidates المؤجلة
  Future<void> _processPendingCandidates(String peerId) async {
    final candidates = pendingCandidates[peerId];
    if (candidates == null || candidates.isEmpty) return;

    final pc = peers[peerId];
    if (pc == null) {
      log('⚠️ لا يوجد peer connection لمعالجة candidates المؤجلة لـ $peerId');
      return;
    }

    // التحقق من الحالة
    final signalingState = await pc.getSignalingState();
    final remoteDesc = await pc.getRemoteDescription();

    if (remoteDesc == null) {
      log('⚠️ لا يزال لا يوجد remote description لـ $peerId، الانتظار...');
      return;
    }

    if (signalingState != RTCSignalingState.RTCSignalingStateStable) {
      log('⚠️ حالة signaling غير مستقرة ($signalingState) لـ $peerId، الانتظار...');

      // إعادة جدولة المعالجة
      Future.delayed(const Duration(seconds: 1), () {
        _processPendingCandidates(peerId);
      });
      return;
    }

    log('📋 معالجة ${candidates.length} ICE candidates مؤجلة لـ $peerId في حالة مستقرة');

    int successCount = 0;
    for (int i = 0; i < candidates.length; i++) {
      try {
        await pc.addCandidate(candidates[i]);
        successCount++;
        log('✅ تم إضافة candidate مؤجل ${i + 1}/${candidates.length} لـ $peerId');

        // تأخير صغير بين الـ candidates
        if (i < candidates.length - 1) {
          await Future.delayed(const Duration(milliseconds: 100));
        }

      } catch (e) {
        log('❌ فشل في إضافة candidate مؤجل ${i + 1} لـ $peerId: $e');
      }
    }

    // مسح الـ candidates المعالجة
    pendingCandidates.remove(peerId);
    log('🗑️ تم مسح الـ candidates المؤجلة لـ $peerId (نجح: $successCount/${candidates.length})');
  }

// تحسين إعداد معالجات الأحداث
  void _setupPeerConnectionHandlers(
      RTCPeerConnection pc,
      String peerId,
      WebRTCSignalingCallbacks signalingCallbacks,
      ) {
    // معالجة ICE candidates مع تصفية
    pc.onIceCandidate = (RTCIceCandidate candidate) {
      if (candidate.candidate != null &&
          candidate.candidate!.isNotEmpty &&
          !candidate.candidate!.contains('0.0.0.0')) {

        log('🧊 ICE candidate صالح للـ peer $peerId');
        signalingCallbacks.onIceCandidateGenerated?.call(peerId, candidate);
      } else {
        log('⚠️ تم تجاهل ICE candidate غير صالح لـ $peerId');
      }
    };

    // معالجة المسارات البعيدة مع تفعيل فوري
    // معالجة المسارات البعيدة محسنة للإصدارات الحديثة
    pc.onTrack = (RTCTrackEvent event) {
      log('🎵 تم استقبال مسار من $peerId - النوع: ${event.track.kind}');

      if (event.streams.isNotEmpty && event.track.kind == 'audio') {
        final remoteStream = event.streams.first;
        remoteStreams[peerId] = remoteStream;

        // تفعيل المسار فوراً مع معالجة محسنة
        event.track.enabled = true;

        // إعداد معالجات أحداث المسار محسنة
        event.track.onEnded = () {
          log('🔇 انتهى المسار الصوتي من $peerId');
          // إعادة محاولة الاتصال عند انتهاء المسار
          Future.delayed(const Duration(seconds: 2), () {
            _retryConnection(peerId);
          });
        };

        event.track.onMute = () {
          log('🔇 تم كتم المسار من $peerId');
        };

        event.track.onUnMute = () {
          log('🔊 تم إلغاء كتم المسار من $peerId');
        };

        log('✅ تم تسجيل مسار صوتي بعيد من $peerId');

        // تأكيد تفعيل الصوت مع إعدادات محسنة
        _ensureAudioEnabled(peerId, event.track);

        // إضافة معالجة خاصة للمتصفحات الحديثة
        Future.delayed(const Duration(milliseconds: 500), () {
          if (event.track.enabled != true) {
            event.track.enabled = true;
            log('🔧 إعادة تفعيل المسار البعيد من $peerId');
          }
        });
      }
    };

    // معالجة تغييرات حالة الاتصال مع إجراءات تصحيحية
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
          _onPeerDisconnected(peerId);
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
          log('🔄 جاري الاتصال مع $peerId');
          break;
        default:
          break;
      }
    };

    // معالجة ICE connection state
    pc.onIceConnectionState = (RTCIceConnectionState state) {
      log('🧊 حالة ICE مع $peerId: $state');

      switch (state) {
        case RTCIceConnectionState.RTCIceConnectionStateConnected:
        case RTCIceConnectionState.RTCIceConnectionStateCompleted:
          log('🎉 تم تأسيس اتصال ICE مع $peerId');
          // معالجة candidates مؤجلة عند الاتصال
          Future.delayed(const Duration(milliseconds: 500), () {
            _processPendingCandidates(peerId);
          });
          break;
        case RTCIceConnectionState.RTCIceConnectionStateFailed:
          log('❌ فشل ICE connection مع $peerId');
          _onIceFailed(peerId);
          break;
        case RTCIceConnectionState.RTCIceConnectionStateDisconnected:
          log('⚠️ انقطع ICE connection مع $peerId');
          break;
        default:
          break;
      }
    };

    // معالجة Signaling state مع مراقبة التحولات
    pc.onSignalingState = (RTCSignalingState state) {
      log('📡 حالة Signaling مع $peerId: $state');

      if (state == RTCSignalingState.RTCSignalingStateStable) {
        log('✅ وصل $peerId لحالة signaling مستقرة');
        // معالجة candidates مؤجلة عند الاستقرار
        Future.delayed(const Duration(milliseconds: 300), () {
          _processPendingCandidates(peerId);
        });
      }
    };
  }

// دالة مساعدة لضمان تفعيل الصوت
  void _ensureAudioEnabled(String peerId, MediaStreamTrack track) {
    // محاولة متعددة لتفعيل الصوت
    for (int i = 0; i < 3; i++) {
      Future.delayed(Duration(milliseconds: 200 * (i + 1)), () {
        if (track.enabled != true) {
          track.enabled = true;
          log('🔊 إعادة تفعيل مسار $peerId (محاولة ${i + 1})');
        }
      });
    }
  }

// معالجات الأحداث المحسنة
  void _onPeerConnected(String peerId) {
    Future.delayed(const Duration(milliseconds: 500), () {
      _audioManager.ensureRemoteAudioEnabled(peerId);
      _processPendingCandidates(peerId);
    });
  }

  void _onPeerDisconnected(String peerId) {
    log('🔄 محاولة إعادة الاتصال مع $peerId بعد انقطاع');
    Future.delayed(const Duration(seconds: 2), () {
      _retryConnection(peerId);
    });
  }

  void _onIceFailed(String peerId) {
    log('🔄 إعادة محاولة ICE لـ $peerId');
    Future.delayed(const Duration(seconds: 1), () {
      _retryConnection(peerId);
    });
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