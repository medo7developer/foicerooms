import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';

import '../models/game_room_model.dart';
import '../models/player_model.dart';
import '../providers/game_provider.dart';
import '../providers/game_state.dart';
import '../services/experience_service.dart';
import '../services/realtime_manager.dart';
import '../services/webrtc_services/webrtc_service.dart';
import '../services/supabase_service.dart';

import '../widgets/game/game_top_bar.dart';
import '../widgets/game/game_content.dart';
import '../widgets/game/game_bottom_controls.dart';
import '../widgets/game/game_connecting_screen.dart';
import '../widgets/game/game_screen_mixin.dart';

class GameScreen extends StatefulWidget {
  final String playerId;

  const GameScreen({super.key, required this.playerId});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with TickerProviderStateMixin, GameScreenMixin {

  late WebRTCService _webrtcService;
  late SupabaseService _supabaseService;
  late AnimationController _pulseController;
  late AnimationController _cardController;
  late RealtimeManager _realtimeManager;

  Timer? _timer;
  Timer? _roundCheckTimer;
  Timer? _connectionTimer;

  bool _isMicrophoneOn = true;
  bool _isConnecting = true;
  bool _isRealtimeConnected = false;
  bool _hasConnectedToPeers = false;

  @override
  void initState() {
    super.initState();
    _initializeServices();
    _initializeAnimations();
    _initializeGame();
  }

  void _initializeServices() {
    _webrtcService = context.read<WebRTCService>();
    _supabaseService = context.read<SupabaseService>();
    _realtimeManager = context.read<RealtimeManager>();
  }

  void _initializeAnimations() {
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();

    _cardController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
  }

  Future<void> _initializeGame() async {
    if (!mounted) return;

    try {
      _hasConnectedToPeers = false;

      log('🚀 === بدء تهيئة اللعبة المحسنة ===');

      // 1. طلب الصلاحيات أولاً
      final hasPermission = await _webrtcService.requestPermissions();
      if (!hasPermission) {
        throw Exception('صلاحيات الميكروفون مطلوبة للدردشة الصوتية');
      }

      // 2. تهيئة الصوت المحلي
      await _webrtcService.initializeLocalAudio();
      await Future.delayed(const Duration(milliseconds: 1200));
      log('✅ تم تهيئة الصوت المحلي');

      if (!mounted) return;

      // 3. إعداد الخدمات
      final gameProvider = context.read<GameProvider>();
      gameProvider.setSupabaseService(_supabaseService);

      final experienceService = ExperienceService();
      gameProvider.setExperienceService(experienceService);
      _setupGameEndListener(gameProvider, experienceService);

      _realtimeManager.registerGameProvider(gameProvider);

      // 4. **تسجيل callbacks أولاً قبل أي شيء آخر**
      log('🔧 === تسجيل WebRTC callbacks ===');
      setupWebRTCCallbacks(_webrtcService, _supabaseService, widget.playerId, context);

      // انتظار للتأكد من التسجيل
      await Future.delayed(const Duration(milliseconds: 800));

      // التحقق من التسجيل
      if (!_webrtcService.hasCallbacks) {
        log('❌ فشل تسجيل callbacks - محاولة ثانية');
        setupWebRTCCallbacks(_webrtcService, _supabaseService, widget.playerId, context);
        await Future.delayed(const Duration(milliseconds: 500));
      }

      log('✅ حالة callbacks: ${_webrtcService.hasCallbacks}');

      // 5. الاتصال بـ Realtime
      final currentRoom = gameProvider.currentRoom;
      if (currentRoom != null) {
        await _realtimeManager.subscribeToRoom(currentRoom.id, widget.playerId);
        setState(() => _isRealtimeConnected = true);
        log('✅ تم الاتصال بـ Realtime');

        // 6. تحديث البيانات وانتظار استقرارها
        await _realtimeManager.forceRefresh();
        await Future.delayed(const Duration(seconds: 2));

        // 7. الحصول على قائمة محدثة من اللاعبين المتصلين
        await _realtimeManager.forceRefresh(); // تحديث إضافي
        await Future.delayed(const Duration(milliseconds: 500));

        final updatedRoom = gameProvider.currentRoom;
        if (updatedRoom != null) {
          final connectedPlayers = updatedRoom.players
              .where((p) => p.isConnected && p.id != widget.playerId)
              .toList();

          log('🔍 اللاعبين المتصلين الفعليين: ${connectedPlayers.length}');
          for (final player in connectedPlayers) {
            log('   - ${player.name} (${player.id})');
          }

          if (connectedPlayers.isNotEmpty) {
            // 8. **إنشاء اتصالات متسلسلة مع انتظار أطول**
            await _createConnectionsSequentially(connectedPlayers);

            // 9. **انتظار استقرار الاتصالات قبل إرسال offers**
            await Future.delayed(const Duration(seconds: 4));

            // 10. **إرسال offers متسلسلة مع فترات انتظار أطول**
            await _sendOffersSequentiallyRobust(connectedPlayers);
          } else {
            log('ℹ️ لا يوجد لاعبين آخرين متصلين حالياً');
          }
        }
      }

      setState(() => _isConnecting = false);

      // 11. بدء المؤقتات والمراقبة
      _startTimers();
      _webrtcService.startConnectionHealthCheck();

      log('🎉 === انتهت تهيئة اللعبة بنجاح ===');

    } catch (e) {
      log('❌ خطأ في تهيئة اللعبة: $e');
      setState(() => _isConnecting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في تهيئة الصوت: $e'),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'إعادة المحاولة',
              onPressed: () => _initializeGame(),
            ),
          ),
        );
      }
    }
  }

