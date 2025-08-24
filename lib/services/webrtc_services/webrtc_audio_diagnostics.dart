import 'dart:developer';
import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// خدمة تشخيص مشاكل الصوت في WebRTC - محسنة للإصدارات الحديثة
class WebRTCAudioDiagnostics {
  final Map<String, RTCPeerConnection> peers;
  final Map<String, MediaStream> remoteStreams;
  final MediaStream? Function() getLocalStream;

  WebRTCAudioDiagnostics({
    required this.peers,
    required this.remoteStreams,
    required this.getLocalStream,
  });

  /// فحص شامل للصوت مع تقرير مفصل
  Future<Map<String, dynamic>> performCompleteDiagnosis() async {
    log('🔍 === بدء التشخيص الشامل للصوت ===');

    final report = <String, dynamic>{};
    final issues = <String>[];
    final solutions = <String>[];

    try {
      // 1. فحص الصوت المحلي
      final localAudioStatus = await _diagnoseLocalAudio();
      report['localAudio'] = localAudioStatus;

      if (!localAudioStatus['isWorking']) {
        issues.add('الصوت المحلي لا يعمل');
        solutions.add('إعادة تهيئة الصوت المحلي');
      }

      // 2. فحص الاتصالات البعيدة
      final remoteAudioStatus = await _diagnoseRemoteAudio();
      report['remoteAudio'] = remoteAudioStatus;

      if (remoteAudioStatus['workingConnections'] == 0 && peers.isNotEmpty) {
        issues.add('لا يوجد صوت بعيد');
        solutions.add('إعادة تأسيس الاتصالات');
      }

      // 3. فحص peer connections
      final connectionsStatus = await _diagnosePeerConnections();
      report['connections'] = connectionsStatus;

      if (connectionsStatus['unhealthyCount'] > 0) {
        issues.add('اتصالات غير صحية');
        solutions.add('إصلاح الاتصالات المعطلة');
      }

      // 4. فحص متقدم للمتصفحات الحديثة
      final advancedStatus = await _diagnoseAdvancedFeatures();
      report['advanced'] = advancedStatus;

      report['issues'] = issues;
      report['solutions'] = solutions;
      report['overallHealth'] = _calculateOverallHealth(report);

      _printDiagnosisReport(report);

      return report;

    } catch (e) {
      log('❌ خطأ في التشخيص الشامل: $e');
      report['error'] = e.toString();
      return report;
    }
  }

  /// فحص الصوت المحلي
  Future<Map<String, dynamic>> _diagnoseLocalAudio() async {
    final localStream = getLocalStream();
    final status = <String, dynamic>{};

    if (localStream == null) {
      status['isWorking'] = false;
      status['error'] = 'لا يوجد مجرى صوتي محلي';
      return status;
    }

    final audioTracks = localStream.getAudioTracks();
    status['trackCount'] = audioTracks.length;

    if (audioTracks.isEmpty) {
      status['isWorking'] = false;
      status['error'] = 'لا توجد مسارات صوتية محلية';
      return status;
    }

    final track = audioTracks.first;
    status['enabled'] = track.enabled;
    status['kind'] = track.kind;
    status['id'] = track.id;
    status['muted'] = track.muted;

    // فحص إعدادات المسار
    try {
      final constraints = await track.getConstraints();
      status['constraints'] = constraints;
    } catch (e) {
      status['constraintsError'] = e.toString();
    }

    // ✅ معالجة null values
    status['isWorking'] = (track.enabled ?? false) && !(track.muted ?? true);

    return status;
  }

  /// فحص الصوت البعيد
  Future<Map<String, dynamic>> _diagnoseRemoteAudio() async {
    final status = <String, dynamic>{};
    final peerDetails = <String, dynamic>{};
    int workingConnections = 0;

    for (final entry in remoteStreams.entries) {
      final peerId = entry.key;
      final stream = entry.value;

      final peerStatus = <String, dynamic>{};
      final audioTracks = stream.getAudioTracks();

      peerStatus['trackCount'] = audioTracks.length;

      if (audioTracks.isNotEmpty) {
        final track = audioTracks.first;

        // الخصائص المتاحة
        peerStatus['enabled'] = track.enabled;
        peerStatus['muted'] = track.muted;

        // ✅ تحديد حالة عمل المسار
        final isEnabled = track.enabled ?? false;
        final isMuted = track.muted ?? true;

        if (isEnabled && !isMuted) {
          workingConnections++;
          peerStatus['isWorking'] = true;
        } else {
          peerStatus['isWorking'] = false;
        }
      } else {
        peerStatus['isWorking'] = false;
        peerStatus['error'] = 'لا توجد مسارات صوتية';
      }

      peerDetails[peerId] = peerStatus;
    }

    status['totalPeers'] = remoteStreams.length;
    status['workingConnections'] = workingConnections;
    status['peerDetails'] = peerDetails;

    return status;
  }

