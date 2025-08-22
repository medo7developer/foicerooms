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
// إضافة متغير لتتبع حالة الاتصالات
  final Map<String, String> _connectionStatus = {};

  late final WebRTCConnectionManager _connectionManager;
  late final WebRTCAudioManager _audioManager;
  late final WebRTCDiagnostics _diagnostics;
  late final WebRTCSignalingCallbacks _signalingCallbacks;
  // إضافة متغيرات للتحكم في التسلسل
  final Map<String, bool> _connectionInProgress = {};
  final Map<String, DateTime> _lastConnectionAttempt = {};

  bool get hasCallbacks => _signalingCallbacks.hasAllCallbacks;

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

// دالة محسنة لإنشاء peer connection مع معالجة أفضل
  Future<RTCPeerConnection> createPeerConnectionForPeer(String peerId) async {
    // منع المحاولات المتعددة المتزامنة
    if (_connectionInProgress[peerId] == true) {
      log('⚠️ اتصال مع $peerId قيد التنفيذ، انتظار انتهاء المحاولة الحالية...');

      // انتظار انتهاء المحاولة الحالية مع timeout
      int waitCount = 0;
      while (_connectionInProgress[peerId] == true && waitCount < 25) { // 5 ثوانٍ كحد أقصى
        await Future.delayed(const Duration(milliseconds: 200));
        waitCount++;
      }

      // إرجاع الاتصال إذا تم إنشاؤه بنجاح
      if (_peers.containsKey(peerId)) {
        log('✅ تم العثور على peer connection موجود لـ $peerId');
        return _peers[peerId]!;
      }
    }

    // التحقق من المحاولات المتكررة السريعة
    final lastAttempt = _lastConnectionAttempt[peerId];
    if (lastAttempt != null) {
      final timeDiff = DateTime.now().difference(lastAttempt).inSeconds;
      if (timeDiff < 3) { // تقليل الوقت إلى 3 ثوان
        log('⚠️ محاولة اتصال مع $peerId سريعة جداً، انتظار ${3 - timeDiff} ثانية');
        await Future.delayed(Duration(seconds: 3 - timeDiff));
      }
    }

    _connectionInProgress[peerId] = true;
    _lastConnectionAttempt[peerId] = DateTime.now();
    _connectionStatus[peerId] = 'creating';

    try {
      // إغلاق الاتصال القديم بأمان إن وجد
      await _safeClosePeerConnection(peerId);

      log('🔧 إنشاء peer connection جديد لـ $peerId');

      // إنشاء الاتصال مع timeout
      final pc = await _connectionManager.createPeerConnectionForPeer(
        peerId,
        _signalingCallbacks,
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          log('⏰ timeout في إنشاء peer connection لـ $peerId');
          throw TimeoutException('timeout في إنشاء peer connection');
        },
      );

      _peers[peerId] = pc;
      _connectionStatus[peerId] = 'created';
      log('✅ تم إنشاء peer connection لـ $peerId بنجاح');

      // التحقق من الاتصال بعد وقت قصير
      Future.delayed(const Duration(seconds: 2), () async {
        final isHealthy = await isPeerConnectionHealthy(peerId);
        _connectionStatus[peerId] = isHealthy ? 'healthy' : 'unhealthy';
        log('🔍 حالة peer $peerId بعد الإنشاء: ${_connectionStatus[peerId]}');
      });

      return pc;

    } catch (e) {
      _connectionStatus[peerId] = 'failed';
      log('❌ خطأ في إنشاء peer connection لـ $peerId: $e');
      rethrow;
    } finally {
      _connectionInProgress[peerId] = false;
    }
  }

// دالة محسنة للحصول على حالة الاتصال
  String getConnectionStatus(String peerId) {
    return _connectionStatus[peerId] ?? 'unknown';
  }