// دالة إنشاء اتصالات متسلسلة محسنة:
  Future<void> _createConnectionsSequentially(List<Player> players) async {
    log('🔧 === بدء إنشاء peer connections متسلسلة ===');

    for (int i = 0; i < players.length; i++) {
      final player = players[i];

      try {
        log('🔗 إنشاء peer connection مع ${player.name} (${i + 1}/${players.length})');

        // إغلاق أي اتصال قديم أولاً
        if (_webrtcService.hasPeer(player.id)) {
          await _webrtcService.closePeerConnection(player.id);
          await Future.delayed(const Duration(milliseconds: 300));
        }

        // إنشاء اتصال جديد
        await _webrtcService.createPeerConnectionForPeer(player.id);

        // انتظار أطول للاستقرار
        await Future.delayed(const Duration(milliseconds: 1500));

        // التحقق من نجاح الإنشاء
        if (_webrtcService.hasPeer(player.id)) {
          log('✅ تم إنشاء peer connection مع ${player.name} بنجاح');
        } else {
          log('❌ فشل إنشاء peer connection مع ${player.name}');
        }

        // انتظار إضافي بين الاتصالات
        if (i < players.length - 1) {
          await Future.delayed(const Duration(milliseconds: 800));
        }

      } catch (e) {
        log('❌ خطأ في إنشاء peer connection مع ${player.id}: $e');
      }
    }

    log('✅ === انتهى إنشاء peer connections ===');
  }

