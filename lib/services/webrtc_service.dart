import 'dart:async';
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

  // Getter لقراءة الـ local stream
  MediaStream? get localStream => _localStream;

  // Getter لقراءة الـ remote streams
  Map<String, MediaStream> get remoteStreams => _remoteStreams;

  bool hasPeer(String peerId) {
    return _peers.containsKey(peerId);
  }

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

  Future<RTCSessionDescription> createAnswer(String peerId) async {
    try {
      final pc = _peers[peerId];
      if (pc == null) {
        throw Exception('لا يوجد peer connection للمعرف $peerId');
      }

      // التحقق من وجود remote description
      final remoteDesc = await pc.getRemoteDescription();
      if (remoteDesc == null) {
        throw Exception('لا يوجد remote description للـ peer $peerId');
      }

      // التأكد من وجود مسارات صوتية محلية
      await _verifyLocalTracks(pc, peerId);

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
      onAnswerCreated?.call(peerId, answer);
      log('📨 تم إرسال الإجابة لـ $peerId');

      return answer;
    } catch (e) {
      log('❌ خطأ في إنشاء الإجابة لـ $peerId: $e');
      rethrow;
    }
  }

  Future<void> recreateFailedConnections() async {
    log('🔄 إعادة إنشاء الاتصالات الفاشلة...');

    final failedPeers = <String>[];

    for (final entry in _peers.entries) {
      final peerId = entry.key;
      final pc = entry.value;

      if (pc.connectionState == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          pc.iceConnectionState == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        failedPeers.add(peerId);
      }
    }

    for (final peerId in failedPeers) {
      try {
        log('🔄 إعادة إنشاء الاتصال مع $peerId');
        await closePeerConnection(peerId);
        await createPeerConnectionForPeer(peerId);
        await createOffer(peerId);
      } catch (e) {
        log('❌ فشل في إعادة إنشاء الاتصال مع $peerId: $e');
      }
    }
  }

// دالة لضمان تشغيل الصوت المحلي والبعيد
  Future<void> ensureAudioPlayback() async {
    log('🔊 ضمان تشغيل الصوت في جميع الاتصالات...');

    // تفعيل الصوت المحلي
    if (_localStream != null) {
      final localTracks = _localStream!.getAudioTracks();
      for (final track in localTracks) {
        if (!track.enabled) {
          track.enabled = true;
          log('✓ تم تفعيل المسار المحلي: ${track.id}');
        }
      }
    }

    // تفعيل جميع المسارات البعيدة
    for (final entry in _remoteStreams.entries) {
      final peerId = entry.key;
      final stream = entry.value;
      final audioTracks = stream.getAudioTracks();

      for (final track in audioTracks) {
        if (!track.enabled) {
          track.enabled = true;
          log('✓ تم تفعيل مسار بعيد من $peerId');
        }
      }
    }

    // إحصائيات نهائية
    final totalRemoteTracks = _remoteStreams.values
        .map((s) => s.getAudioTracks().length)
        .fold(0, (sum, count) => sum + count);

    log('📊 إجمالي المسارات البعيدة المفعلة: $totalRemoteTracks');
  }

  Future<void> toggleMicrophone() async {
    if (_localStream != null) {
      final audioTracks = _localStream!.getAudioTracks();
      if (audioTracks.isNotEmpty) {
        final track = audioTracks.first;
        track.enabled = !track.enabled;
        log('الميكروفون ${track.enabled ? 'مفعل' : 'مكتوم'}');

        // إشعار جميع الـ peers بحالة المسار الجديدة
        for (final entry in _peers.entries) {
          final pc = entry.value;
          final List senders = await pc.getSenders();
          for (final sender in senders) {
            if (sender.track?.kind == 'audio') {
              // إعادة إرسال المسار المحدث
              sender.replaceTrack(track);
              log('تم تحديث مسار الصوت للـ peer ${entry.key}');
            }
          }
        }
      }
    }
  }

