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
      await _webrtcService.initializeLocalAudio();
      setupWebRTCCallbacks(_webrtcService, _supabaseService, widget.playerId);

      if (!mounted) return;

      final gameProvider = context.read<GameProvider>();
      gameProvider.setSupabaseService(_supabaseService);
      _realtimeManager.registerGameProvider(gameProvider);

      final currentRoom = gameProvider.currentRoom;
      if (currentRoom != null) {
        await _realtimeManager.subscribeToRoom(currentRoom.id, widget.playerId);
        setState(() => _isRealtimeConnected = true);
        await _realtimeManager.forceRefresh();
      }

      setState(() => _isConnecting = false);
      _startTimers();

    } catch (e) {
      setState(() => _isConnecting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تهيئة الصوت: $e')),
        );
      }
    }
  }

  void _startTimers() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() {});
    });

    _roundCheckTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      final gameProvider = context.read<GameProvider>();
      gameProvider.checkRoundTimeout();
    });

    _connectionTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      checkConnectionAndRefresh(_realtimeManager, widget.playerId);
    });
  }

  Future<void> _connectToOtherPlayers(List<Player> players) async {
    if (_hasConnectedToPeers) return;

    try {
      final peerIds = players.where((p) => p.id != widget.playerId).map((p) => p.id).toList();
      if (peerIds.isNotEmpty) {
        await _webrtcService.connectToAllPeers(peerIds, widget.playerId);
        _hasConnectedToPeers = true;
        log('تم الاتصال بـ ${peerIds.length} لاعبين');
      }
    } catch (e) {
      log('خطأ في الاتصال باللاعبين: $e');
    }
  }

  void _toggleMicrophone() {
    _webrtcService.toggleMicrophone();
    setState(() => _isMicrophoneOn = _webrtcService.isMicrophoneEnabled);
  }

  void _leaveGame() {
    showLeaveGameDialog(context, _supabaseService, widget.playerId);
  }

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
      case GameState.finished:
        colors = [Colors.purple, Colors.deepPurple];
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