// دالة إرسال offers محسنة مع مراقبة الاستجابة:
  Future<void> _sendOffersSequentiallyRobust(List<Player> players) async {
    log('📤 === بدء إرسال offers متسلسلة مع مراقبة ===');

    for (int i = 0; i < players.length; i++) {
      final player = players[i];

      try {
        log('📨 إرسال offer إلى ${player.name} (${i + 1}/${players.length})');

        // التحقق من وجود peer connection صحي
        if (!_webrtcService.hasPeer(player.id)) {
          log('⚠️ لا يوجد peer connection مع ${player.name}، إنشاء جديد');
          await _webrtcService.createPeerConnectionForPeer(player.id);
          await Future.delayed(const Duration(milliseconds: 800));
        }

        // التحقق من صحة الاتصال
        final isHealthy = await _webrtcService.isPeerConnectionHealthy(player.id);
        log('🔍 صحة peer connection مع ${player.name}: $isHealthy');

        // إرسال offer
        await _webrtcService.createOffer(player.id);
        log('✅ تم إرسال offer إلى ${player.name}');

        // **انتظار أطول لاستقبال answer**
        await Future.delayed(const Duration(seconds: 6)); // زيادة الانتظار

        // فحص حالة الاتصال بعد offer
        final healthAfterOffer = await _webrtcService.isPeerConnectionHealthy(player.id);
        log('🔍 صحة الاتصال مع ${player.name} بعد offer: $healthAfterOffer');

        if (!healthAfterOffer) {
          log('⚠️ لم يتم استقبال answer من ${player.name} - سيتم المراقبة');

        }

        // انتظار بين العروض
        if (i < players.length - 1) {
          await Future.delayed(const Duration(seconds: 2));
        }

      } catch (e) {
        log('❌ خطأ في إرسال offer إلى ${player.id}: $e');
      }
    }

    _hasConnectedToPeers = true;
    log('✅ === انتهى إرسال جميع offers ===');
  }


  void _setupGameEndListener(GameProvider gameProvider, ExperienceService experienceService) {
    // مراقبة تغييرات حالة اللعبة
    Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      final room = gameProvider.currentRoom;
      if (room != null && room.state == GameState.finished) {
        timer.cancel();

        // معالجة المكافآت عند انتهاء اللعبة
        Future.delayed(const Duration(seconds: 1), () async {
          if (mounted) {
            await _processGameEndRewards(experienceService, room);
          }
        });
      }
    });
  }

  Future<void> _processGameEndRewards(ExperienceService experienceService, GameRoom room) async {
    try {
      log('🎉 معالجة مكافآت نهاية اللعبة للاعب: ${widget.playerId}');

      // التأكد من معالجة المكافآت
      await experienceService.ensureGameRewardsProcessed(widget.playerId, room);

      // تحديث GameProvider
      final gameProvider = context.read<GameProvider>();
      await gameProvider.loadPlayerStats(widget.playerId);

      log('✅ تم الانتهاء من معالجة مكافآت نهاية اللعبة');
    } catch (e) {
      log('❌ خطأ في معالجة مكافآت نهاية اللعبة: $e');
    }
  }

  Future<void> _connectToOtherPlayersEnhanced(List<Player> players) async {
    if (_hasConnectedToPeers) return;

    try {
      final connectedPlayers = players
          .where((p) => p.isConnected && p.id != widget.playerId)
          .toList();

      if (connectedPlayers.isEmpty) {
        log('لا يوجد لاعبون آخرون متصلون للاتصال بهم');
        return;
      }

      log('🚀 بدء الاتصال المحسن بـ ${connectedPlayers.length} لاعبين');

      // **المشكلة هنا: تم تعيين callbacks لكن لم يتم استخدامها!**
      // إعادة تعيين callbacks قبل بدء الاتصالات
      log('🔧 إعادة تعيين WebRTC callbacks...');
      setupWebRTCCallbacks(_webrtcService, _supabaseService, widget.playerId, context);

      // **تنظيف أي اتصالات سابقة أولاً**
      for (final player in connectedPlayers) {
        if (_webrtcService.hasPeer(player.id)) {
          log('🗑️ تنظيف اتصال سابق مع ${player.id}');
          await _webrtcService.closePeerConnection(player.id);
          await Future.delayed(const Duration(milliseconds: 300));
        }
      }

      // **إنشاء جميع peer connections جديدة مع انتظار أطول**
      for (final player in connectedPlayers) {
        try {
          log('🔧 إنشاء peer connection جديد مع ${player.name}');
          await _webrtcService.createPeerConnectionForPeer(player.id);

          // انتظار أطول لضمان الاستقرار
          await Future.delayed(const Duration(milliseconds: 1000));
          log('✅ تم إنشاء peer connection مع ${player.id}');
        } catch (e) {
          log('❌ خطأ في إنشاء peer connection مع ${player.id}: $e');
        }
      }

      // **انتظار استقرار الاتصالات - زيادة الوقت**
      await Future.delayed(const Duration(seconds: 3));

      // **إرسال offers واحد تلو الآخر مع تحقق**
      for (int i = 0; i < connectedPlayers.length; i++) {
        final player = connectedPlayers[i];

        try {
          log('📤 إنشاء offer لـ ${player.name} (${i + 1}/${connectedPlayers.length})');

          if (_webrtcService.hasPeer(player.id)) {
            // **التحقق من حالة الـ peer قبل الإرسال**
            final isHealthy = await _webrtcService.isPeerConnectionHealthy(player.id);
            log('🔍 حالة الـ peer ${player.id}: $isHealthy');

            await _webrtcService.createOffer(player.id);
            log('✅ تم إرسال offer إلى ${player.id}');

            // انتظار أطول بين العروض
            if (i < connectedPlayers.length - 1) {
              await Future.delayed(const Duration(seconds: 4)); // زيادة الانتظار
            }
          }

        } catch (e) {
          log('❌ خطأ في إرسال offer إلى ${player.id}: $e');
        }
      }

      _hasConnectedToPeers = true;
      log('✅ تم الانتهاء من إرسال جميع العروض');

    } catch (e) {
      log('❌ خطأ عام في الاتصال: $e');
    }
  }