// دالة محسنة للتشخيص
  Future<void> debugConnectionStates() async {
    log('=== حالة الاتصالات WebRTC ===');
    log('عدد الـ peers: ${_peers.length}');
    log('عدد المجاري البعيدة: ${_remoteStreams.length}');

    if (_localStream != null) {
      final localAudioTracks = _localStream!.getAudioTracks();
      log('المسارات الصوتية المحلية: ${localAudioTracks.length}');
      for (final track in localAudioTracks) {
        log('مسار محلي: id=${track.id}, kind=${track.kind}, enabled=${track.enabled}');
      }
    }

    for (final entry in _peers.entries) {
      final pc = entry.value;
      log('Peer ${entry.key}:');
      log('  - connectionState: ${pc.connectionState}');
      log('  - iceConnectionState: ${pc.iceConnectionState}');
      log('  - signalingState: ${pc.signalingState}');

      // المرسلات
      final senders = await pc.getSenders();
      log('  - عدد المرسلات: ${senders.length}');
      for (final sender in senders) {
        if (sender.track != null) {
          log('    - مرسل: ${sender.track!.kind}, id=${sender.track!.id}, enabled=${sender.track!.enabled}');
        }
      }

      // المستقبلات
      final receivers = await pc.getReceivers();
      log('  - عدد المستقبلات: ${receivers.length}');
      for (final receiver in receivers) {
        if (receiver.track != null) {
          log('    - مستقبل: ${receiver.track!.kind}, id=${receiver.track!.id}, enabled=${receiver.track!.enabled}');
        }
      }
    }

    // المجاري البعيدة
    for (final entry in _remoteStreams.entries) {
      final tracks = entry.value.getAudioTracks();
      log('المجرى البعيد ${entry.key}: ${tracks.length} مسارات صوتية');
      for (final track in tracks) {
        log('  - مسار بعيد: id=${track.id}, kind=${track.kind}, enabled=${track.enabled}');
      }
    }
  }

  Future<void> refreshAudioConnections() async {
    log('إعادة تنشيط اتصالات الصوت...');

    for (final entry in _peers.entries) {
      final peerId = entry.key;
      final pc = entry.value;

      try {
        // التحقق من وجود مسارات صوتية
        final List senders = await pc.getSenders();
        bool hasAudioSender = false;

        for (final sender in senders) {
          if (sender.track?.kind == 'audio') {
            hasAudioSender = true;
            log('مسار صوتي موجود للـ peer $peerId');
            break;
          }
        }

        // إضافة مسار صوتي إذا لم يكن موجوداً
        if (!hasAudioSender && _localStream != null) {
          final audioTracks = _localStream!.getAudioTracks();
          if (audioTracks.isNotEmpty) {
            await pc.addTrack(audioTracks.first, _localStream!);
            log('تم إضافة مسار صوتي جديد للـ peer $peerId');
          }
        }

      } catch (e) {
        log('خطأ في تنشيط الصوت للـ peer $peerId: $e');
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

  Future<RTCPeerConnection> createPeerConnectionForPeer(String peerId) async {
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
      _setupPeerConnectionHandlers(pc, peerId);

      // إضافة المسارات الصوتية المحلية
      await _addLocalTracksToConnection(pc, peerId);

      _peers[peerId] = pc;
      log('✅ تم إنشاء peer connection للـ $peerId بنجاح');

      return pc;

    } catch (e) {
      log('❌ خطأ في إنشاء peer connection لـ $peerId: $e');
      rethrow;
    }
  }

// دالة منفصلة لإعداد معالجات الأحداث
  void _setupPeerConnectionHandlers(RTCPeerConnection pc, String peerId) {
    // معالجة ICE candidates
    pc.onIceCandidate = (RTCIceCandidate candidate) {
      if (candidate.candidate != null && candidate.candidate!.isNotEmpty) {
        log('🧊 ICE candidate جديد للـ peer $peerId: ${candidate.candidate?.substring(0, 50)}...');
        onIceCandidateGenerated?.call(peerId, candidate);
      }
    };

    // معالجة المسارات البعيدة
    pc.onTrack = (RTCTrackEvent event) {
      log('🎵 تم استقبال مسار من $peerId - النوع: ${event.track.kind}');

      if (event.streams.isNotEmpty && event.track.kind == 'audio') {
        final remoteStream = event.streams.first;
        _remoteStreams[peerId] = remoteStream;

        // تفعيل المسار فوراً
        event.track.enabled = true;

        // إعداد معالجات أحداث المسار
        event.track.onEnded = () => log('🔇 انتهى المسار الصوتي من $peerId');
        event.track.onMute = () => log('🔇 تم كتم المسار من $peerId');
        event.track.onUnMute = () => log('🔊 تم إلغاء كتم المسار من $peerId');

        log('✅ تم تسجيل مسار صوتي بعيد من $peerId - ID: ${event.track.id}');

        // تأكيد تفعيل الصوت بعد تأخير
        Future.delayed(const Duration(milliseconds: 200), () {
          _ensureRemoteAudioEnabled(peerId);
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

// دالة منفصلة لإضافة المسارات المحلية
  Future<void> _addLocalTracksToConnection(RTCPeerConnection pc, String peerId) async {
    if (_localStream == null) {
      log('⚠️ لا يوجد مجرى محلي - إعادة التهيئة');
      await initializeLocalAudio();
    }

    if (_localStream != null) {
      final audioTracks = _localStream!.getAudioTracks();
      log('🎤 إضافة ${audioTracks.length} مسارات صوتية محلية لـ $peerId');

      for (final track in audioTracks) {
        // التأكد من تفعيل المسار
        track.enabled = true;

        try {
          await pc.addTrack(track, _localStream!);
          log('✅ تم إضافة مسار صوتي محلي: ${track.id}');
        } catch (e) {
          log('❌ فشل في إضافة مسار صوتي: $e');
        }
      }
    }
  }

// معالجات الأحداث المحسنة
  void _onPeerConnected(String peerId) {
    // تفعيل الصوت عند الاتصال
    Future.delayed(const Duration(milliseconds: 500), () {
      _ensureRemoteAudioEnabled(peerId);
    });
  }

  void _onPeerFailed(String peerId) {
    // إعادة المحاولة بعد تأخير
    Future.delayed(const Duration(seconds: 3), () {
      if (_peers.containsKey(peerId)) {
        log('🔄 إعادة محاولة الاتصال مع $peerId بعد فشل');
        _retryConnection(peerId);
      }
    });
  }

  void _ensureRemoteAudioEnabled(String peerId) {
    final stream = _remoteStreams[peerId];
    if (stream != null) {
      final audioTracks = stream.getAudioTracks();
      for (final track in audioTracks) {
        if (!track.enabled) {
          track.enabled = true;
          log('🔊 تم تفعيل الصوت البعيد لـ $peerId');
        }
      }
    }
  }

// تحسين دالة createOffer
  Future<RTCSessionDescription> createOffer(String peerId) async {
    try {
      final pc = _peers[peerId];
      if (pc == null) {
        throw Exception('لا يوجد peer connection للمعرف $peerId');
      }

      // التأكد من وجود مسارات صوتية
      await _verifyLocalTracks(pc, peerId);

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
      onOfferCreated?.call(peerId, offer);
      log('📨 تم إرسال العرض لـ $peerId');

      return offer;
    } catch (e) {
      log('❌ خطأ في إنشاء العرض لـ $peerId: $e');
      rethrow;
    }
  }

// التحقق من المسارات المحلية
  Future<void> _verifyLocalTracks(RTCPeerConnection pc, String peerId) async {
    final senders = await pc.getSenders();
    bool hasAudioSender = false;

    for (final sender in senders) {
      if (sender.track?.kind == 'audio') {
        hasAudioSender = true;
        break;
      }
    }

    if (!hasAudioSender) {
      log('⚠️ لا يوجد مرسل صوتي لـ $peerId - إضافة مسار');
      await _addLocalTracksToConnection(pc, peerId);
    }
  }

// دالة لإعادة محاولة الاتصال في حالة الفشل
  Future<void> _retryConnection(String peerId) async {
    try {
      log('🔄 إعادة محاولة الاتصال مع $peerId');

      // إغلاق الاتصال الحالي
      await closePeerConnection(peerId);

      // إعادة إنشاء الاتصال بعد تأخير
      await Future.delayed(const Duration(seconds: 2));

      await createPeerConnectionForPeer(peerId);
      await createOffer(peerId);

      log('✅ تمت إعادة محاولة الاتصال مع $peerId');
    } catch (e) {
      log('❌ فشل في إعادة محاولة الاتصال مع $peerId: $e');
    }
  }

// تحديث دالة diagnoseAndFixAudio لتكون أكثر شمولية
  Future<void> diagnoseAndFixAudio() async {
    log('🔍 === بدء تشخيص شامل للصوت ===');

    // 1. فحص وإصلاح الصوت المحلي
    if (_localStream == null) {
      log('❌ المجرى المحلي غير موجود - إعادة التهيئة');
      try {
        await initializeLocalAudio();
        log('✅ تم إصلاح المجرى المحلي');
      } catch (e) {
        log('❌ فشل في إصلاح المجرى المحلي: $e');
        return;
      }
    }

    final localTracks = _localStream!.getAudioTracks();
    log('🎤 المسارات المحلية: ${localTracks.length}');

    for (int i = 0; i < localTracks.length; i++) {
      final track = localTracks[i];
      log('   مسار محلي $i: enabled=${track.enabled}, muted=${track.muted}');

      // تفعيل المسار إذا كان معطلاً
      if (!track.enabled) {
        track.enabled = true;
        log('   ✅ تم تفعيل المسار المحلي $i');
      }
    }

    // 2. فحص وإصلاح اتصالات الـ peers
    log('🔗 فحص ${_peers.length} اتصالات peers:');

    for (final entry in _peers.entries) {
      final peerId = entry.key;
      final pc = entry.value;

      log('   Peer $peerId:');
      log('     - Connection: ${pc.connectionState}');
      log('     - ICE: ${pc.iceConnectionState}');
      log('     - Signaling: ${pc.signalingState}');

      // فحص المرسلات الصوتية
      final senders = await pc.getSenders();
      bool hasActiveSender = false;

      for (final sender in senders) {
        if (sender.track?.kind == 'audio') {
          hasActiveSender = true;
          final track = sender.track!;
          log('     - مرسل صوتي: enabled=${track.enabled}, muted=${track.muted}');

          // تفعيل المسار إذا كان معطلاً
          if (!track.enabled) {
            track.enabled = true;
            log('     ✅ تم تفعيل المرسل الصوتي');
          }
        }
      }

      // إضافة مسار صوتي إذا لم يكن موجوداً
      if (!hasActiveSender && _localStream != null) {
        final audioTracks = _localStream!.getAudioTracks();
        if (audioTracks.isNotEmpty) {
          try {
            await pc.addTrack(audioTracks.first, _localStream!);
            log('     ✅ تم إضافة مسار صوتي جديد للـ peer $peerId');
          } catch (e) {
            log('     ❌ فشل في إضافة مسار صوتي: $e');
          }
        }
      }

      // فحص المستقبلات الصوتية
      final receivers = await pc.getReceivers();
      for (final receiver in receivers) {
        if (receiver.track?.kind == 'audio') {
          final track = receiver.track!;
          log('     - مستقبل صوتي: enabled=${track.enabled}, muted=${track.muted}');

          if (!track.enabled) {
            track.enabled = true;
            log('     ✅ تم تفعيل المستقبل الصوتي');
          }
        }
      }
    }

    // 3. فحص وإصلاح المجاري البعيدة
    log('🔊 فحص ${_remoteStreams.length} مجاري بعيدة:');

    for (final entry in _remoteStreams.entries) {
      final peerId = entry.key;
      final stream = entry.value;
      final audioTracks = stream.getAudioTracks();

      log('   مجرى $peerId: ${audioTracks.length} مسارات');

      for (int i = 0; i < audioTracks.length; i++) {
        final track = audioTracks[i];
        log(
          '     مسار $i: enabled=${track.enabled}, muted=${track.muted}, kind=${track.kind}, id=${track.id}, label=${track.label}',
        );

        // تفعيل المسار البعيد
        if (!track.enabled) {
          track.enabled = true;
          log('     ✅ تم تفعيل المسار البعيد $i');
        }
      }
    }

    // 4. إحصائيات نهائية
    final totalLocalTracks = _localStream?.getAudioTracks().length ?? 0;
    final totalRemoteTracks = _remoteStreams.values
        .map((s) => s.getAudioTracks().length)
        .fold(0, (sum, count) => sum + count);

    log('📊 === نتائج التشخيص ===');
    log('   - المسارات المحلية: $totalLocalTracks');
    log('   - المسارات البعيدة: $totalRemoteTracks');
    log('   - اتصالات الـ peers: ${_peers.length}');
    log('   - المجاري البعيدة: ${_remoteStreams.length}');

    // إعادة تشغيل الصوت للتأكد
    await _restartAllAudio();
  }

// دالة جديدة لإعادة تشغيل جميع المسارات الصوتية
  Future<void> _restartAllAudio() async {
    log('🔄 إعادة تشغيل جميع المسارات الصوتية...');

    // إعادة تشغيل الصوت المحلي
    if (_localStream != null) {
      final localTracks = _localStream!.getAudioTracks();
      for (final track in localTracks) {
        // إعادة تعيين الإعدادات
        track.enabled = false;
        await Future.delayed(const Duration(milliseconds: 100));
        track.enabled = true;
        log('🔄 تم إعادة تشغيل مسار محلي: ${track.id}');
      }
    }

    // إعادة تشغيل الصوت البعيد
    for (final entry in _remoteStreams.entries) {
      final peerId = entry.key;
      final audioTracks = entry.value.getAudioTracks();

      for (final track in audioTracks) {
        track.enabled = false;
        await Future.delayed(const Duration(milliseconds: 100));
        track.enabled = true;
        log('🔄 تم إعادة تشغيل مسار بعيد من $peerId: ${track.id}');
      }
    }

    log('✅ تم إعادة تشغيل جميع المسارات الصوتية');
  }

// إضافة متغير لحفظ الـ candidates المؤجلة
  final Map<String, List<RTCIceCandidate>> _pendingCandidates = {};

  Future<void> setRemoteDescription(String peerId, RTCSessionDescription description) async {
    try {
      final pc = _peers[peerId];
      if (pc == null) {
        // إنشاء peer connection جديد إذا لم يكن موجوداً
        log('⚠️ لا يوجد peer connection لـ $peerId، إنشاء جديد...');
        await createPeerConnectionForPeer(peerId);
      }

      final peer = _peers[peerId]!;

      log('📝 تعيين Remote Description لـ $peerId - النوع: ${description.type}');

      // تعيين Remote Description
      await peer.setRemoteDescription(description);
      log('✅ تم تعيين Remote Description لـ $peerId');

      // إضافة ICE candidates المؤجلة إذا وجدت
      await _processPendingCandidates(peerId);

      // إذا كان العرض، نحتاج لإنشاء إجابة
      if (description.type == 'offer') {
        log('📥 استقبال عرض من $peerId، إنشاء إجابة...');

        // تأخير قصير للتأكد من استقرار الحالة
        await Future.delayed(const Duration(milliseconds: 100));

        await createAnswer(peerId);
      }

    } catch (e) {
      log('❌ خطأ في تعيين Remote Description لـ $peerId: $e');
      rethrow;
    }
  }

// تحسين addIceCandidate مع نظام انتظار أفضل
  Future<void> addIceCandidate(String peerId, RTCIceCandidate candidate) async {
    try {
      final pc = _peers[peerId];
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

  // تحسين نظام الـ candidates المؤجلة
  void _addPendingCandidate(String peerId, RTCIceCandidate candidate) {
    _pendingCandidates[peerId] ??= [];
    _pendingCandidates[peerId]!.add(candidate);

    log('📋 تم تأجيل ICE candidate لـ $peerId (المجموع: ${_pendingCandidates[peerId]!.length})');

    // محاولة المعالجة بعد تأخير
    Future.delayed(const Duration(milliseconds: 2000), () {
      _processPendingCandidates(peerId);
    });
  }

  Future<void> _processPendingCandidates(String peerId) async {
    final candidates = _pendingCandidates[peerId];
    if (candidates == null || candidates.isEmpty) return;

    final pc = _peers[peerId];
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
    _pendingCandidates.remove(peerId);
    log('🗑️ تم مسح الـ candidates المؤجلة لـ $peerId');
  }

// دالة محسنة للتحقق من الصوت البعيد
  void enableRemoteAudio() {
    log('تفعيل جميع المسارات الصوتية البعيدة...');

    for (final entry in _remoteStreams.entries) {
      final peerId = entry.key;
      final stream = entry.value;
      final audioTracks = stream.getAudioTracks();

      log('معالجة الصوت البعيد لـ $peerId - عدد المسارات: ${audioTracks.length}');

      for (final track in audioTracks) {
        track.enabled = true;
        log('✓ تم تفعيل مسار صوتي بعيد: ${track.id} من $peerId');
      }
    }
  }

  // دالة محسنة لإعادة تأسيس الاتصالات الفاشلة
  Future<void> restartFailedConnections() async {
    log('🔄 فحص وإعادة تأسيس الاتصالات الفاشلة...');

    final failedPeers = <String>[];

    // فحص جميع الاتصالات
    for (final entry in _peers.entries) {
      final peerId = entry.key;
      final pc = entry.value;

      final connectionState = pc.connectionState;
      final iceState = pc.iceConnectionState;

      log('فحص $peerId: Connection=$connectionState, ICE=$iceState');

      if (connectionState == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          connectionState == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          iceState == RTCIceConnectionState.RTCIceConnectionStateFailed ||
          iceState == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
        failedPeers.add(peerId);
      }
    }

    // إعادة تأسيس الاتصالات الفاشلة
    for (final peerId in failedPeers) {
      try {
        log('🔄 إعادة تأسيس الاتصال مع $peerId');

        // إغلاق الاتصال القديم
        await closePeerConnection(peerId);

        // انتظار قبل إنشاء اتصال جديد
        await Future.delayed(const Duration(milliseconds: 1000));

        // إنشاء اتصال جديد
        await createPeerConnectionForPeer(peerId);

        // انتظار ثم إنشاء عرض جديد
        await Future.delayed(const Duration(milliseconds: 500));
        await createOffer(peerId);

        log('✅ تم إعادة تأسيس الاتصال مع $peerId');

      } catch (e) {
        log('❌ فشل في إعادة تأسيس الاتصال مع $peerId: $e');
      }
    }

    if (failedPeers.isNotEmpty) {
      log('تمت إعادة تأسيس ${failedPeers.length} اتصالات فاشلة');
    }
  }

  void _performHealthCheck() {
    log('🏥 === فحص صحة الاتصالات ===');

    int healthyConnections = 0;
    int totalConnections = _peers.length;

    if (totalConnections == 0) {
      log('ℹ️ لا توجد اتصالات للفحص');
      return;
    }

    for (final entry in _peers.entries) {
      final peerId = entry.key;
      final pc = entry.value;

      try {
        final connectionState = pc.connectionState;
        final iceState = pc.iceConnectionState;
        final signalingState = pc.signalingState;

        log('🔍 فحص $peerId:');
        log('   📡 Connection: $connectionState');
        log('   🧊 ICE: $iceState');
        log('   📻 Signaling: $signalingState');

        // اعتبار الاتصال صحياً إذا كان متصلاً أو في طور الاتصال
        if (connectionState == RTCPeerConnectionState.RTCPeerConnectionStateConnected ||
            connectionState == RTCPeerConnectionState.RTCPeerConnectionStateConnecting ||
            iceState == RTCIceConnectionState.RTCIceConnectionStateConnected ||
            iceState == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
          healthyConnections++;
          log('   ✅ اتصال صحي');
        } else {
          log('   ❌ اتصال غير صحي');
          log('   🔧 محاولة إصلاح فوري...');
          _attemptQuickFix(peerId, pc);
        }

      } catch (e) {
        log('   ⚠️ خطأ في فحص $peerId: $e');
      }
    }

    log('📊 الاتصالات الصحية: $healthyConnections/$totalConnections');

    // إعادة تأسيس فقط إذا كانت جميع الاتصالات فاشلة
    if (totalConnections > 0 && healthyConnections == 0) {
      log('🚨 جميع الاتصالات فاشلة - إعادة تأسيس شاملة');
      Future.delayed(const Duration(seconds: 2), () {
        restartFailedConnections();
      });
    }
  }

// محاولة إصلاح سريعة للاتصال
  Future<void> _attemptQuickFix(String peerId, RTCPeerConnection pc) async {
    try {
      log('🔧 محاولة إصلاح سريعة لـ $peerId');

      // التحقق من وجود مسارات صوتية
      await _verifyLocalTracks(pc, peerId);

      // إعادة تفعيل الصوت المحلي والبعيد
      await _refreshAudioTracks(peerId);

      log('✅ تم الإصلاح السريع لـ $peerId');

    } catch (e) {
      log('❌ فشل الإصلاح السريع لـ $peerId: $e');
    }
  }

// تحديث المسارات الصوتية
  Future<void> _refreshAudioTracks(String peerId) async {
    // تحديث المسارات المحلية
    if (_localStream != null) {
      final localTracks = _localStream!.getAudioTracks();
      for (final track in localTracks) {
        track.enabled = true;
      }
    }

    // تحديث المسارات البعيدة
    final remoteStream = _remoteStreams[peerId];
    if (remoteStream != null) {
      final remoteTracks = remoteStream.getAudioTracks();
      for (final track in remoteTracks) {
        track.enabled = true;
      }
    }
  }

// دالة محسنة للتحقق من حالة الاتصال
  bool isPeerHealthy(String peerId) {
    final pc = _peers[peerId];
    if (pc == null) return false;

    try {
      final connectionState = pc.connectionState;
      final iceState = pc.iceConnectionState;

      return connectionState == RTCPeerConnectionState.RTCPeerConnectionStateConnected ||
          iceState == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          iceState == RTCIceConnectionState.RTCIceConnectionStateCompleted;
    } catch (e) {
      log('خطأ في فحص حالة $peerId: $e');
      return false;
    }
  }

// تحسين startConnectionHealthCheck
  void startConnectionHealthCheck() {
    log('🏥 بدء فحص الصحة الدوري كل 15 ثانية');

    Timer.periodic(const Duration(seconds: 15), (timer) {
      try {
        _performHealthCheck();
      } catch (e) {
        log('خطأ في فحص الصحة الدوري: $e');
      }
    });
  }

// دالة للتأكد من وجود الصوت في جميع الاتصالات
  Future<void> verifyAudioInAllConnections() async {
    log('🔊 التحقق من الصوت في جميع الاتصالات...');

    // فحص الصوت المحلي
    if (_localStream == null) {
      log('❌ لا يوجد مجرى صوتي محلي');
      await initializeLocalAudio();
    }

    final localTracks = _localStream?.getAudioTracks() ?? [];
    log('🎤 المسارات المحلية: ${localTracks.length}');

    // فحص كل peer connection
    for (final entry in _peers.entries) {
      final peerId = entry.key;
      final pc = entry.value;

      // فحص المرسلات الصوتية
      final senders = await pc.getSenders();
      bool hasAudioSender = false;

      for (final sender in senders) {
        if (sender.track?.kind == 'audio') {
          hasAudioSender = true;
          final track = sender.track!;
          if (!track.enabled) {
            track.enabled = true;
            log('✅ تم تفعيل مرسل صوتي لـ $peerId');
          }
        }
      }

      // إضافة مسار صوتي إذا لم يكن موجوداً
      if (!hasAudioSender && localTracks.isNotEmpty) {
        try {
          await pc.addTrack(localTracks.first, _localStream!);
          log('✅ تم إضافة مسار صوتي جديد لـ $peerId');
        } catch (e) {
          log('❌ فشل في إضافة مسار صوتي لـ $peerId: $e');
        }
      }

      // فحص المستقبلات
      final stream = _remoteStreams[peerId];
      if (stream != null) {
        final remoteTracks = stream.getAudioTracks();
        for (final track in remoteTracks) {
          if (!track.enabled) {
            track.enabled = true;
            log('✅ تم تفعيل مستقبل صوتي من $peerId');
          }
        }
      }
    }

    log('🔊 انتهى فحص الصوت لجميع الاتصالات');
  }

}