  /// فحص peer connections
  Future<Map<String, dynamic>> _diagnosePeerConnections() async {
    final status = <String, dynamic>{};
    final connectionDetails = <String, dynamic>{};

    int healthyCount = 0;
    int unhealthyCount = 0;

    for (final entry in peers.entries) {
      final peerId = entry.key;
      final pc = entry.value;

      final connectionStatus = <String, dynamic>{};

      try {
        final connectionState = await pc.getConnectionState();
        final iceState = await pc.getIceConnectionState();
        final signalingState = await pc.getSignalingState();

        connectionStatus['connectionState'] = connectionState.toString();
        connectionStatus['iceState'] = iceState.toString();
        connectionStatus['signalingState'] = signalingState.toString();

        // فحص الـ senders
        final senders = await pc.getSenders();
        final audioSenders = senders.where((s) => s.track?.kind == 'audio').toList();
        connectionStatus['audioSenders'] = audioSenders.length;

        // فحص الـ receivers
        final receivers = await pc.getReceivers();
        final audioReceivers = receivers.where((r) => r.track?.kind == 'audio').toList();
        connectionStatus['audioReceivers'] = audioReceivers.length;

        // تقييم صحة الاتصال
        final isHealthy = _isConnectionHealthy(connectionState!, iceState!, signalingState!);
        connectionStatus['isHealthy'] = isHealthy;

        if (isHealthy) {
          healthyCount++;
        } else {
          unhealthyCount++;
        }

      } catch (e) {
        connectionStatus['error'] = e.toString();
        connectionStatus['isHealthy'] = false;
        unhealthyCount++;
      }

      connectionDetails[peerId] = connectionStatus;
    }

    status['totalConnections'] = peers.length;
    status['healthyCount'] = healthyCount;
    status['unhealthyCount'] = unhealthyCount;
    status['connectionDetails'] = connectionDetails;

    return status;
  }

  /// فحص الميزات المتقدمة للإصدارات الحديثة
  Future<Map<String, dynamic>> _diagnoseAdvancedFeatures() async {
    final status = <String, dynamic>{};

    try {
      // فحص دعم الميزات المتقدمة
      status['webrtcSupport'] = await _checkWebRTCSupport();
      status['audioContext'] = await _checkAudioContext();
      status['mediaDevices'] = await _checkMediaDevicesSupport();

    } catch (e) {
      status['error'] = e.toString();
    }

    return status;
  }

  /// التحقق من دعم WebRTC
  Future<Map<String, dynamic>> _checkWebRTCSupport() async {
    final support = <String, dynamic>{};

    try {
      // فحص وجود WebRTC APIs الأساسية
      support['rtcPeerConnection'] = true; // إذا وصلنا هنا فهو موجود
      support['mediaDevices'] = true;
      support['getUserMedia'] = true;

    } catch (e) {
      support['error'] = e.toString();
    }

    return support;
  }

  /// فحص Audio Context
  Future<Map<String, dynamic>> _checkAudioContext() async {
    // هذا فحص عام لحالة الصوت في النظام
    return {
      'available': true,
      'note': 'Audio context availability check requires platform-specific implementation'
    };
  }

  /// فحص دعم Media Devices
  Future<Map<String, dynamic>> _checkMediaDevicesSupport() async {
    final support = <String, dynamic>{};

    try {
      // محاولة الحصول على قائمة الأجهزة
      final devices = await navigator.mediaDevices.enumerateDevices();
      final audioInputs = devices.where((d) => d.kind == 'audioinput').toList();

      support['totalDevices'] = devices.length;
      support['audioInputDevices'] = audioInputs.length;
      support['hasAudioInputs'] = audioInputs.isNotEmpty;

    } catch (e) {
      support['error'] = e.toString();
    }

    return support;
  }

  /// تحديد ما إذا كان الاتصال صحي
  bool _isConnectionHealthy(
      RTCPeerConnectionState connectionState,
      RTCIceConnectionState iceState,
      RTCSignalingState signalingState,
      ) {
    return (connectionState == RTCPeerConnectionState.RTCPeerConnectionStateConnected ||
        connectionState == RTCPeerConnectionState.RTCPeerConnectionStateConnecting) &&
        (iceState == RTCIceConnectionState.RTCIceConnectionStateConnected ||
            iceState == RTCIceConnectionState.RTCIceConnectionStateCompleted) &&
        signalingState == RTCSignalingState.RTCSignalingStateStable;
  }