// دالة تشخيص مفصلة جديدة
  Future<void> _performDetailedDiagnostics() async {
    try {
      log('🔍 === بدء التشخيص المفصل ===');

      final gameProvider = context.read<GameProvider>();
      final connectedPlayers = gameProvider.currentRoom?.players
          .where((p) => p.isConnected && p.id != widget.playerId)
          .toList() ?? [];

      log('👥 عدد اللاعبين المتصلين: ${connectedPlayers.length}');

      for (final player in connectedPlayers) {
        final hasPeer = _webrtcService.hasPeer(player.id);
        final hasStream = _webrtcService.getRemoteStream(player.id) != null;
        final isHealthy = _webrtcService.isPeerHealthy(player.id);

        log('🔍 ${player.name}:');
        log('   📡 Has Peer: $hasPeer');
        log('   🎵 Has Stream: $hasStream');
        log('   💚 Is Healthy: $isHealthy');

        if (!isHealthy && hasPeer) {
          log('🔧 محاولة إصلاح الاتصال مع ${player.id}');
          try {
            await _webrtcService.restartFailedConnections();
          } catch (e) {
            log('❌ فشل إصلاح الاتصال: $e');
          }
        }
      }

      // فحص الصوت المحلي
      final localStream = _webrtcService.localStream;
      if (localStream != null) {
        final audioTracks = localStream.getAudioTracks();
        log('🎤 مسارات صوتية محلية: ${audioTracks.length}');

        for (final track in audioTracks) {
          log('   🎵 Track ${track.id}: enabled=${track.enabled}');        }
      } else {
        log('❌ لا يوجد مجرى صوتي محلي!');
      }

      log('🔍 === انتهاء التشخيص المفصل ===');

    } catch (e) {
      log('❌ خطأ في التشخيص المفصل: $e');
    }
  }

// التعديل الرابع: إضافة هذه الدوال في game_screen.dart:

// تحديث دالة _scheduleDelayedDiagnostics لتشمل فحصاً أكثر تفصيلاً:
  void _scheduleDelayedDiagnostics() {
    // فحص أولي سريع بعد 3 ثوان
    Future.delayed(const Duration(seconds: 3), () async {
      if (mounted) {
        log('🔍 === فحص أولي سريع ===');
        await _performQuickHealthCheck();
      }
    });

    // فحص متوسط بعد 7 ثوان
    Future.delayed(const Duration(seconds: 7), () async {
      if (mounted) {
        log('🔍 === فحص متوسط وإصلاحات ===');
        await _webrtcService.checkAndFixLateConnections();
        await _webrtcService.verifyAudioInAllConnections();
      }
    });

    // فحص شامل بعد 12 ثانية
    Future.delayed(const Duration(seconds: 12), () async {
      if (mounted) {
        log('🔍 === فحص شامل نهائي ===');
        await _performComprehensiveCheck();
      }
    });

    // فحص دوري كل 20 ثانية بعد ذلك
    Timer.periodic(const Duration(seconds: 20), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      _performPeriodicHealthCheck();
    });
  }

// دالة فحص سريع للحالة
  Future<void> _performQuickHealthCheck() async {
    try {
      final gameProvider = context.read<GameProvider>();
      final connectedPlayers = gameProvider.currentRoom?.players
          .where((p) => p.isConnected && p.id != widget.playerId)
          .toList() ?? [];

      log('⚡ فحص سريع: ${connectedPlayers.length} لاعبين متصلين');

      for (final player in connectedPlayers) {
        final hasPeer = _webrtcService.hasPeer(player.id);
        final hasRemoteStream = _webrtcService.getRemoteStream(player.id) != null;

        log('   ${player.name}: Peer=$hasPeer, Stream=$hasRemoteStream');

        // إذا لم يكن هناك peer connection، إنشاؤه
        if (!hasPeer) {
          log('🔧 إنشاء peer connection مفقود مع ${player.name}');
          try {
            await _webrtcService.createPeerConnectionForPeer(player.id);
            await Future.delayed(const Duration(milliseconds: 500));
            await _webrtcService.createOffer(player.id);
          } catch (e) {
            log('❌ فشل في إنشاء peer connection مع ${player.id}: $e');
          }
        }
      }

      // فحص الصوت المحلي
      final localTracks = _webrtcService.localStream?.getAudioTracks().length ?? 0;
      log('🎤 مسارات صوتية محلية: $localTracks');

      if (localTracks == 0) {
        log('⚠️ لا توجد مسارات صوتية محلية - إعادة التهيئة');
        await _webrtcService.initializeLocalAudio();
      }

    } catch (e) {
      log('❌ خطأ في الفحص السريع: $e');
    }
  }

// دالة فحص شامل متقدم
  Future<void> _performComprehensiveCheck() async {
    try {
      log('🔍 === بدء الفحص الشامل ===');

      // 1. إحصائيات عامة
      final stats = await _webrtcService.getDetailedStats();
      log('📊 إحصائيات WebRTC: $stats');

      // 2. فحص كل peer connection
      final gameProvider = context.read<GameProvider>();
      final connectedPlayers = gameProvider.currentRoom?.players
          .where((p) => p.isConnected && p.id != widget.playerId)
          .toList() ?? [];

      int healthyConnections = 0;
      int totalConnections = connectedPlayers.length;

      for (final player in connectedPlayers) {
        final status = _webrtcService.getConnectionStatus(player.id);
        final isHealthy = await _webrtcService.isPeerConnectionHealthy(player.id);

        log('🔍 ${player.name}: status=$status, healthy=$isHealthy');

        if (isHealthy) {
          healthyConnections++;
        } else {
          log('🔧 محاولة إصلاح اتصال ${player.name}');
          await _attemptConnectionRepair(player.id);
        }
      }

      log('📈 اتصالات صحية: $healthyConnections/$totalConnections');

      // 3. تقرير نهائي
      final localTracks = _webrtcService.localStream?.getAudioTracks().length ?? 0;
      final remoteTracks = _webrtcService.remoteStreams.length;

      log('🎵 === تقرير الصوت النهائي ===');
      log('   🎤 مسارات محلية: $localTracks');
      log('   🔊 مجاري بعيدة: $remoteTracks');
      log('   📡 اتصالات صحية: $healthyConnections/$totalConnections');

      if (healthyConnections > 0 && localTracks > 0) {
        log('🎉 الدردشة الصوتية تعمل بشكل صحيح!');
      } else {
        log('⚠️ توجد مشاكل في الدردشة الصوتية');

        // محاولة إصلاح شاملة
        await _performEmergencyFix();
      }

    } catch (e) {
      log('❌ خطأ في الفحص الشامل: $e');
    }
  }

