import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../providers/game_provider.dart';
import '../services/realtime_manager.dart';
import '../services/webrtc_service.dart';
import '../services/supabase_service.dart';

class GameScreen extends StatefulWidget {
  final String playerId;

  const GameScreen({super.key, required this.playerId});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with TickerProviderStateMixin {
  late WebRTCService _webrtcService;
  late SupabaseService _supabaseService;
  late AnimationController _pulseController;
  late AnimationController _cardController;
  late RealtimeManager _realtimeManager; // إضافة جديدة
  Timer? _timer;
  bool _isMicrophoneOn = true;
  bool _isConnecting = true;
  bool _isRealtimeConnected = false;
  Timer? _connectionTimer;
// إضافة مؤقت للتحقق من انتهاء الجولة:
  Timer? _roundCheckTimer;
  bool _hasConnectedToPeers = false; // إضافة هذا المتغير

  @override
  void initState() {
    super.initState();
    _webrtcService = context.read<WebRTCService>();
    _supabaseService = context.read<SupabaseService>();
    _realtimeManager = context.read<RealtimeManager>();

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();

    _cardController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _initializeGame();
  }

  Future<void> _connectToOtherPlayers(List<Player> players) async {
    if (_hasConnectedToPeers) return; // تجنب الاتصال المتكرر

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

// استبدال دالة _initializeGame:
  Future<void> _initializeGame() async {

    if (!mounted) return; // التحقق من أن الـ widget ما زال mounted
    try {
      _hasConnectedToPeers = false; // إعادة تعيين حالة الاتصال
      await _webrtcService.initializeLocalAudio();

      await _webrtcService.initializeLocalAudio();
      _setupWebRTCCallbacks();

      if (!mounted) return;
      // تسجيل GameProvider مع RealtimeManager وحقن التبعيات
      final gameProvider = context.read<GameProvider>();
      gameProvider.setSupabaseService(_supabaseService);
      _realtimeManager.registerGameProvider(gameProvider);

      // بدء الاستماع للتحديثات المباشرة
      final currentRoom = gameProvider.currentRoom;
      if (currentRoom != null) {
        await _realtimeManager.subscribeToRoom(currentRoom.id, widget.playerId);
        setState(() => _isRealtimeConnected = true);

        // تحديث فوري أول مرة
        await _realtimeManager.forceRefresh();
      }

      setState(() => _isConnecting = false);

      // بدء مؤقت التحديث والاتصال
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted) setState(() {});
      });

// تحديث المؤقت ليكون أقل تكراراً:
      _roundCheckTimer = Timer.periodic(const Duration(seconds: 2), (timer) { // من 1 إلى 2 ثانية
        final gameProvider = context.read<GameProvider>();
        gameProvider.checkRoundTimeout();
      });

      // مؤقت للتحقق من الاتصال - تقليل التكرار
      _connectionTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
        _checkConnectionAndRefresh();
      });

    } catch (e) {
      setState(() => _isConnecting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ في تهيئة الصوت: $e')),
      );
    }
  }

  void _setupWebRTCCallbacks() {
    _webrtcService.setSignalingCallbacks(
      onIceCandidate: (peerId, candidate) async {
        final gameProvider = context.read<GameProvider>(); // إضافة هذا السطر
        if (gameProvider.currentRoom != null) {
          await _supabaseService.sendSignal(
            roomId: gameProvider.currentRoom!.id,
            fromPeer: widget.playerId,
            toPeer: peerId,
            type: 'ice-candidate',
            data: {
              'candidate': candidate.candidate,
              'sdpMid': candidate.sdpMid,
              'sdpMLineIndex': candidate.sdpMLineIndex,
            },
          );
        }
      },
      onOffer: (peerId, offer) async {
        final gameProvider = context.read<GameProvider>(); // إضافة هذا السطر
        if (gameProvider.currentRoom != null) {
          await _supabaseService.sendSignal(
            roomId: gameProvider.currentRoom!.id,
            fromPeer: widget.playerId,
            toPeer: peerId,
            type: 'offer',
            data: {
              'sdp': offer.sdp,
              'type': offer.type,
            },
          );
        }
      },
      onAnswer: (peerId, answer) async {
        final gameProvider = context.read<GameProvider>(); // إضافة هذا السطر
        if (gameProvider.currentRoom != null) {
          await _supabaseService.sendSignal(
            roomId: gameProvider.currentRoom!.id,
            fromPeer: widget.playerId,
            toPeer: peerId,
            type: 'answer',
            data: {
              'sdp': answer.sdp,
              'type': answer.type,
            },
          );
        }
      },
    );

    // الاستماع للإشارات الواردة
    _supabaseService.listenToSignals(widget.playerId).listen((signal) {
      if (signal.isNotEmpty) {
        _handleIncomingSignal(signal);
      }
    });
  }

