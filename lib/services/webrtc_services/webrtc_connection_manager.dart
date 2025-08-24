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
      // 🔥 إصلاح تسرب الذاكرة: تنظيف أي اتصال سابق
      if (peers.containsKey(peerId)) {
        log('🧹 تنظيف peer connection سابق لـ $peerId لتجنب تسرب الذاكرة');
        await _cleanupExistingConnection(peerId);
      }
      // 🔥 إعدادات محسنة وموثوقة مع TURN servers محدثة وآمنة للذاكرة
      final Map<String, dynamic> configuration = {
        'iceServers': [
          // STUN servers موثوقة وسريعة
          {'urls': 'stun:stun.l.google.com:19302'},
          {'urls': 'stun:stun1.l.google.com:19302'}, 
          {'urls': 'stun:stun.cloudflare.com:3478'},
          
          // TURN servers موثوقة ومحدثة (2024-2025) مع أداء محسن
          {
            'urls': [
              'turn:relay.metered.ca:80',
              'turn:relay.metered.ca:443', 
              'turns:relay.metered.ca:443'
            ],
            'username': 'dd7ce87b5d39a6ba6043b5b6',
            'credential': 'nMH0i5wRzpJfrMny',
          },
          {
            'urls': [
              'turn:global.relay.metered.ca:80',
              'turn:global.relay.metered.ca:443',
              'turns:global.relay.metered.ca:443'
            ],
            'username': 'dd7ce87b5d39a6ba6043b5b6', 
            'credential': 'nMH0i5wRzpJfrMny',
          },
          // Backup TURN server آمن ومجاني
          {
            'urls': [
              'turn:openrelay.metered.ca:80',
              'turn:openrelay.metered.ca:443'
            ],
            'username': 'openrelayproject',
            'credential': 'openrelayproject',
          },
        ],
        'sdpSemantics': 'unified-plan',
        'iceCandidatePoolSize': 10, // 🔥 تقليل pool size لتوفير الذاكرة
        'bundlePolicy': 'max-bundle',
        'rtcpMuxPolicy': 'require', 
        'iceTransportPolicy': 'all',
        // 🔥 إعدادات محسنة للأداء وتوفير الذاكرة
        'enableDtlsSrtp': true,
        'enableRtpDataChannel': false,
        'continualGatheringPolicy': 'gather_continually',
        'iceConnectionReceivingTimeout': 20000, // 🔥 تقليل timeout لتوفير الموارد
        'iceBackupCandidatePairPingInterval': 5000, // 🔥 تقليل تكرار ping
        // إعدادات إضافية لتحسين الاستقرار
        'iceInactiveTimeout': 30000,
        'enableImplicitRollback': true,
        'enableCpuAdaptation': false, // توفير موارد المعالج
        'maxBitrate': 32000, // 🔥 تحديد أقصى bitrate للصوت
      };

      log('🔧 إنشاء peer connection لـ $peerId مع إعدادات محسنة');
      final pc = await createPeerConnection(configuration);

      // إعداد معالجات الأحداث قبل إضافة المسارات
      _setupPeerConnectionHandlers(pc, peerId, signalingCallbacks);

      // إضافة المسارات الصوتية المحلية مع معالجة محسنة للأخطاء
      try {
        await _audioManager.addLocalTracksToConnection(pc, peerId);
      } catch (addTrackError) {
        log('⚠️ خطأ في إضافة المسارات الصوتية لـ $peerId: $addTrackError');
        // نتابع بدون المسارات الصوتية في الوقت الحالي
        // سيتم إضافتها لاحقاً عند إنشاء offer/answer
      }

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