// دالة إصلاح اتصال واحد
  Future<void> _attemptConnectionRepair(String peerId) async {
    try {
      log('🔧 محاولة إصلاح اتصال $peerId');

      // 1. فحص صحة الاتصال
      final isHealthy = await _webrtcService.isPeerConnectionHealthy(peerId);
      if (isHealthy) {
        log('✅ الاتصال مع $peerId صحي فعلاً');
        return;
      }

      // 2. محاولة إعادة تشغيل ICE
      if (_webrtcService.hasPeer(peerId)) {
        log('🔄 إعادة تشغيل ICE لـ $peerId');
        try {
          // الحصول على peer connection وإعادة تشغيل ICE
          // هذا يتطلب إضافة دالة في WebRTCService
          await _webrtcService.restartPeerIce(peerId);

          // انتظار وفحص مرة أخرى
          await Future.delayed(const Duration(seconds: 2));

          final fixedHealthy = await _webrtcService.isPeerConnectionHealthy(peerId);
          if (fixedHealthy) {
            log('✅ تم إصلاح الاتصال مع $peerId عبر ICE restart');
            return;
          }
        } catch (e) {
          log('⚠️ فشل ICE restart لـ $peerId: $e');
        }
      }

      // 3. إعادة إنشاء الاتصال كملاذ أخير
      log('🔄 إعادة إنشاء اتصال كامل مع $peerId');
      await _webrtcService.closePeerConnection(peerId);
      await Future.delayed(const Duration(milliseconds: 1000));

      await _webrtcService.createPeerConnectionForPeer(peerId);
      await Future.delayed(const Duration(milliseconds: 500));
      await _webrtcService.createOffer(peerId);

      log('✅ تمت إعادة إنشاء الاتصال مع $peerId');

    } catch (e) {
      log('❌ فشل في إصلاح اتصال $peerId: $e');
    }
  }

// دالة الإصلاح الطارئ
  Future<void> _performEmergencyFix() async {
    try {
      log('🚨 بدء الإصلاح الطارئ للدردشة الصوتية');

      // 1. إعادة تهيئة الصوت المحلي
      log('🎤 إعادة تهيئة الصوت المحلي');
      try {
        await _webrtcService.initializeLocalAudio();
        await Future.delayed(const Duration(seconds: 1));
      } catch (e) {
        log('❌ فشل في إعادة تهيئة الصوت المحلي: $e');
      }

      // 2. إعادة إنشاء جميع الاتصالات
      final gameProvider = context.read<GameProvider>();
      final connectedPlayers = gameProvider.currentRoom?.players
          .where((p) => p.isConnected && p.id != widget.playerId)
          .toList() ?? [];

      log('🔄 إعادة إنشاء ${connectedPlayers.length} اتصالات');

      for (final player in connectedPlayers) {
        try {
          // إغلاق الاتصال القديم
          await _webrtcService.closePeerConnection(player.id);
          await Future.delayed(const Duration(milliseconds: 500));

          // إنشاء اتصال جديد
          await _webrtcService.createPeerConnectionForPeer(player.id);
          await Future.delayed(const Duration(milliseconds: 800));

          // إرسال offer جديد
          await _webrtcService.createOffer(player.id);
          await Future.delayed(const Duration(seconds: 1));

          log('✅ تم إعادة إنشاء اتصال مع ${player.name}');

        } catch (e) {
          log('❌ فشل في إعادة إنشاء اتصال مع ${player.id}: $e');
        }
      }

      // 3. تفعيل جميع المسارات الصوتية
      _webrtcService.enableRemoteAudio();
      await _webrtcService.ensureAudioPlayback();

      log('🚨 انتهى الإصلاح الطارئ');

    } catch (e) {
      log('❌ خطأ في الإصلاح الطارئ: $e');
    }
  }