// إضافة دالة معالجة الإشارات الواردة
  Future<void> _handleIncomingSignal(Map<String, dynamic> signal) async {
    try {
      final fromPeer = signal['from_peer'] as String;
      final type = signal['type'] as String;
      final data = signal['data'] as Map<String, dynamic>;

      switch (type) {
        case 'offer':
          await _webrtcService.createPeerConnectionForPeer(fromPeer);
          await _webrtcService.setRemoteDescription(
            fromPeer,
            RTCSessionDescription(data['sdp'], data['type']),
          );
          await _webrtcService.createAnswer(fromPeer);
          break;

        case 'answer':
          await _webrtcService.setRemoteDescription(
            fromPeer,
            RTCSessionDescription(data['sdp'], data['type']),
          );
          break;

        case 'ice-candidate':
          final candidate = RTCIceCandidate(
            data['candidate'],
            data['sdpMid'],
            data['sdpMLineIndex'],
          );
          await _webrtcService.addIceCandidate(fromPeer, candidate);
          break;
      }

      // حذف الإشارة بعد المعالجة
      if (signal['id'] != null) {
        await _supabaseService.deleteSignal(signal['id']);
      }
    } catch (e) {
      log('خطأ في معالجة الإشارة: $e');
    }
  }

  // فحص الاتصال والتحديث
  void _checkConnectionAndRefresh() {
    final gameProvider = context.read<GameProvider>();
    if (gameProvider.currentRoom != null) {
      // تحديث حالة الاتصال للاعب الحالي
      gameProvider.updateConnectionStatus(widget.playerId, true);

      // تحديث يدوي إذا لزم الأمر
      _realtimeManager.forceRefresh();
    }
  }

  // تحسين شريط المعلومات العلوي
  Widget _buildTopBar(GameRoom room, Player currentPlayer) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          IconButton(
            onPressed: _leaveGame,
            icon: const Icon(Icons.exit_to_app, color: Colors.white),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  room.name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _getStatusText(room.state),
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(width: 10),
                    // مؤشر الاتصال
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _isRealtimeConnected ? Colors.green : Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          _buildTimerWidget(room),
        ],
      ),
    );
  }

  // تحديث دالة التصويت لاستخدام الخادم
  Future<void> _votePlayer(Player player) async {
    final gameProvider = context.read<GameProvider>();
    final currentRoom = gameProvider.currentRoom;

    if (currentRoom == null || currentRoom.state != GameState.voting) return;

    // تأكيد التصويت
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد التصويت'),
        content: Text('هل تريد التصويت ضد ${player.name}؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('تأكيد', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // استخدام التصويت مع المزامنة
      final success = await gameProvider.votePlayerWithServer(player.id);
      if (!success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('فشل في تسجيل الصوت'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

// في dispose، إلغاء المؤقت:
  @override
  void dispose() {
    _timer?.cancel();
    _roundCheckTimer?.cancel(); // إضافة هذا السطر
    _connectionTimer?.cancel();
    _pulseController.dispose();
    _cardController.dispose();
    _webrtcService.dispose();
    _realtimeManager.dispose();
    super.dispose();
  }

  void _toggleMicrophone() {
    _webrtcService.toggleMicrophone();
    setState(() => _isMicrophoneOn = _webrtcService.isMicrophoneEnabled);
  }

  void _leaveGame() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('مغادرة اللعبة'),
        content: const Text('هل تريد مغادرة اللعبة؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              await _supabaseService.leaveRoom(widget.playerId);
              context.read<GameProvider>().leaveRoom();
              Navigator.popUntil(context, (route) => route.isFirst);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('مغادرة', style: TextStyle(color: Colors.white)),
          ),
        ],
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
                    ? _buildConnectingScreen()
                    : _buildGameContent(room, currentPlayer, gameProvider),
              ),
            ),
          ),
        );
      },
    );
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

  Widget _buildConnectingScreen() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return Transform.scale(
                scale: 1.0 + (_pulseController.value * 0.3),
                child: const Icon(
                  Icons.mic,
                  size: 80,
                  color: Colors.white,
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          const Text(
            'جاري تهيئة الصوت...',
            style: TextStyle(
              fontSize: 20,
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGameContent(GameRoom room, Player currentPlayer, GameProvider gameProvider) {
    return Column(
      children: [
        // شريط المعلومات العلوي
        _buildTopBar(room, currentPlayer),

        const SizedBox(height: 20),

        // المحتوى الأساسي حسب حالة اللعبة
        Expanded(
          child: _buildMainContent(room, currentPlayer, gameProvider),
        ),

        // شريط التحكم السفلي
        _buildBottomControls(room),
      ],
    );
  }

  Widget _buildTimerWidget(GameRoom room) {
    final remainingTime = Provider.of<GameProvider>(context).remainingTime;

    if (remainingTime == null || room.state != GameState.playing) {
      return const SizedBox();
    }

    final minutes = remainingTime.inMinutes;
    final seconds = remainingTime.inSeconds % 60;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildMainContent(GameRoom room, Player currentPlayer, GameProvider gameProvider) {
    switch (room.state) {
      case GameState.waiting:
        return _buildWaitingContent(room);
      case GameState.playing:
        return _buildPlayingContent(room, currentPlayer, gameProvider);
      case GameState.voting:
        return _buildVotingContent(room, currentPlayer);
      case GameState.finished:
        return _buildFinishedContent(room, currentPlayer);
    }
  }

  // تحديث _buildWaitingContent لاستخدام بدء اللعبة مع الخادم
  Widget _buildWaitingContent(GameRoom room) {
    final gameProvider = context.watch<GameProvider>();
    final canStart = gameProvider.canStartGame();
    final isCreator = gameProvider.isCurrentPlayerCreator;
    final hasEnoughPlayers = gameProvider.hasEnoughPlayers;
    final connectedCount = gameProvider.connectedPlayersCount;

    return Center(
      child: Container(
        margin: const EdgeInsets.all(20),
        padding: const EdgeInsets.all(30),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.hourglass_empty,
              size: 60,
              color: Colors.blue,
            ),
            const SizedBox(height: 20),
            const Text(
              'في انتظار اللاعبين',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '$connectedCount/${room.maxPlayers} لاعبين',
              style: TextStyle(
                fontSize: 18,
                color: hasEnoughPlayers ? Colors.green : Colors.orange,
                fontWeight: FontWeight.bold,
              ),
            ),

            // إضافة مؤشر الحالة
            const SizedBox(height: 15),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: hasEnoughPlayers ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                hasEnoughPlayers
                    ? '✓ العدد كافي لبدء اللعبة'
                    : 'نحتاج ${gameProvider.minimumPlayersRequired - connectedCount} لاعبين إضافيين على الأقل',
                style: TextStyle(
                  color: hasEnoughPlayers ? Colors.green : Colors.orange,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),

            const SizedBox(height: 20),

            // قائمة اللاعبين مع مؤشرات الاتصال المحسنة
            ...room.players.map((player) => Container(
              margin: const EdgeInsets.symmetric(vertical: 5),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: player.isConnected ? Colors.blue.shade50 : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: player.isConnected ? Colors.blue : Colors.grey,
                  width: player.id == widget.playerId ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: player.isConnected ? Colors.blue : Colors.grey,
                    child: Text(
                      player.name[0].toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              player.name,
                              style: TextStyle(
                                fontWeight: FontWeight.w500,
                                color: player.isConnected ? Colors.black87 : Colors.grey,
                              ),
                            ),
                            if (player.id == widget.playerId) ...[
                              const SizedBox(width: 5),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.green,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'أنت',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        Text(
                          player.isConnected ? 'متصل' : 'غير متصل',
                          style: TextStyle(
                            fontSize: 10,
                            color: player.isConnected ? Colors.green : Colors.red,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (player.id == room.creatorId) ...[
                    const Icon(Icons.star, color: Colors.amber, size: 20),
                  ],
                  if (player.isConnected) ...[
                    const SizedBox(width: 10),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ],
              ),
            )).toList(),

            // زر بدء اللعبة المحسن للمنشئ
            if (isCreator) ...[
              const SizedBox(height: 25),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: canStart ? () async {
                    // تأكيد بدء اللعبة
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('بدء اللعبة'),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('هل تريد بدء اللعبة مع $connectedCount لاعبين؟'),
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.blue.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'سيتم اختيار جاسوس عشوائياً من بين اللاعبين',
                                style: TextStyle(fontSize: 12),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('إلغاء'),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(context, true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                            ),
                            child: const Text('بدء اللعبة',
                                style: TextStyle(color: Colors.white)),
                          ),
                        ],
                      ),
                    );

                    if (confirmed == true) {
                      // إظهار مؤشر التحميل
                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (context) => const AlertDialog(
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 15),
                              Text('جاري بدء اللعبة...'),
                            ],
                          ),
                        ),
                      );

                      // بدء اللعبة مع الخادم
                      final success = await gameProvider.startGameWithServer();

                      // إغلاق مؤشر التحميل
                      Navigator.pop(context);

                      if (!success) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('فشل في بدء اللعبة، يرجى المحاولة مرة أخرى'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  } : null,
                  icon: Icon(
                    canStart ? Icons.play_arrow : Icons.lock,
                    color: Colors.white,
                  ),
                  label: Text(
                    canStart ? 'بدء اللعبة' : 'نحتاج المزيد من اللاعبين',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: canStart ? Colors.green : Colors.grey,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ] else ...[
              // رسالة محسنة للاعبين العاديين
              const SizedBox(height: 25),
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.withOpacity(0.3)),
                ),
                child: Column(
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.info, color: Colors.blue),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'في انتظار مالك الغرفة لبدء اللعبة...',
                            style: TextStyle(
                              color: Colors.blue,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (hasEnoughPlayers) ...[
                      const SizedBox(height: 5),
                      Text(
                        'العدد كافي، يمكن البدء في أي وقت!',
                        style: TextStyle(
                          color: Colors.green.shade700,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPlayingContent(GameRoom room, Player currentPlayer, GameProvider gameProvider) {
    final word = gameProvider.currentWordForPlayer;
    // التحقق من الحاجة للاتصال بالآخرين مرة واحدة فقط
    if (room.players.length > 1) {
      Future.microtask(() => _connectToOtherPlayers(room.players));
    }
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // عرض الكلمة
          AnimatedBuilder(
            animation: _cardController,
            builder: (context, child) {
              return Transform.scale(
                scale: 1.0 + (_cardController.value * 0.1),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(30),
                  decoration: BoxDecoration(
                    color: currentPlayer.role == PlayerRole.spy
                        ? Colors.red.shade100
                        : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: currentPlayer.role == PlayerRole.spy
                          ? Colors.red
                          : Colors.green,
                      width: 3,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 15,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Icon(
                        currentPlayer.role == PlayerRole.spy
                            ? Icons.visibility_off
                            : Icons.visibility,
                        size: 50,
                        color: currentPlayer.role == PlayerRole.spy
                            ? Colors.red
                            : Colors.green,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        word ?? '',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: currentPlayer.role == PlayerRole.spy
                              ? Colors.red
                              : Colors.green,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        currentPlayer.role == PlayerRole.spy
                            ? 'حاول اكتشاف الكلمة دون أن يكتشفوك!'
                            : 'تحدث عن الكلمة دون ذكرها مباشرة',
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.black54,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 30),

          // قائمة اللاعبين
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(15),
                    decoration: const BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.people, color: Colors.white),
                        const SizedBox(width: 10),
                        const Text(
                          'اللاعبون',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          'الجولة ${room.currentRound}/${room.totalRounds}',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(10),
                      itemCount: room.players.length,
                      itemBuilder: (context, index) {
                        final player = room.players[index];
                        final isCurrentPlayer = player.id == widget.playerId;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(15),
                          decoration: BoxDecoration(
                            color: isCurrentPlayer
                                ? Colors.green.shade50
                                : Colors.white,
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(
                              color: isCurrentPlayer
                                  ? Colors.green
                                  : Colors.grey.shade300,
                            ),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: isCurrentPlayer
                                    ? Colors.green
                                    : Colors.grey,
                                child: Text(
                                  player.name[0].toUpperCase(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 15),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      player.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    Text(
                                      isCurrentPlayer ? 'أنت' : 'لاعب',
                                      style: const TextStyle(
                                        color: Colors.grey,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                player.isConnected
                                    ? Icons.mic
                                    : Icons.mic_off,
                                color: player.isConnected
                                    ? Colors.green
                                    : Colors.red,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

  }

  Widget _buildVotingContent(GameRoom room, Player currentPlayer) {
    final hasVoted = currentPlayer.isVoted;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.orange.shade100,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Colors.orange, width: 2),
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.how_to_vote,
                  size: 40,
                  color: Colors.orange,
                ),
                const SizedBox(height: 10),
                Text(
                  hasVoted ? 'تم تسجيل صوتك!' : 'وقت التصويت',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  hasVoted
                      ? 'في انتظار باقي اللاعبين...'
                      : 'صوت ضد اللاعب الذي تشك أنه الجاسوس',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.black54,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          Expanded(
            child: ListView.builder(
              itemCount: room.players.length,
              itemBuilder: (context, index) {
                final player = room.players[index];
                final isCurrentPlayer = player.id == widget.playerId;

                if (isCurrentPlayer) return const SizedBox();

                return Container(
                  margin: const EdgeInsets.only(bottom: 15),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 5,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(15),
                    leading: CircleAvatar(
                      backgroundColor: Colors.orange,
                      child: Text(
                        player.name[0].toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    title: Text(
                      player.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    subtitle: Text('الأصوات: ${player.votes}'),
                    trailing: hasVoted
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : ElevatedButton(
                      onPressed: () => _votePlayer(player),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('صوت'),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFinishedContent(GameRoom room, Player currentPlayer) {
    final wasPlayerSpy = currentPlayer.role == PlayerRole.spy;
    final spyWon = room.players.any((p) => p.role == PlayerRole.spy);
    final playerWon = wasPlayerSpy ? spyWon : !spyWon;

    return Center(
      child: Container(
        margin: const EdgeInsets.all(20),
        padding: const EdgeInsets.all(30),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              playerWon ? Icons.emoji_events : Icons.sentiment_dissatisfied,
              size: 80,
              color: playerWon ? Colors.amber : Colors.grey,
            ),
            const SizedBox(height: 20),
            Text(
              playerWon ? '🎉 فزت!' : '😔 خسرت',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: playerWon ? Colors.amber : Colors.grey,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              wasPlayerSpy
                  ? (spyWon ? 'نجحت في خداع الآخرين!' : 'تم اكتشافك!')
                  : (spyWon ? 'لم تتمكنوا من اكتشاف الجاسوس' : 'نجحتم في اكتشاف الجاسوس!'),
              style: const TextStyle(
                fontSize: 16,
                color: Colors.black54,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: () {
                context.read<GameProvider>().leaveRoom();
                Navigator.popUntil(context, (route) => route.isFirst);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 30,
                  vertical: 15,
                ),
              ),
              child: const Text('العودة للرئيسية'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomControls(GameRoom room) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              onPressed: _toggleMicrophone,
              icon: Icon(
                _isMicrophoneOn ? Icons.mic : Icons.mic_off,
                color: Colors.white,
                size: 30,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getStatusText(GameState state) {
    switch (state) {
      case GameState.waiting:
        return 'في انتظار اللاعبين';
      case GameState.playing:
        return 'اللعبة جارية';
      case GameState.voting:
        return 'وقت التصويت';
      case GameState.finished:
        return 'انتهت اللعبة';
    }
  }
}