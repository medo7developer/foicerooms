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

// التعديل المطلوب في game_screen.dart - استبدال دالة _initializeGame:

  Future<void> _initializeGame() async {
    if (!mounted) return;

    try {
      _hasConnectedToPeers = false;

      // 1. طلب الصلاحيات والتحقق منها
      final hasPermission = await _webrtcService.requestPermissions();
      if (!hasPermission) {
        throw Exception('صلاحيات الميكروفون مطلوبة للدردشة الصوتية');
      }

      // 2. تهيئة الصوت المحلي مع انتظار كافي
      await _webrtcService.initializeLocalAudio();
      await Future.delayed(const Duration(milliseconds: 1000)); // زيادة وقت الانتظار
      log('✅ تم تهيئة الصوت المحلي');

      if (!mounted) return;

      // 3. إعداد الخدمات
      final gameProvider = context.read<GameProvider>();
      gameProvider.setSupabaseService(_supabaseService);

      // إضافة تهيئة ExperienceService
      final experienceService = ExperienceService();
      gameProvider.setExperienceService(experienceService);
      _setupGameEndListener(gameProvider, experienceService);

      _realtimeManager.registerGameProvider(gameProvider);

      // 4. إعداد WebRTC callbacks مع الدوال المحسنة - هنا المشكلة الأساسية!
      setupWebRTCCallbacks(_webrtcService, _supabaseService, widget.playerId, context);
      log('✅ تم إعداد WebRTC callbacks المحسنة');

      // 5. الاتصال بـ Realtime
      final currentRoom = gameProvider.currentRoom;
      if (currentRoom != null) {
        await _realtimeManager.subscribeToRoom(currentRoom.id, widget.playerId);
        setState(() => _isRealtimeConnected = true);
        log('✅ تم الاتصال بـ Realtime');

        // 6. تحديث البيانات
        await _realtimeManager.forceRefresh();

        // 7. انتظار أطول قبل بدء الاتصالات الصوتية
        await Future.delayed(const Duration(seconds: 3)); // زيادة وقت الانتظار

        // التأكد من وجود لاعبين آخرين
        final connectedPlayers = currentRoom.players
            .where((p) => p.isConnected && p.id != widget.playerId)
            .toList();

        log('🔍 عدد اللاعبين المتصلين: ${connectedPlayers.length}');

        if (connectedPlayers.isNotEmpty) {
          await _connectToOtherPlayersEnhanced(currentRoom.players);
        } else {
          log('⚠️ لا يوجد لاعبين آخرين للاتصال بهم');
        }
      }

      setState(() => _isConnecting = false);

      // 8. بدء المؤقتات
      _startTimers();

      // 9. بدء فحص الصحة الدوري لـ WebRTC
      _webrtcService.startConnectionHealthCheck();

      // 10. تشخيص نهائي بعد فترة أطول
      _scheduleDelayedDiagnostics();

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
    Future.delayed(const Duration(seconds: 20), () async {
      if (mounted) {
        await _testWebRTCCallbacks();
      }
    });
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

// دالة لجدولة التشخيصات المؤجلة
  void _scheduleDelayedDiagnostics() {
    // تشخيص أولي بعد 5 ثوانٍ
    Future.delayed(const Duration(seconds: 5), () async {
      if (mounted) {
        log('🔍 تشخيص أولي للصوت...');
        await _webrtcService.diagnoseAndFixAudio();
      }
    });

    // تشخيص ثاني بعد 10 ثوانٍ
    Future.delayed(const Duration(seconds: 10), () async {
      if (mounted) {
        log('🔍 تشخيص ثاني وإصلاح شامل...');
        await _webrtcService.verifyAudioInAllConnections();
        await _webrtcService.restartFailedConnections();
      }
    });

    // تشخيص نهائي بعد 15 ثانية
    Future.delayed(const Duration(seconds: 15), () async {
      if (mounted) {
        log('🔍 === تشخيص نهائي ===');
        await _webrtcService.diagnoseAndFixAudio();
        _webrtcService.debugConnectionStates();

        // تقرير نهائي عن حالة الصوت
        final localTracks = _webrtcService.localStream?.getAudioTracks().length ?? 0;
        final remoteTracks = _webrtcService.remoteStreams.length;
        final activePeers = _webrtcService.hasPeer;

        log('📋 === تقرير الحالة النهائية ===');
        log('   🎤 مسارات محلية: $localTracks');
        log('   🔊 مجاري بعيدة: $remoteTracks');
        log('   🔗 اتصالات نشطة: $activePeers');

        if (localTracks > 0 && remoteTracks > 0) {
          log('🎉 الدردشة الصوتية جاهزة!');
        } else {
          log('⚠️ قد تحتاج لإعادة تأسيس الاتصالات');
        }
      }
    });
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