// دالة فحص دوري خفيف
  void _performPeriodicHealthCheck() {
    try {
      log('⏰ فحص دوري خفيف');

      final localTracks = _webrtcService.localStream?.getAudioTracks().length ?? 0;
      final remoteTracks = _webrtcService.remoteStreams.length;

      log('📊 حالة سريعة: محلي=$localTracks، بعيد=$remoteTracks');

      // إذا لم يكن هناك صوت محلي، إعادة التهيئة
      if (localTracks == 0) {
        log('🔧 إعادة تهيئة الصوت المحلي المفقود');
        _webrtcService.initializeLocalAudio().catchError((e) {
          log('❌ فشل إعادة تهيئة الصوت: $e');
        });
      }

      // تفعيل الصوت البعيد إذا كان متوفراً
      if (remoteTracks > 0) {
        _webrtcService.enableRemoteAudio();
      }

    } catch (e) {
      log('❌ خطأ في الفحص الدوري: $e');
    }
  }

// تحديث دالة _startTimers لتضمين تنظيف الإشارات
  void _startTimers() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() {});
    });

    _roundCheckTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      final gameProvider = context.read<GameProvider>();
      gameProvider.checkRoundTimeout();
    });

    _connectionTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (mounted) {
        checkConnectionAndRefresh(_realtimeManager, widget.playerId, context);

        // تنظيف دوري للإشارات القديمة
        final gameProvider = context.read<GameProvider>();
        if (gameProvider.currentRoom != null) {
          _supabaseService.cleanupOldSignals(gameProvider.currentRoom!.id);
        }
      }
    });

    // مؤقت إضافي لفحص صحة WebRTC
    Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) {
        _webrtcService.verifyAudioInAllConnections();
      }
    });
  }

  Future<void> _connectToOtherPlayers(List<Player> players) async {
    if (_hasConnectedToPeers) return;

    try {
      final connectedPlayers = players.where((p) => p.isConnected && p.id != widget.playerId).toList();

      if (connectedPlayers.isEmpty) {
        log('لا يوجد لاعبون آخرون متصلون للاتصال بهم');
        return;
      }

      log('🚀 بدء الاتصال بـ ${connectedPlayers.length} لاعبين');

      for (final player in connectedPlayers) {
        try {
          log('📞 إنشاء اتصال مع ${player.name} (${player.id})');
          await _webrtcService.createPeerConnectionForPeer(player.id);

          // تأخير للتأكد من استقرار الاتصال
          await Future.delayed(const Duration(milliseconds: 1500));

          // إنشاء عرض للاتصال
          await _webrtcService.createOffer(player.id);
          log('✓ تم إرسال عرض إلى ${player.id}');

          // تأخير إضافي للسماح بمعالجة العرض
          await Future.delayed(const Duration(milliseconds: 1000));

        } catch (e) {
          log('❌ خطأ في الاتصال باللاعب ${player.id}: $e');
        }
      }

      _hasConnectedToPeers = true;
      log('✅ تم الانتهاء من محاولات الاتصال');

      // تشخيص شامل للاتصالات والصوت
      Future.delayed(const Duration(seconds: 10), () async {
        if (mounted) {
          log('🔍 === تشخيص شامل بعد 10 ثوانٍ ===');
          await _webrtcService.diagnoseAndFixAudio();
        }
      });

    } catch (e) {
      log('❌ خطأ عام في الاتصال باللاعبين: $e');
    }
  }

// 3. تحديث دالة _toggleMicrophone:
  void _toggleMicrophone() {
    _webrtcService.toggleMicrophone();
    setState(() => _isMicrophoneOn = _webrtcService.isMicrophoneEnabled);

    // إضافة تشخيص
    _webrtcService.checkAudioTracks();
  }

  void _leaveGame() {
    showLeaveGameDialog(context, _supabaseService, widget.playerId);
  }