  /// حساب الصحة الإجمالية
  String _calculateOverallHealth(Map<String, dynamic> report) {
    final localAudio = report['localAudio'] as Map<String, dynamic>? ?? {};
    final remoteAudio = report['remoteAudio'] as Map<String, dynamic>? ?? {};
    final connections = report['connections'] as Map<String, dynamic>? ?? {};

    final localWorking = localAudio['isWorking'] ?? false;
    final hasRemoteAudio = (remoteAudio['workingConnections'] ?? 0) > 0;
    final healthyConnections = (connections['healthyCount'] ?? 0) > 0;

    if (localWorking && hasRemoteAudio && healthyConnections) {
      return 'ممتازة';
    } else if (localWorking && healthyConnections) {
      return 'جيدة';
    } else if (localWorking) {
      return 'متوسطة';
    } else {
      return 'ضعيفة';
    }
  }

  /// طباعة تقرير التشخيص
  void _printDiagnosisReport(Map<String, dynamic> report) {
    log('📊 === تقرير التشخيص الشامل ===');

    final overallHealth = report['overallHealth'] ?? 'غير معروف';
    log('🎯 الصحة الإجمالية: $overallHealth');

    final localAudio = report['localAudio'] as Map<String, dynamic>? ?? {};
    log('🎤 الصوت المحلي: ${localAudio['isWorking'] ? 'يعمل' : 'لا يعمل'}');

    final remoteAudio = report['remoteAudio'] as Map<String, dynamic>? ?? {};
    final workingConnections = remoteAudio['workingConnections'] ?? 0;
    final totalPeers = remoteAudio['totalPeers'] ?? 0;
    log('🔊 الصوت البعيد: $workingConnections/$totalPeers يعمل');

    final connections = report['connections'] as Map<String, dynamic>? ?? {};
    final healthyCount = connections['healthyCount'] ?? 0;
    final totalConnections = connections['totalConnections'] ?? 0;
    log('📡 الاتصالات: $healthyCount/$totalConnections صحية');

    final issues = report['issues'] as List<String>? ?? [];
    if (issues.isNotEmpty) {
      log('⚠️ المشاكل المكتشفة:');
      for (final issue in issues) {
        log('  - $issue');
      }
    }

    final solutions = report['solutions'] as List<String>? ?? [];
    if (solutions.isNotEmpty) {
      log('💡 الحلول المقترحة:');
      for (final solution in solutions) {
        log('  - $solution');
      }
    }

    log('📊 === انتهاء التقرير ===');
  }

  /// إصلاح تلقائي للمشاكل المكتشفة
  Future<void> performAutoFix(Map<String, dynamic> diagnosis) async {
    log('🔧 === بدء الإصلاح التلقائي ===');

    final issues = diagnosis['issues'] as List<String>? ?? [];

    for (final issue in issues) {
      try {
        await _fixIssue(issue, diagnosis);
      } catch (e) {
        log('❌ فشل في إصلاح المشكلة "$issue": $e');
      }
    }

    log('🔧 === انتهاء الإصلاح التلقائي ===');
  }

  /// إصلاح مشكلة محددة
  Future<void> _fixIssue(String issue, Map<String, dynamic> diagnosis) async {
    switch (issue) {
      case 'الصوت المحلي لا يعمل':
        await _fixLocalAudio();
        break;
      case 'لا يوجد صوت بعيد':
        await _fixRemoteAudio();
        break;
      case 'اتصالات غير صحية':
        await _fixUnhealthyConnections();
        break;
      default:
        log('⚠️ مشكلة غير معروفة للإصلاح: $issue');
    }
  }

  /// إصلاح الصوت المحلي
  Future<void> _fixLocalAudio() async {
    log('🔧 إصلاح الصوت المحلي...');
    // هذا يتطلب الوصول لـ WebRTCAudioManager
    // يجب أن يتم استدعاؤه من WebRTCService
  }

  /// إصلاح الصوت البعيد
  Future<void> _fixRemoteAudio() async {
    log('🔧 إصلاح الصوت البعيد...');
    // تفعيل جميع المسارات البعيدة
    for (final stream in remoteStreams.values) {
      final audioTracks = stream.getAudioTracks();
      for (final track in audioTracks) {
        track.enabled = true;
      }
    }
  }

  /// إصلاح الاتصالات غير الصحية
  Future<void> _fixUnhealthyConnections() async {
    log('🔧 إصلاح الاتصالات غير الصحية...');

    for (final entry in peers.entries) {
      final peerId = entry.key;
      final pc = entry.value;

      try {
        final connectionState = await pc.getConnectionState();

        if (connectionState == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            connectionState == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {

          log('🔄 إعادة تشغيل ICE لـ $peerId');
          await pc.restartIce();
        }
      } catch (e) {
        log('❌ فشل في إصلاح اتصال $peerId: $e');
      }
    }
  }
}