// دالة لفحص وإصلاح الاتصالات المتأخرة
  Future<void> checkAndFixLateConnections() async {
    log('🔍 فحص الاتصالات المتأخرة...');

    final peersToCheck = List<String>.from(_peers.keys);

    for (final peerId in peersToCheck) {
      final status = _connectionStatus[peerId];

      if (status == 'created' || status == 'unhealthy') {
        log('🔧 فحص اتصال متأخر مع $peerId (حالة: $status)');

        final isHealthy = await isPeerConnectionHealthy(peerId);

        if (!isHealthy) {
          log('⚠️ اتصال $peerId غير صحي، محاولة إصلاح');

          try {
            // محاولة إعادة تشغيل ICE
            final pc = _peers[peerId];
            if (pc != null) {
              await pc.restartIce();
              await Future.delayed(const Duration(seconds: 1));

              // فحص مرة أخرى
              final fixedHealthy = await isPeerConnectionHealthy(peerId);
              _connectionStatus[peerId] = fixedHealthy ? 'healthy' : 'failed';

              if (fixedHealthy) {
                log('✅ تم إصلاح اتصال $peerId');
              } else {
                log('❌ فشل إصلاح اتصال $peerId');
              }
            }
          } catch (e) {
            log('❌ خطأ في إصلاح اتصال $peerId: $e');
            _connectionStatus[peerId] = 'failed';
          }
        } else {
          _connectionStatus[peerId] = 'healthy';
          log('✅ اتصال $peerId صحي');
        }
      }
    }
  }

// دالة لإحصائيات الاتصالات
  Map<String, dynamic> getConnectionsStats() {
    final stats = <String, dynamic>{};
    final statusCount = <String, int>{};

    for (final status in _connectionStatus.values) {
      statusCount[status] = (statusCount[status] ?? 0) + 1;
    }

    stats['totalPeers'] = _peers.length;
    stats['statusBreakdown'] = statusCount;
    stats['hasLocalStream'] = _localStream != null;
    stats['remoteStreams'] = _remoteStreams.length;

    return stats;
  }

// تحديث دالة dispose لتنظيف المتغيرات الجديدة
  Future<void> dispose() async {
    try {
      log('🧹 بدء تنظيف موارد WebRTC');

      // مسح حالات التتبع
      _connectionInProgress.clear();
      _lastConnectionAttempt.clear();
      _connectionStatus.clear();

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

  // التعديل الخامس: إضافة هذه الدوال المفقودة في webrtc_service.dart:

// إضافة دالة إعادة تشغيل ICE لـ peer محدد
  Future<void> restartPeerIce(String peerId) async {
    try {
      final pc = _peers[peerId];
      if (pc != null) {
        log('🔄 إعادة تشغيل ICE للـ peer $peerId');
        await pc.restartIce();
        log('✅ تم إعادة تشغيل ICE للـ peer $peerId');
      } else {
        log('⚠️ لا يوجد peer connection للمعرف $peerId لإعادة تشغيل ICE');
      }
    } catch (e) {
      log('❌ خطأ في إعادة تشغيل ICE للـ peer $peerId: $e');
      rethrow;
    }
  }

// تحسين دالة createOffer مع معالجة أفضل للأخطاء
  Future<RTCSessionDescription> createOffer(String peerId) async {
    try {
      log('📤 بدء إنشاء offer لـ $peerId');

      // التحقق من وجود peer connection
      if (!_peers.containsKey(peerId)) {
        log('⚠️ لا يوجد peer connection لـ $peerId، إنشاء جديد...');
        await createPeerConnectionForPeer(peerId);
      }

      final pc = _peers[peerId]!;

      // التحقق من حالة signaling
      final signalingState = await pc.getSignalingState();
      log('📡 حالة signaling قبل إنشاء offer: $signalingState');

      // التحقق من وجود مسارات صوتية محلية
      final senders = await pc.getSenders();
      bool hasAudioSender = senders.any((sender) => sender.track?.kind == 'audio');

      if (!hasAudioSender && _localStream != null) {
        final audioTracks = _localStream!.getAudioTracks();
        if (audioTracks.isNotEmpty) {
          log('🎤 إضافة مسار صوتي محلي قبل إنشاء offer');
          await pc.addTrack(audioTracks.first, _localStream!);
        }
      }

      // إنشاء العرض مع timeout
      final offer = await pc.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': false,
        'voiceActivityDetection': true,
      }).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          log('⏰ timeout في إنشاء offer لـ $peerId');
          throw TimeoutException('timeout في إنشاء offer');
        },
      );

      // تعيين local description مع timeout
      await pc.setLocalDescription(offer).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          log('⏰ timeout في تعيين local description لـ $peerId');
          throw TimeoutException('timeout في تعيين local description');
        },
      );

      log('✅ تم إنشاء offer لـ $peerId بنجاح');

      // استدعاء callback
      _signalingCallbacks.onOfferCreated?.call(peerId, offer);

      return offer;

    } catch (e) {
      log('❌ خطأ في إنشاء offer لـ $peerId: $e');

      // في حالة الفشل، محاولة إعادة إنشاء peer connection
      try {
        log('🔄 محاولة إعادة إنشاء peer connection لـ $peerId');
        await _safeClosePeerConnection(peerId);
        await Future.delayed(const Duration(milliseconds: 500));
        await createPeerConnectionForPeer(peerId);

        // محاولة إنشاء offer مرة أخرى
        final pc = _peers[peerId]!;
        final retryOffer = await pc.createOffer({
          'offerToReceiveAudio': true,
          'offerToReceiveVideo': false,
        });

        await pc.setLocalDescription(retryOffer);
        _signalingCallbacks.onOfferCreated?.call(peerId, retryOffer);

        log('✅ تم إنشاء offer لـ $peerId بعد إعادة الإنشاء');
        return retryOffer;

      } catch (retryError) {
        log('❌ فشل إعادة المحاولة لإنشاء offer لـ $peerId: $retryError');
        rethrow;
      }
    }
  }