// تعديل دالة _getBackgroundDecoration في GameScreen
  BoxDecoration _getBackgroundDecoration(GameState state) {
    List<Color> colors;
    switch (state) {
      case GameState.waiting:
        colors = [Colors.blue, Colors.indigo];
        break;
      case GameState.playing:
        colors = [Colors.green, Colors.teal];
        break;
      case GameState.voting:
        colors = [Colors.orange, Colors.deepOrange];
        break;
      case GameState.continueVoting:
        colors = [Colors.purple, Colors.deepPurple];
        break;
      case GameState.finished:
        colors = [Colors.grey, Colors.blueGrey];
        break;
    }

    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: colors,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<GameProvider>(
      builder: (context, gameProvider, child) {
        final room = gameProvider.currentRoom;
        final currentPlayer = gameProvider.currentPlayer;

        if (room == null || currentPlayer == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return WillPopScope(
          onWillPop: () async {
            _leaveGame();
            return false;
          },
          child: Scaffold(
            body: Container(
              decoration: _getBackgroundDecoration(room.state),
              child: SafeArea(
                child: _isConnecting
                    ? GameConnectingScreen(pulseController: _pulseController)
                    : _buildGameContent(room, currentPlayer, gameProvider),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildGameContent(GameRoom room, Player currentPlayer, GameProvider gameProvider) {
    return Column(
      children: [
        GameTopBar(
          room: room,
          currentPlayer: currentPlayer,
          isRealtimeConnected: _isRealtimeConnected,
          onLeaveGame: _leaveGame,
        ),
        const SizedBox(height: 20),
        Expanded(
          child: GameContent(
            room: room,
            currentPlayer: currentPlayer,
            gameProvider: gameProvider,
            playerId: widget.playerId,
            cardController: _cardController,
            onConnectToOtherPlayers: _connectToOtherPlayers,
          ),
        ),
        GameBottomControls(
          room: room,
          isMicrophoneOn: _isMicrophoneOn,
          onToggleMicrophone: _toggleMicrophone,
        ),
      ],
    );
  }

  Future<void> _testWebRTCCallbacks() async {
    log('🧪 === اختبار WebRTC Callbacks ===');

    // التحقق من أن الـ callbacks تم تعيينها
    final hasCallbacks = _webrtcService.hasCallbacks; // ستحتاج إضافة هذا getter
    log('📞 Callbacks معينة: $hasCallbacks');

    // اختبار الإشارات
    final gameProvider = context.read<GameProvider>();
    if (gameProvider.currentRoom != null) {
      final room = gameProvider.currentRoom!;
      final otherPlayers = room.players.where((p) => p.id != widget.playerId && p.isConnected).toList();

      log('👥 لاعبين آخرين متصلين: ${otherPlayers.length}');

      for (final player in otherPlayers) {
        log('🔍 فحص اتصال مع ${player.name} (${player.id})');

        // التحقق من وجود peer connection
        final hasPeer = _webrtcService.hasPeer(player.id);
        log('   📡 Has Peer: $hasPeer');

        if (hasPeer) {
          // التحقق من صحة الاتصال
          final isHealthy = await _webrtcService.isPeerConnectionHealthy(player.id);
          log('   💚 Is Healthy: $isHealthy');

          // التحقق من وجود مسارات
          final hasRemoteStream = _webrtcService.getRemoteStream(player.id) != null;
          log('   🎵 Has Remote Stream: $hasRemoteStream');
        }
      }
    }

    log('🧪 === انتهاء اختبار Callbacks ===');
  }

  @override
  void dispose() {
    _timer?.cancel();
    _roundCheckTimer?.cancel();
    _connectionTimer?.cancel();
    _pulseController.dispose();
    _cardController.dispose();
    _webrtcService.dispose();
    _realtimeManager.dispose();
    super.dispose();
  }
}