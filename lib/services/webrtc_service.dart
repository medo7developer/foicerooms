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

  Future<RTCSessionDescription> createOffer(String peerId) async {
    try {
      final pc = _peers[peerId];
      if (pc == null) throw Exception('لا يوجد peer connection للمعرف $peerId');

      // تأكد من وجود مسارات صوتية قبل إنشاء العرض
      if (_localStream != null) {
        final audioTracks = _localStream!.getAudioTracks();
        if (audioTracks.isEmpty) {
          log('⚠ لا توجد مسارات صوتية محلية');
          await initializeLocalAudio(); // إعادة تهيئة الصوت
        }
      }

      final Map<String, dynamic> offerOptions = {
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': false,
        'iceRestart': false,
      };

      final offer = await pc.createOffer(offerOptions);
      await pc.setLocalDescription(offer);

      log('✓ تم إنشاء العرض للـ peer $peerId');
      log('SDP Offer length: ${offer.sdp?.length ?? 0}');

      // تأخير قصير قبل إرسال العرض للتأكد من استقرار الحالة
      await Future.delayed(const Duration(milliseconds: 100));

      onOfferCreated?.call(peerId, offer);
      return offer;
    } catch (e) {
      log('✗ خطأ في إنشاء العرض: $e');
      rethrow;
    }
  }