// تحسين دالة createAnswer
  Future<RTCSessionDescription> createAnswer(String peerId) async {
    try {
      log('📥 بدء إنشاء answer لـ $peerId');

      final pc = _peers[peerId];
      if (pc == null) {
        throw Exception('لا يوجد peer connection للمعرف $peerId');
      }

      // التحقق من حالة signaling
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

      // التحقق من وجود مسارات صوتية محلية
      final senders = await pc.getSenders();
      bool hasAudioSender = senders.any((sender) => sender.track?.kind == 'audio');

      if (!hasAudioSender && _localStream != null) {
        final audioTracks = _localStream!.getAudioTracks();
        if (audioTracks.isNotEmpty) {
          log('🎤 إضافة مسار صوتي محلي قبل إنشاء answer');
          await pc.addTrack(audioTracks.first, _localStream!);
        }
      }

      // إنشاء الإجابة مع timeout
      final answer = await pc.createAnswer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': false,
        'voiceActivityDetection': true,
      }).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          log('⏰ timeout في إنشاء answer لـ $peerId');
          throw TimeoutException('timeout في إنشاء answer');
        },
      );

      // تعيين local description
      await pc.setLocalDescription(answer).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          log('⏰ timeout في تعيين local description للإجابة لـ $peerId');
          throw TimeoutException('timeout في تعيين local description');
        },
      );

      log('✅ تم إنشاء answer لـ $peerId بنجاح');

      // استدعاء callback
      _signalingCallbacks.onAnswerCreated?.call(peerId, answer);

      return answer;

    } catch (e) {
      log('❌ خطأ في إنشاء answer لـ $peerId: $e');
      rethrow;
    }
  }