// دالة محسنة لإضافة ICE candidate مع معالجة محسنة للتوقيت
  Future<void> addIceCandidate(String peerId, RTCIceCandidate candidate) async {
    try {
      final pc = peers[peerId];
      if (pc == null) {
        log('⚠️ لا يوجد peer connection لـ $peerId، تأجيل ICE candidate');
        _addPendingCandidate(peerId, candidate);
        return;
      }

      // التحقق من حالة الـ signaling والاتصال
      final signalingState = await pc.getSignalingState();
      final connectionState = await pc.getConnectionState();
      final iceState = await pc.getIceConnectionState();
      final remoteDesc = await pc.getRemoteDescription();
      
      // تحقق أشمل من صحة الاتصال
      final isConnectionHealthy = connectionState != RTCPeerConnectionState.RTCPeerConnectionStateClosed &&
                                 connectionState != RTCPeerConnectionState.RTCPeerConnectionStateFailed &&
                                 iceState != RTCIceConnectionState.RTCIceConnectionStateClosed &&
                                 iceState != RTCIceConnectionState.RTCIceConnectionStateFailed;
      
      if (!isConnectionHealthy) {
        log('❌ اتصال غير صحي لـ $peerId - حالة: $connectionState, ICE: $iceState');
        _addPendingCandidate(peerId, candidate);
        return;
      }
      
      // شروط محسنة ومرنة أكثر لإضافة ICE candidate
      final canAddCandidate = remoteDesc != null;
      
      // إذا كان signaling state غير مناسب ولكن الاتصال صحي، نحاول الإضالة مع تأخير قصير
      if (!canAddCandidate) {
        log('⚠️ لا يمكن إضافم ICE candidate الآن لـ $peerId (signaling: $signalingState, remoteDesc: ${remoteDesc != null})');
        _addPendingCandidate(peerId, candidate);
        
        // محاولة معالجة بعد تأخير قصير جداً
        Future.delayed(const Duration(milliseconds: 300), () {
          _processPendingCandidates(peerId);
        });
        return;
      }
      
      // محاولة إضافة فورية مع معالجة للأخطاء
      try {
        await _addCandidateWithRetry(pc, candidate, peerId);
        log('✅ تم إضافة ICE candidate لـ $peerId فوراً (حالة: $signalingState)');
      } catch (immediateError) {
        // إذا فشلت الإضافة الفورية، نؤجل مع تسجيل الخطأ
        log('⚠️ فشلت الإضافة الفورية لـ $peerId: $immediateError - تأجيل');
        _addPendingCandidate(peerId, candidate);
        
        // جدولة معالجة بعد وقت قصير جداً
        Future.delayed(const Duration(milliseconds: 200), () {
          _processPendingCandidates(peerId);
        });
      }

    } catch (e) {
      log('❌ خطأ عام في معالجة ICE candidate لـ $peerId: $e');
      _addPendingCandidate(peerId, candidate);
      
      // جدولة معالجة بعد تأخير إضافي
      Future.delayed(const Duration(milliseconds: 500), () {
        _processPendingCandidates(peerId);
      });
    }
  }

  // دالة مساعدة لإضافة candidate مع إعادة محاولة
  Future<void> _addCandidateWithRetry(RTCPeerConnection pc, RTCIceCandidate candidate, String peerId) async {
    int retries = 0;
    const maxRetries = 3;
    
    while (retries < maxRetries) {
      try {
        await pc.addCandidate(candidate).timeout(const Duration(seconds: 5));
        return; // نجح
      } catch (e) {
        retries++;
        if (retries >= maxRetries) {
          log('❌ فشل إضافة ICE candidate لـ $peerId بعد $maxRetries محاولات: $e');
          rethrow;
        }
        
        log('⚠️ فشل إضافة ICE candidate لـ $peerId (محاولة $retries/$maxRetries): $e');
        await Future.delayed(Duration(milliseconds: 200 * retries)); // تأخير متدرج
      }
    }
  }

