import 'dart:async';
import 'dart:developer';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'webrtc_audio_manager.dart';

class WebRTCDiagnostics {
  final Map<String, RTCPeerConnection> peers;
  final Map<String, MediaStream> remoteStreams;
  final MediaStream? Function() getLocalStream;

  late final WebRTCAudioManager _audioManager;

  WebRTCDiagnostics({
    required this.peers,
    required this.remoteStreams,
    required this.getLocalStream,
  }) {
    _audioManager = WebRTCAudioManager(
      peers: peers,
      remoteStreams: remoteStreams,
      getLocalStream: getLocalStream,
      setLocalStream: (stream) {}, // Not used in this context
    );
  }

  // فحص حالات الاتصالات
  Future<void> debugConnectionStates() async {
    log('=== حالة الاتصالات WebRTC ===');
    log('عدد الـ peers: ${peers.length}');
    log('عدد المجاري البعيدة: ${remoteStreams.length}');

    final localStream = getLocalStream();
    if (localStream != null) {
      final localAudioTracks = localStream.getAudioTracks();
      log('المسارات الصوتية المحلية: ${localAudioTracks.length}');
      for (final track in localAudioTracks) {
        log('مسار محلي: id=${track.id}, kind=${track.kind}, enabled=${track.enabled}');
      }
    }

    for (final entry in peers.entries) {
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
    for (final entry in remoteStreams.entries) {
      final tracks = entry.value.getAudioTracks();
      log('المجرى البعيد ${entry.key}: ${tracks.length} مسارات صوتية');
      for (final track in tracks) {
        log('  - مسار بعيد: id=${track.id}, kind=${track.kind}, enabled=${track.enabled}');
      }
    }
  }

  // تشخيص وإصلاح الصوت الشامل
  Future<void> diagnoseAndFixAudio() async {
    log('🔍 === بدء تشخيص شامل للصوت ===');

    // 1. فحص وإصلاح الصوت المحلي
    await _checkAndFixLocalAudio();

    // 2. فحص وإصلاح اتصالات الـ peers
    await _checkAndFixPeerConnections();

    // 3. فحص وإصلاح المجاري البعيدة
    _checkAndFixRemoteStreams();

    // 4. إحصائيات نهائية
    _logFinalStats();

    // إعادة تشغيل الصوت للتأكد
    await _audioManager.restartAllAudio();
  }

  // فحص الصوت المحلي
  Future<void> _checkAndFixLocalAudio() async {
    final localStream = getLocalStream();
    if (localStream == null) {
      log('❌ المجرى المحلي غير موجود - إعادة التهيئة');
      try {
        await _audioManager.initializeLocalAudio();
        log('✅ تم إصلاح المجرى المحلي');
      } catch (e) {
        log('❌ فشل في إصلاح المجرى المحلي: $e');
        return;
      }
    }

    final stream = getLocalStream();
    if (stream != null) {
      final localTracks = stream.getAudioTracks();
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
    }
  }

  // فحص اتصالات الـ peers
  Future<void> _checkAndFixPeerConnections() async {
    log('🔗 فحص ${peers.length} اتصالات peers:');

    for (final entry in peers.entries) {
      final peerId = entry.key;
      final pc = entry.value;

      log('   Peer $peerId:');
      log('     - Connection: ${pc.connectionState}');
      log('     - ICE: ${pc.iceConnectionState}');
      log('     - Signaling: ${pc.signalingState}');

      // فحص المرسلات الصوتية
      await _checkAndFixSenders(pc, peerId);

      // فحص المستقبلات الصوتية
      await _checkAndFixReceivers(pc, peerId);
    }
  }

  // فحص المرسلات الصوتية
  Future<void> _checkAndFixSenders(RTCPeerConnection pc, String peerId) async {
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
    if (!hasActiveSender) {
      final localStream = getLocalStream();
      if (localStream != null) {
        final audioTracks = localStream.getAudioTracks();
        if (audioTracks.isNotEmpty) {
          try {
            await pc.addTrack(audioTracks.first, localStream);
            log('     ✅ تم إضافة مسار صوتي جديد للـ peer $peerId');
          } catch (e) {
            log('     ❌ فشل في إضافة مسار صوتي: $e');
          }
        }
      }
    }
  }

  // فحص المستقبلات الصوتية
  Future<void> _checkAndFixReceivers(RTCPeerConnection pc, String peerId) async {
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

  // فحص المجاري البعيدة
  void _checkAndFixRemoteStreams() {
    log('🔊 فحص ${remoteStreams.length} مجاري بعيدة:');

    for (final entry in remoteStreams.entries) {
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
  }

  // طباعة الإحصائيات النهائية
  void _logFinalStats() {
    final localStream = getLocalStream();
    final totalLocalTracks = localStream?.getAudioTracks().length ?? 0;
    final totalRemoteTracks = remoteStreams.values
        .map((s) => s.getAudioTracks().length)
        .fold(0, (sum, count) => sum + count);

    log('📊 === نتائج التشخيص ===');
    log('   - المسارات المحلية: $totalLocalTracks');
    log('   - المسارات البعيدة: $totalRemoteTracks');
    log('   - اتصالات الـ peers: ${peers.length}');
    log('   - المجاري البعيدة: ${remoteStreams.length}');
  }

  // فحص صحة الاتصال
  bool isPeerHealthy(String peerId) {
    final pc = peers[peerId];
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

  // بدء فحص الصحة الدوري
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

  // تنفيذ فحص الصحة
  void _performHealthCheck() {
    log('🏥 === فحص صحة الاتصالات ===');

    int healthyConnections = 0;
    int totalConnections = peers.length;

    if (totalConnections == 0) {
      log('ℹ️ لا توجد اتصالات للفحص');
      return;
    }

    for (final entry in peers.entries) {
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

  // محاولة إصلاح سريعة
  Future<void> _attemptQuickFix(String peerId, RTCPeerConnection pc) async {
    try {
      log('🔧 محاولة إصلاح سريعة لـ $peerId');

      // التحقق من وجود مسارات صوتية
      await _audioManager.verifyLocalTracks(pc, peerId);

      // إعادة تفعيل الصوت المحلي والبعيد
      await _audioManager.refreshAudioTracks(peerId);

      log('✅ تم الإصلاح السريع لـ $peerId');

    } catch (e) {
      log('❌ فشل الإصلاح السريع لـ $peerId: $e');
    }
  }

  // إعادة تأسيس الاتصالات الفاشلة
  Future<void> restartFailedConnections() async {
    log('🔄 فحص وإعادة تأسيس الاتصالات الفاشلة...');

    final failedPeers = <String>[];

    // فحص جميع الاتصالات
    for (final entry in peers.entries) {
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
      await _restartSingleConnection(peerId);
    }

    if (failedPeers.isNotEmpty) {
      log('تمت إعادة تأسيس ${failedPeers.length} اتصالات فاشلة');
    }
  }

  // إعادة تأسيس اتصال واحد
  Future<void> _restartSingleConnection(String peerId) async {
    try {
      log('🔄 إعادة تأسيس الاتصال مع $peerId');

      // إغلاق الاتصال القديم
      final pc = peers[peerId];
      if (pc != null) {
        await pc.close();
        peers.remove(peerId);
        remoteStreams.remove(peerId);
      }

      // انتظار قبل إنشاء اتصال جديد
      await Future.delayed(const Duration(milliseconds: 1000));

      // سيتم إعادة الإنشاء من خلال الخدمة الرئيسية
      log('✅ تم تنظيف الاتصال القديم مع $peerId');

    } catch (e) {
      log('❌ فشل في إعادة تأسيس الاتصال مع $peerId: $e');
    }
  }

  // التحقق من الصوت في جميع الاتصالات
  Future<void> verifyAudioInAllConnections() async {
    log('🔊 التحقق من الصوت في جميع الاتصالات...');

    // فحص الصوت المحلي
    final localStream = getLocalStream();
    if (localStream == null) {
      log('❌ لا يوجد مجرى صوتي محلي');
      await _audioManager.initializeLocalAudio();
    }

    final stream = getLocalStream();
    final localTracks = stream?.getAudioTracks() ?? [];
    log('🎤 المسارات المحلية: ${localTracks.length}');

    // فحص كل peer connection
    for (final entry in peers.entries) {
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
          await pc.addTrack(localTracks.first, stream!);
          log('✅ تم إضافة مسار صوتي جديد لـ $peerId');
        } catch (e) {
          log('❌ فشل في إضافة مسار صوتي لـ $peerId: $e');
        }
      }

      // فحص المستقبلات
      final remoteStream = remoteStreams[peerId];
      if (remoteStream != null) {
        final remoteTracks = remoteStream.getAudioTracks();
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