// دالة محسنة لإدارة setRemoteDescription
  Future<void> setRemoteDescription(String peerId, RTCSessionDescription description) async {
    try {
      log('📝 تعيين remote description لـ $peerId - النوع: ${description.type}');

      RTCPeerConnection? pc = _peers[peerId];

      // إنشاء peer connection إذا لم يكن موجوداً
      if (pc == null) {
        log('⚠️ لا يوجد peer connection لـ $peerId، إنشاء جديد...');
        pc = await createPeerConnectionForPeer(peerId);
      }

      // التحقق من الحالة الحالية
      final currentSignalingState = await pc.getSignalingState();
      log('📡 الحالة الحالية لـ $peerId: $currentSignalingState');

      // التحقق من التوافق مع نوع الوصف
      if (description.type == 'offer') {
        if (currentSignalingState != RTCSignalingState.RTCSignalingStateStable) {
          log('⚠️ حالة signaling غير مناسبة للـ offer: $currentSignalingState');

          // إعادة تعيين الاتصال إذا كان في حالة غير مناسبة
          await _resetPeerConnection(peerId);
          pc = _peers[peerId]!;
        }
      } else if (description.type == 'answer') {
        if (currentSignalingState != RTCSignalingState.RTCSignalingStateHaveLocalOffer) {
          log('⚠️ حالة signaling غير مناسبة للـ answer: $currentSignalingState');
          // في هذه الحالة، قد نحتاج لإعادة إرسال offer
          return;
        }
      }

      // تعيين remote description مع timeout
      await pc.setRemoteDescription(description).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          log('⏰ timeout في تعيين remote description لـ $peerId');
          throw TimeoutException('timeout في تعيين remote description');
        },
      );

      log('✅ تم تعيين remote description لـ $peerId');

      // معالجة خاصة حسب نوع الوصف
      if (description.type == 'offer') {
        // انتظار قصير ثم إنشاء إجابة
        await Future.delayed(const Duration(milliseconds: 200));
        await createAnswer(peerId);

      } else if (description.type == 'answer') {
        // التحقق من الحالة النهائية
        await Future.delayed(const Duration(milliseconds: 300));
        final finalState = await pc.getSignalingState();

        if (finalState == RTCSignalingState.RTCSignalingStateStable) {
          log('✅ تم تأسيس اتصال مستقر مع $peerId');

          // معالجة ICE candidates المؤجلة
          await Future.delayed(const Duration(milliseconds: 200));
          _processPendingCandidates(peerId);
        }
      }

    } catch (e) {
      log('❌ خطأ في تعيين remote description لـ $peerId: $e');

      // في حالة الفشل، محاولة إعادة تأسيس الاتصال
      await Future.delayed(const Duration(seconds: 1));
      await _resetPeerConnection(peerId);

      rethrow;
    }
  }

// إضافة دالة إعادة تعيين peer connection
  Future<void> _resetPeerConnection(String peerId) async {
    try {
      log('🔄 إعادة تعيين peer connection لـ $peerId');

      // إغلاق الاتصال القديم
      await _safeClosePeerConnection(peerId);

      // انتظار قصير
      await Future.delayed(const Duration(milliseconds: 500));

      // إنشاء اتصال جديد
      await createPeerConnectionForPeer(peerId);

      log('✅ تم إعادة تعيين peer connection لـ $peerId');

    } catch (e) {
      log('❌ فشل في إعادة تعيين peer connection لـ $peerId: $e');
      rethrow;
    }
  }

// إضافة دالة معالجة candidates مؤجلة
  Future<void> _processPendingCandidates(String peerId) async {
    final candidates = _pendingCandidates[peerId];
    if (candidates == null || candidates.isEmpty) return;

    final pc = _peers[peerId];
    if (pc == null) {
      log('⚠️ لا يوجد peer connection لمعالجة candidates المؤجلة لـ $peerId');
      return;
    }

    log('📋 معالجة ${candidates.length} ICE candidates مؤجلة لـ $peerId');

    int successCount = 0;
    for (int i = 0; i < candidates.length; i++) {
      try {
        await pc.addCandidate(candidates[i]);
        successCount++;

        // تأخير صغير بين candidates
        if (i < candidates.length - 1) {
          await Future.delayed(const Duration(milliseconds: 100));
        }

      } catch (e) {
        log('❌ فشل في إضافة candidate مؤجل ${i + 1} لـ $peerId: $e');
      }
    }

    // مسح candidates المعالجة
    _pendingCandidates.remove(peerId);
    log('✅ تم معالجة $successCount/${candidates.length} candidates مؤجلة لـ $peerId');
  }

}