// دالة محسنة لإنشاء answer
  Future<RTCSessionDescription> createAnswer(String peerId) async {
    try {
      final pc = _peers[peerId];
      if (pc == null) throw Exception('لا يوجد peer connection للمعرف $peerId');

      // التأكد من وجود remote description قبل إنشاء الإجابة
      if (await pc.getRemoteDescription() == null) {
        throw Exception('لا يوجد remote description للـ peer $peerId');
      }

      final Map<String, dynamic> answerOptions = {
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': false,
      };

      final answer = await pc.createAnswer(answerOptions);
      await pc.setLocalDescription(answer);

      log('✓ تم إنشاء الإجابة للـ peer $peerId');
      log('SDP Answer length: ${answer.sdp?.length ?? 0}');

      await Future.delayed(const Duration(milliseconds: 100));
      onAnswerCreated?.call(peerId, answer);
      return answer;
    } catch (e) {
      log('✗ خطأ في إنشاء الإجابة: $e');
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

// دالة محسنة لإضافة ice candidate
  Future<void> addIceCandidate(String peerId, RTCIceCandidate candidate) async {
    try {
      final pc = _peers[peerId];
      if (pc == null) {
        log('⚠ لا يوجد peer connection للمعرف $peerId عند إضافة ICE candidate');
        return;
      }

      // التحقق من حالة الاتصال
      final desc = await pc.getRemoteDescription();
      if (desc == null) {
        log('⚠ تأخير إضافة ICE candidate حتى يتم تعيين remote description');
        // ممكن تخزن الـ candidates مؤقتاً وتضيفها بعدين
        return;
      }

      await pc.addCandidate(candidate);
      log('✓ تم إضافة ICE candidate للـ peer $peerId');
    } catch (e) {
      log('✗ خطأ في إضافة ICE candidate للـ peer $peerId: $e');
    }
  }

  // إضافة دالة لفحص وإصلاح الصوت
  Future<void> diagnoseAndFixAudio() async {
    log('🔍 بدء تشخيص مشاكل الصوت...');

    // 1. فحص الصوت المحلي
    if (_localStream == null) {
      log('❌ المجرى المحلي غير موجود - إعادة التهيئة');
      await initializeLocalAudio();
    } else {
      final localTracks = _localStream!.getAudioTracks();
      log('🎤 المسارات المحلية: ${localTracks.length}');
      for (final track in localTracks) {
        log('   - مسار: ${track.id}, enabled: ${track.enabled}, muted: ${track.muted}');
        // إعداد الأحداث عند انتهاء المسار
        track.onEnded = () => log('   – المسار ${track.id} انتهى (ended)');
      }
    }

    // 2. فحص الاتصالات
    for (final entry in _peers.entries) {
      final peerId = entry.key;
      final pc = entry.value;

      log('🔗 فحص الاتصال مع $peerId:');
      log('   - Connection State: ${pc.connectionState}');
      log('   - ICE State: ${pc.iceConnectionState}');
      log('   - Signaling State: ${pc.signalingState}');

      final senders = await pc.getSenders();
      log('   - المرسلات: ${senders.length}');
      for (final sender in senders) {
        if (sender.track?.kind == 'audio') {
          final tr = sender.track!;
          log('     - مرسل صوتي: enabled=${tr.enabled}, muted=${tr.muted}');
          tr.onEnded = () => log('     – المرسل ${tr.id} انتهى (ended)');
        }
      }

      final receivers = await pc.getReceivers();
      log('   - المستقبلات: ${receivers.length}');
      for (final receiver in receivers) {
        if (receiver.track?.kind == 'audio') {
          final tr = receiver.track!;
          log('     - مستقبل صوتي: enabled=${tr.enabled}, muted=${tr.muted}');
          tr.onEnded = () => log('     – المستقبل ${tr.id} انتهى (ended)');
        }
      }
    }

    // 3. فحص المجاري البعيدة
    for (final entry in _remoteStreams.entries) {
      final peerId = entry.key;
      final stream = entry.value;
      final audioTracks = stream.getAudioTracks();

      log('🔊 مجرى بعيد من $peerId: ${audioTracks.length} مسارات');
      for (final track in audioTracks) {
        log('   - مسار: ${track.id}, enabled: ${track.enabled}, muted: ${track.muted}');
        track.onEnded = () => log('   – المجرى ${track.id} انتهى (ended)');
        // تفعيل المسار إذا كان معطلاً
        if (!track.enabled) {
          track.enabled = true;
          log('   ✓ تم تفعيل المسار ${track.id}');
        }
      }
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

// دالة محسنة لمعالجة الصوت البعيد
  void _onAddRemoteStream(String peerId, MediaStream stream) {
    log('تم إضافة مجرى صوتي بعيد من $peerId');
    _remoteStreams[peerId] = stream;

    // تفعيل المسارات الصوتية فوراً
    final audioTracks = stream.getAudioTracks();
    for (final track in audioTracks) {
      track.enabled = true;
      log('تم تفعيل مسار صوتي بعيد من $peerId - ID: ${track.id}');
    }
  }

// تحديث createPeerConnectionForPeer لإصلاح مشكلة الصوت:
  Future<RTCPeerConnection> createPeerConnectionForPeer(String peerId) async {
    try {
      // إعدادات محسنة
      final Map<String, dynamic> configuration = {
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
          {'urls': 'stun:stun1.l.google.com:19302'},
          {'urls': 'stun:stun2.l.google.com:19302'},
        ],
        'sdpSemantics': 'unified-plan',
        'iceCandidatePoolSize': 10,
      };

      final pc = await createPeerConnection(configuration);

      // إضافة المسارات الصوتية المحلية
      if (_localStream != null) {
        final audioTracks = _localStream!.getAudioTracks();
        for (final track in audioTracks) {
          await pc.addTrack(track, _localStream!);
          log('تم إضافة مسار صوتي محلي للـ peer $peerId');
        }
      }

      // معالجة ICE candidates
      pc.onIceCandidate = (RTCIceCandidate candidate) {
        if (candidate.candidate != null && candidate.candidate!.isNotEmpty) {
          log('ICE candidate جديد للـ peer $peerId');
          onIceCandidateGenerated?.call(peerId, candidate);
        }
      };

      // معالجة المسارات البعيدة - هذا هو الإصلاح الرئيسي
      pc.onTrack = (RTCTrackEvent event) {
        log('تم استقبال مسار من $peerId - النوع: ${event.track.kind}');

        if (event.streams.isNotEmpty) {
          final remoteStream = event.streams.first;
          _remoteStreams[peerId] = remoteStream;

          // تفعيل الصوت البعيد فوراً
          if (event.track.kind == 'audio') {
            event.track.enabled = true;
            log('✓ تم تفعيل مسار صوتي بعيد من $peerId');

            // إشعار أن الصوت متاح
            _onAddRemoteStream(peerId, remoteStream);
          }
        }
      };

      // معالجة تغيير حالة الاتصال
      pc.onConnectionState = (RTCPeerConnectionState state) {
        log('حالة الاتصال مع $peerId: $state');

        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          log('✓ تم الاتصال بنجاح مع $peerId');

          // التأكد من تفعيل الصوت عند الاتصال
          Future.delayed(const Duration(milliseconds: 500), () {
            _enableAudioForPeer(peerId);
          });
        }
      };

      // معالجة حالة ICE
      pc.onIceConnectionState = (RTCIceConnectionState state) {
        log('حالة ICE مع $peerId: $state');

        if (state == RTCIceConnectionState.RTCIceConnectionStateConnected) {
          log('✓ تم تأسيس ICE connection مع $peerId');
        }
      };

      _peers[peerId] = pc;
      log('تم إنشاء peer connection للـ $peerId');
      return pc;
    } catch (e) {
      log('خطأ في إنشاء peer connection: $e');
      rethrow;
    }
  }

// دالة جديدة لتفعيل الصوت لـ peer محدد
  void _enableAudioForPeer(String peerId) {
    final stream = _remoteStreams[peerId];
    if (stream != null) {
      final audioTracks = stream.getAudioTracks();
      for (final track in audioTracks) {
        track.enabled = true;
        log('تم تفعيل الصوت البعيد لـ $peerId - Track: ${track.id}');
      }
    }
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

  // معالج إزالة المجرى البعيد
  void _onRemoveRemoteStream(String peerId, MediaStream stream) {
    log('تم إزالة مجرى صوتي بعيد من $peerId');
    _remoteStreams.remove(peerId);
  }
}