// معالجة محسنة للـ candidates المؤجلة مع إدارة أفضل للتوقيت
  Future<void> _processPendingCandidates(String peerId) async {
    final candidates = pendingCandidates[peerId];
    if (candidates == null || candidates.isEmpty) return;

    final pc = peers[peerId];
    if (pc == null) {
      log('⚠️ لا يوجد peer connection لمعالجة candidates المؤجلة لـ $peerId');
      return;
    }

    try {
      // التحقق من الحالة
      final signalingState = await pc.getSignalingState();
      final remoteDesc = await pc.getRemoteDescription();
      final iceState = await pc.getIceConnectionState();

      // شروط محسنة للمعالجة
      final canProcess = remoteDesc != null &&
          (signalingState == RTCSignalingState.RTCSignalingStateStable ||
           signalingState == RTCSignalingState.RTCSignalingStateHaveRemoteOffer) &&
          (iceState != RTCIceConnectionState.RTCIceConnectionStateClosed &&
           iceState != RTCIceConnectionState.RTCIceConnectionStateFailed);

      if (!canProcess) {
        log('⚠️ الشروط غير مناسبة لمعالجة candidates المؤجلة لـ $peerId');
        log('   SignalingState: $signalingState, RemoteDesc: ${remoteDesc != null}, IceState: $iceState');
        
        // إعادة جدولة إذا كانت الحالة قابلة للإصلاح
        if (iceState != RTCIceConnectionState.RTCIceConnectionStateClosed) {
          Future.delayed(const Duration(milliseconds: 1500), () {
            _processPendingCandidates(peerId);
          });
        }
        return;
      }

      log('📋 معالجة ${candidates.length} ICE candidates مؤجلة لـ $peerId');

      int successCount = 0;
      final candidatesToRemove = <RTCIceCandidate>[];

      // معالجة المجموعات (batch processing)
      const batchSize = 3;
      for (int i = 0; i < candidates.length; i += batchSize) {
        final batch = candidates.skip(i).take(batchSize).toList();
        
        await Future.wait(
          batch.map((candidate) async {
            try {
              await pc.addCandidate(candidate).timeout(const Duration(seconds: 3));
              successCount++;
              candidatesToRemove.add(candidate);
              log('✅ تم إضافة candidate مؤجل ${successCount} لـ $peerId');
            } catch (e) {
              log('❌ فشل في إضافة candidate مؤجل لـ $peerId: $e');
            }
          }),
        );

        // تأخير صغير بين المجموعات
        if (i + batchSize < candidates.length) {
          await Future.delayed(const Duration(milliseconds: 200));
        }
      }

      // إزالة candidates المعالجة بنجاح
      candidates.removeWhere((c) => candidatesToRemove.contains(c));
      
      if (candidates.isEmpty) {
        pendingCandidates.remove(peerId);
        log('🗑️ تم مسح جميع candidates المؤجلة لـ $peerId (نجح: $successCount)');
      } else {
        log('📋 باقي ${candidates.length} candidates مؤجلة لـ $peerId (نجح: $successCount)');
      }

    } catch (e) {
      log('❌ خطأ في معالجة candidates المؤجلة لـ $peerId: $e');
    }
  }

