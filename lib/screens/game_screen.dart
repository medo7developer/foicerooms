import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';

import '../providers/game_provider.dart';
import '../services/realtime_manager.dart';
import '../services/webrtc_service.dart';
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

      // تهيئة الصوت المحلي أولاً
      await _webrtcService.initializeLocalAudio();
      log('تم تهيئة الصوت المحلي');

      if (!mounted) return;

      final gameProvider = context.read<GameProvider>();
      gameProvider.setSupabaseService(_supabaseService);
      _realtimeManager.registerGameProvider(gameProvider);

      // إعداد callbacks للـ WebRTC مع تمرير context صحيح
      setupWebRTCCallbacks(_webrtcService, _supabaseService, widget.playerId, context);
      log('تم إعداد WebRTC callbacks مع context صحيح');

      final currentRoom = gameProvider.currentRoom;
      if (currentRoom != null) {
        await _realtimeManager.subscribeToRoom(currentRoom.id, widget.playerId);
        setState(() => _isRealtimeConnected = true);

        // تحديث فوري للبيانات
        await _realtimeManager.forceRefresh();

        // محاولة الاتصال بالآخرين إذا كان هناك لاعبون
        if (currentRoom.players.length > 1) {
          await _connectToOtherPlayers(currentRoom.players);
        }
      }

      setState(() => _isConnecting = false);
      _startTimers();

      // تشخيص الصوت مع تأخير أطول
      Future.delayed(const Duration(seconds: 8), () {
        if (mounted) {
          log('=== فحص الاتصالات بعد 8 ثوانٍ ===');
          _webrtcService.debugConnectionStates();
          _webrtcService.enableRemoteAudio();
          _webrtcService.ensureAudioPlayback();
        }
      });

    } catch (e) {
      log('خطأ في تهيئة اللعبة: $e');
      setState(() => _isConnecting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تهيئة الصوت: $e')),
        );
      }
    }
  }

// تحديث _startTimers لتمرير context:
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