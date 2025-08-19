import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';

import '../providers/game_provider.dart';
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

      // 1. طلب الصلاحيات والتحقق منها
      final hasPermission = await _webrtcService.requestPermissions();
      if (!hasPermission) {
        throw Exception('صلاحيات الميكروفون مطلوبة للدردشة الصوتية');
      }

      // 2. تهيئة الصوت المحلي مع انتظار كافي
      await _webrtcService.initializeLocalAudio();
      await Future.delayed(const Duration(milliseconds: 800));
      log('✅ تم تهيئة الصوت المحلي');

      if (!mounted) return;

      // 3. إعداد الخدمات
      final gameProvider = context.read<GameProvider>();
      gameProvider.setSupabaseService(_supabaseService);
      _realtimeManager.registerGameProvider(gameProvider);

      // 4. إعداد WebRTC callbacks مع الدوال المحسنة
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

        // 7. انتظار ثم بدء الاتصالات الصوتية
        await Future.delayed(const Duration(seconds: 2));

        if (currentRoom.players.length > 1) {
          await _connectToOtherPlayersEnhanced(currentRoom.players);
        }
      }

      setState(() => _isConnecting = false);

      // 8. بدء المؤقتات
      _startTimers();

      // 9. بدء فحص الصحة الدوري لـ WebRTC
      _webrtcService.startConnectionHealthCheck();

      // 10. تشخيص نهائي بعد فترة
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
  }

// دالة محسنة للاتصال بالآخرين
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

      // الاتصال بكل لاعب مع تأخير بينهم
      for (int i = 0; i < connectedPlayers.length; i++) {
        final player = connectedPlayers[i];

        try {
          log('📞 الاتصال مع ${player.name} (${i + 1}/${connectedPlayers.length})');

          // إنشاء peer connection
          await _webrtcService.createPeerConnectionForPeer(player.id);

          // انتظار للتأكد من استقرار الاتصال
          await Future.delayed(const Duration(milliseconds: 1200));

          // إنشاء العرض مع retry logic
          bool offerSuccess = false;
          for (int attempt = 1; attempt <= 3; attempt++) {
            try {
              await _webrtcService.createOffer(player.id);
              offerSuccess = true;
              log('✅ تم إرسال عرض إلى ${player.id} (المحاولة $attempt)');
              break;
            } catch (e) {
              log('❌ فشل العرض للمحاولة $attempt: $e');
              if (attempt < 3) {
                await Future.delayed(Duration(seconds: attempt));
              }
            }
          }

          if (!offerSuccess) {
            log('❌ فشل نهائياً في إرسال عرض إلى ${player.id}');
          }

          // تأخير بين الاتصالات
          if (i < connectedPlayers.length - 1) {
            await Future.delayed(const Duration(milliseconds: 800));
          }

        } catch (e) {
          log('❌ خطأ في الاتصال باللاعب ${player.id}: $e');
        }
      }

      _hasConnectedToPeers = true;
      log('✅ تم الانتهاء من محاولات الاتصال المحسنة');

    } catch (e) {
      log('❌ خطأ عام في الاتصال باللاعبين: $e');
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

// دالة جديدة للاتصال مع إعادة المحاولة
  Future<void> _connectToOtherPlayersWithRetry(List<Player> players) async {
    if (_hasConnectedToPeers) return;

    try {
      final connectedPlayers = players
          .where((p) => p.isConnected && p.id != widget.playerId)
          .toList();

      if (connectedPlayers.isEmpty) {
        log('لا يوجد لاعبون آخرون متصلون');
        return;
      }

      log('🚀 بدء الاتصال بـ ${connectedPlayers.length} لاعبين');

      for (final player in connectedPlayers) {
        await _connectToSinglePlayer(player);
      }

      _hasConnectedToPeers = true;
      log('✅ تم الانتهاء من محاولات الاتصال');

      // تشخيص بعد الاتصال
      Future.delayed(const Duration(seconds: 5), () async {
        if (mounted) {
          await _webrtcService.diagnoseAndFixAudio();
        }
      });

    } catch (e) {
      log('❌ خطأ في الاتصال باللاعبين: $e');
    }
  }

// دالة للاتصال بلاعب واحد مع معالجة الأخطاء
  Future<void> _connectToSinglePlayer(Player player) async {
    try {
      log('📞 محاولة الاتصال مع ${player.name} (${player.id})');

      // إنشاء peer connection
      await _webrtcService.createPeerConnectionForPeer(player.id);
      await Future.delayed(const Duration(milliseconds: 800));

      // محاولة إنشاء العرض مع retry
      bool offerSent = false;
      for (int attempt = 1; attempt <= 3; attempt++) {
        try {
          await _webrtcService.createOffer(player.id);
          offerSent = true;
          log('✅ تم إرسال عرض إلى ${player.id} (المحاولة $attempt)');
          break;
        } catch (e) {
          log('❌ فشل العرض للمحاولة $attempt مع ${player.id}: $e');
          if (attempt < 3) {
            await Future.delayed(Duration(seconds: attempt * 2));
          }
        }
      }

      if (!offerSent) {
        log('❌ فشل في إرسال العرض إلى ${player.id} نهائياً');
      }

    } catch (e) {
      log('❌ خطأ شامل في الاتصال باللاعب ${player.id}: $e');
    }
  }

// دالة جديدة للتشخيص الدوري
  void _startAudioDiagnosticTimer() {
    Timer.periodic(const Duration(seconds: 15), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      // فحص سريع لحالة الصوت
      _quickAudioCheck();
    });
  }

// فحص سريع للصوت
  void _quickAudioCheck() {
    final localTracks = _webrtcService.localStream?.getAudioTracks() ?? [];
    final remoteTracks = _webrtcService.remoteStreams.length;

    log('🔊 فحص سريع: ${localTracks.length} محلي، $remoteTracks بعيد');

    // إصلاح سريع إذا لزم الأمر
    if (localTracks.isEmpty) {
      log('⚠️ لا توجد مسارات محلية - إعادة التهيئة');
      _webrtcService.initializeLocalAudio();
    }

    // تفعيل المسارات البعيدة
    _webrtcService.enableRemoteAudio();
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