// تحسين إعداد معالجات الأحداث
  void _setupPeerConnectionHandlers(
      RTCPeerConnection pc,
      String peerId,
      WebRTCSignalingCallbacks signalingCallbacks,
      ) {
    // معالجة ICE candidates محسنة مع تصفية وتوقيت أفضل
    pc.onIceCandidate = (RTCIceCandidate candidate) {
      // تحسين فلترة ICE candidates
      if (candidate.candidate != null &&
          candidate.candidate!.isNotEmpty &&
          !candidate.candidate!.contains('0.0.0.0') &&
          !candidate.candidate!.contains('candidate:')) {
        
        // تأجيل الإرسال قليلاً لتجميع candidates
        Future.delayed(const Duration(milliseconds: 100), () {
          log('🧊 إرسال ICE candidate للـ peer $peerId');
          signalingCallbacks.onIceCandidateGenerated?.call(peerId, candidate);
        });
      } else if (candidate.candidate != null && 
                 candidate.candidate!.isNotEmpty &&
                 candidate.candidate!.contains('candidate:')) {
        // إرسال ICE candidate عادي فوراً
        log('🧊 ICE candidate عادي للـ peer $peerId');
        signalingCallbacks.onIceCandidateGenerated?.call(peerId, candidate);
      } else {
        log('⚠️ تم تجاهل ICE candidate غير صالح لـ $peerId: ${candidate.candidate}');
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
        case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
          log('🔴 تم إغلاق الاتصال مع $peerId');
          // 🔥 تنظيف فوري عند الإغلاق لتجنب تسرب الذاكرة
          _immediateCleanup(peerId);
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
          log('🔄 جاري الاتصال مع $peerId');
          break;
        default:
          break;
      }
    };

    // معالجة ICE connection state محسنة مع إعادة محاولة ذكية
    pc.onIceConnectionState = (RTCIceConnectionState state) {
      log('🧊 حالة ICE مع $peerId: $state');

      switch (state) {
        case RTCIceConnectionState.RTCIceConnectionStateConnected:
        case RTCIceConnectionState.RTCIceConnectionStateCompleted:
          log('🎉 تم تأسيس اتصال ICE مع $peerId');
          // معالجة candidates مؤجلة عند الاتصال
          Future.delayed(const Duration(milliseconds: 300), () {
            _processPendingCandidates(peerId);
          });
          break;
        case RTCIceConnectionState.RTCIceConnectionStateFailed:
          log('❌ فشل ICE connection مع $peerId - محاولة إصلاح');
          _handleIceFailureWithRetry(peerId, pc);
          break;
        case RTCIceConnectionState.RTCIceConnectionStateDisconnected:
          log('⚠️ انقطع ICE connection مع $peerId - إعادة محاولة');
          _handleIceDisconnection(peerId, pc);
          break;
        case RTCIceConnectionState.RTCIceConnectionStateClosed:
          log('🔴 تم إغلاق ICE connection مع $peerId');
          // 🔥 تنظيف فوري عند إغلاق ICE لتجنب تسرب الذاكرة
          _immediateCleanup(peerId);
          break;
        case RTCIceConnectionState.RTCIceConnectionStateChecking:
          log('🔍 فحص ICE candidates مع $peerId');
          // إضافة timeout للفحص
          Future.delayed(const Duration(seconds: 15), () async {
            try {
              final currentState = await pc.getIceConnectionState();
              if (currentState == RTCIceConnectionState.RTCIceConnectionStateChecking) {
                log('⏰ انتهت مهلة فحص ICE لـ $peerId - إعادة تشغيل');
                await pc.restartIce();
              }
            } catch (e) {
              log('❌ خطأ في timeout فحص ICE لـ $peerId: $e');
            }
          });
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

    // إضافة معالج ICE gathering state لتحسين عملية جمع candidates
    pc.onIceGatheringState = (RTCIceGatheringState state) {
      log('🧊 حالة جمع ICE candidates مع $peerId: $state');
      
      switch (state) {
        case RTCIceGatheringState.RTCIceGatheringStateGathering:
          log('🔍 بدء جمع ICE candidates لـ $peerId');
          break;
        case RTCIceGatheringState.RTCIceGatheringStateComplete:
          log('✅ انتهاء جمع ICE candidates لـ $peerId');
          // معالجة أي candidates مؤجلة بعد انتهاء الجمع
          Future.delayed(const Duration(milliseconds: 500), () {
            _processPendingCandidates(peerId);
          });
          break;
        default:
          break;
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

  // معالج فشل ICE محسن مع إعادة محاولة ذكية
  Future<void> _handleIceFailureWithRetry(String peerId, RTCPeerConnection pc) async {
    log('🛠️ معالجة فشل ICE لـ $peerId');
    
    try {
      // محاولة إعادة تشغيل ICE أولاً
      await pc.restartIce();
      log('🔄 تم إعادة تشغيل ICE لـ $peerId');
      
      // انتظار 3 ثوان لمعرفة النتيجة
      await Future.delayed(const Duration(seconds: 3));
      
      final currentState = await pc.getIceConnectionState();
      if (currentState == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        log('❌ فشل إعادة تشغيل ICE، إعادة إنشاء الاتصال لـ $peerId');
        await _retryConnection(peerId);
      }
    } catch (e) {
      log('❌ خطأ في معالجة فشل ICE لـ $peerId: $e');
      await _retryConnection(peerId);
    }
  }

  // معالج انقطاع ICE
  Future<void> _handleIceDisconnection(String peerId, RTCPeerConnection pc) async {
    log('🔌 معالجة انقطاع ICE لـ $peerId');
    
    // انتظار قصير لمعرفة إذا كان مؤقتاً
    await Future.delayed(const Duration(seconds: 2));
    
    try {
      final currentState = await pc.getIceConnectionState();
      if (currentState == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
        log('🔄 لا يزال منقطع، محاولة إعادة الاتصال لـ $peerId');
        await pc.restartIce();
      }
    } catch (e) {
      log('❌ خطأ في معالجة انقطاع ICE لـ $peerId: $e');
    }
  }

  // إغلاق اتصال peer محدد
  Future<void> closePeerConnection(String peerId) async {
    try {
      final pc = peers[peerId];
      if (pc != null) {
        log('🔴 إغلاق peer connection لـ $peerId');
        
        // إغلاق آمن مع معالجة الأخطاء
        try {
          await pc.close();
        } catch (closeError) {
          log('⚠️ خطأ أثناء إغلاق peer connection لـ $peerId: $closeError');
        }
        
        // تنظيف شامل
        await _immediateCleanup(peerId);
        log('✅ تم إغلاق وتنظيف الاتصال مع $peerId');
      }
    } catch (e) {
      log('❌ خطأ في إغلاق الاتصال مع $peerId: $e');
      // تنظيف قسري حتى في حالة الخطأ
      await _forceCleanup(peerId);
    }
  }

  // إضافة candidate مؤجل مع إدارة محسنة
  void _addPendingCandidate(String peerId, RTCIceCandidate candidate) {
    pendingCandidates[peerId] ??= [];
    
    // تجنب إضافة candidates مكررة
    final existingCandidate = pendingCandidates[peerId]!.any(
      (c) => c.candidate == candidate.candidate && 
             c.sdpMid == candidate.sdpMid && 
             c.sdpMLineIndex == candidate.sdpMLineIndex
    );
    
    if (!existingCandidate) {
      pendingCandidates[peerId]!.add(candidate);
      log('📋 تم تأجيل ICE candidate لـ $peerId (المجموع: ${pendingCandidates[peerId]!.length})');
      
      // محاولة المعالجة بعد تأخير متدرج
      final delayMs = pendingCandidates[peerId]!.length <= 3 ? 1000 : 2000;
      Future.delayed(Duration(milliseconds: delayMs), () {
        _processPendingCandidates(peerId);
      });
    } else {
      log('⚠️ تجاهل ICE candidate مكرر لـ $peerId');
    }
    
    // تنظيف الـ candidates القديمة جداً (أكثر من 20)
    if (pendingCandidates[peerId]!.length > 20) {
      pendingCandidates[peerId]!.removeRange(0, 10);
      log('🧹 تنظيف candidates قديمة لـ $peerId');
    }
  }

  // إعادة محاولة الاتصال
  Future<void> _retryConnection(String peerId) async {
    try {
      log('🔄 إعادة محاولة الاتصال مع $peerId');

      // إغلاق الاتصال الحالي بشكل آمن
      await closePeerConnection(peerId);

      // انتظار لضمان التنظيف
      await Future.delayed(const Duration(seconds: 2));

      // إنشاء اتصال جديد
      await createPeerConnectionForPeer(peerId, WebRTCSignalingCallbacks());
      await createOffer(peerId, WebRTCSignalingCallbacks());

      log('✅ تمت إعادة محاولة الاتصال مع $peerId');
    } catch (e) {
      log('❌ فشل في إعادة محاولة الاتصال مع $peerId: $e');
      // تنظيف قسري في حالة الفشل
      await _forceCleanup(peerId);
    }
  }

  // 🔥 دالة تنظيف شاملة لتجنب تسرب الذاكرة
  Future<void> _cleanupExistingConnection(String peerId) async {
    try {
      final pc = peers[peerId];
      if (pc != null) {
        log('🧹 تنظيف اتصال موجود لـ $peerId');
        
        // إيقاف جميع معالجات الأحداث
        pc.onIceCandidate = null;
        pc.onTrack = null;
        pc.onConnectionState = null;
        pc.onIceConnectionState = null;
        pc.onSignalingState = null;
        pc.onIceGatheringState = null;
        
        // إغلاق الاتصال
        try {
          await pc.close();
        } catch (e) {
          log('⚠️ خطأ أثناء إغلاق peer connection قديم: $e');
        }
      }
      
      // تنظيف الخرائط
      await _immediateCleanup(peerId);
      
    } catch (e) {
      log('❌ خطأ في تنظيف الاتصال الموجود لـ $peerId: $e');
      await _forceCleanup(peerId);
    }
  }

  // 🔥 تنظيف فوري للموارد
  Future<void> _immediateCleanup(String peerId) async {
    try {
      // إزالة من جميع الخرائط
      peers.remove(peerId);
      remoteStreams.remove(peerId);
      pendingCandidates.remove(peerId);
      
      log('🧹 تم تنظيف موارد $peerId من الذاكرة');
    } catch (e) {
      log('❌ خطأ في التنظيف الفوري لـ $peerId: $e');
    }
  }

  // 🔥 تنظيف قسري في حالة الأخطاء
  Future<void> _forceCleanup(String peerId) async {
    try {
      log('🚨 تنظيف قسري لـ $peerId');
      
      // تنظيف جميع الموارد بدون استثناءات
      peers.remove(peerId);
      remoteStreams.remove(peerId);
      pendingCandidates.remove(peerId);
      
      // محاولة إجبار garbage collection
      await Future.delayed(const Duration(milliseconds: 100));
      
      log('✅ تم التنظيف القسري لـ $peerId');
    } catch (e) {
      log('❌ خطأ في التنظيف القسري: $e');
    }
  }

  // 🔥 تنظيف جميع الاتصالات (استخدام عند إغلاق التطبيق)
  Future<void> cleanupAllConnections() async {
    log('🧹 بدء تنظيف جميع الاتصالات');
    
    final allPeerIds = List<String>.from(peers.keys);
    
    for (final peerId in allPeerIds) {
      try {
        await closePeerConnection(peerId);
      } catch (e) {
        log('❌ خطأ في تنظيف $peerId: $e');
        await _forceCleanup(peerId);
      }
    }
    
    // تنظيف نهائي
    peers.clear();
    remoteStreams.clear();
    pendingCandidates.clear();
    
    log('✅ تم تنظيف جميع الاتصالات بنجاح');
  }

  // دالة للتحقق من صحة ICE candidate
  bool _isValidIceCandidate(RTCIceCandidate candidate) {
    if (candidate.candidate == null || candidate.candidate!.isEmpty) {
      return false;
    }
    
    final candidateStr = candidate.candidate!;
    
    // تجاهل candidates غير صالحة
    if (candidateStr.contains('0.0.0.0') ||
        candidateStr.contains('169.254.') || // Link-local addresses
        candidateStr.contains('127.0.0.1')) { // Localhost
      return false;
    }
    
    // التأكد من وجود معلومات أساسية
    if (!candidateStr.contains('candidate:') ||
        candidate.sdpMid == null ||
        candidate.sdpMLineIndex == null) {
      return false;
    }
    
    return true;
  }

  // دالة شاملة للتشخيص وحل مشاكل ICE
  Future<void> diagnoseAndFixIceIssues(String peerId) async {
    log('🔍 بدء تشخيص مشاكل ICE لـ $peerId');
    
    try {
      final pc = peers[peerId];
      if (pc == null) {
        log('❌ لا يوجد peer connection لـ $peerId');
        return;
      }

      // فحص الحالات
      final connectionState = await pc.getConnectionState();
      final iceState = await pc.getIceConnectionState();
      final signalingState = await pc.getSignalingState();
      final remoteDesc = await pc.getRemoteDescription();
      final localDesc = await pc.getLocalDescription();

      log('📊 حالة التشخيص لـ $peerId:');
      log('   Connection: $connectionState');
      log('   ICE: $iceState');
      log('   Signaling: $signalingState');
      log('   Remote Desc: ${remoteDesc != null}');
      log('   Local Desc: ${localDesc != null}');

      // تطبيق الإصلاحات حسب المشكلة
      if (iceState == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        log('🔧 إصلاح فشل ICE لـ $peerId');
        await pc.restartIce();
        
      } else if (iceState == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
        log('🔧 إصلاح انقطاع ICE لـ $peerId');
        await pc.restartIce();
        
      } else if (iceState == RTCIceConnectionState.RTCIceConnectionStateChecking) {
        log('⏰ ICE في حالة فحص طويلة لـ $peerId، معالجة candidates مؤجلة');
        await _processPendingCandidates(peerId);
        
      } else if (connectionState == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        log('🔄 إعادة إنشاء الاتصال الكامل لـ $peerId');
        await _retryConnection(peerId);
      }

      // فحص نهائي بعد المعالجة
      Future.delayed(const Duration(seconds: 3), () async {
        final finalState = await pc.getIceConnectionState();
        log('🏁 الحالة النهائية بعد التشخيص لـ $peerId: $finalState');
      });

    } catch (e) {
      log('❌ خطأ في تشخيص مشاكل ICE لـ $peerId: $e');
    }
  }
}