import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';

import '../../../providers/game_provider.dart';
import '../../../services/supabase_service.dart';

class WaitingContent extends StatefulWidget {
  final GameRoom room;

  const WaitingContent({super.key, required this.room});

  @override
  State<WaitingContent> createState() => _WaitingContentState();
}

class _WaitingContentState extends State<WaitingContent> {
  StreamSubscription<Map<String, dynamic>>? _roomSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _playersSubscription;
  final SupabaseService _supabaseService = SupabaseService();

  @override
  void initState() {
    super.initState();
    _startListeningToUpdates();
  }

  @override
  void dispose() {
    _roomSubscription?.cancel();
    _playersSubscription?.cancel();
    super.dispose();
  }

  void _startListeningToUpdates() {
    final gameProvider = context.read<GameProvider>();

    // الاستماع لتحديثات الغرفة
    _roomSubscription = _supabaseService.listenToRoom(widget.room.id).listen(
          (roomData) {
        _handleRoomUpdate(roomData, gameProvider);
      },
      onError: (error) {
        debugPrint('خطأ في الاستماع لتحديثات الغرفة: $error');
      },
    );

    // الاستماع لتحديثات اللاعبين
    _playersSubscription = _supabaseService.listenToPlayers(widget.room.id).listen(
          (playersData) {
        _handlePlayersUpdate(playersData, gameProvider);
      },
      onError: (error) {
        debugPrint('خطأ في الاستماع لتحديثات اللاعبين: $error');
      },
    );
  }

  void _handleRoomUpdate(Map<String, dynamic> roomData, GameProvider gameProvider) {
    if (!mounted) return;

    try {
      // تحويل البيانات إلى GameRoom
      final updatedRoom = _convertToGameRoom(roomData);
      if (updatedRoom != null) {
        // تحديث GameProvider مع البيانات الجديدة
        gameProvider.updateRoomFromRealtime(
            updatedRoom,
            gameProvider.currentPlayer?.id ?? ''
        );

        // فرض تحديث إضافي للواجهة
        if (mounted) {
          setState(() {});
        }
      }
    } catch (e) {
      debugPrint('خطأ في معالجة تحديث الغرفة: $e');
    }
  }

  void _handlePlayersUpdate(List<Map<String, dynamic>> playersData, GameProvider gameProvider) {
    if (!mounted) return;

    try {
      final currentRoom = gameProvider.currentRoom;
      if (currentRoom == null) return;

      // تحويل بيانات اللاعبين
      final updatedPlayers = playersData.map((playerData) => Player(
        id: playerData['id'] ?? '',
        name: playerData['name'] ?? '',
        isConnected: playerData['is_connected'] ?? false,
        isVoted: playerData['is_voted'] ?? false,
        votes: playerData['votes'] ?? 0,
        role: playerData['role'] == 'spy' ? PlayerRole.spy : PlayerRole.normal,
      )).toList();

      // إنشاء غرفة محدثة مع اللاعبين الجدد
      final updatedRoom = currentRoom.copyWith(players: updatedPlayers);

      gameProvider.updateRoomFromRealtime(
          updatedRoom,
          gameProvider.currentPlayer?.id ?? ''
      );

      // فرض تحديث الواجهة
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('خطأ في معالجة تحديث اللاعبين: $e');
    }
  }

  GameRoom? _convertToGameRoom(Map<String, dynamic> data) {
    try {
      return GameRoom(
        id: data['id'] ?? '',
        name: data['name'] ?? '',
        creatorId: data['creator_id'] ?? '',
        maxPlayers: data['max_players'] ?? 0,
        totalRounds: data['total_rounds'] ?? 0,
        roundDuration: data['round_duration'] ?? 0,
        state: _convertToGameState(data['state']),
        currentRound: data['current_round'] ?? 0,
        currentWord: data['current_word'],
        spyId: data['spy_id'],
        roundStartTime: data['round_start_time'] != null
            ? DateTime.parse(data['round_start_time'])
            : null,
        players: widget.room.players, // سيتم تحديثها من stream اللاعبين
      );
    } catch (e) {
      debugPrint('خطأ في تحويل بيانات الغرفة: $e');
      return null;
    }
  }

  GameState _convertToGameState(String? state) {
    switch (state) {
      case 'waiting': return GameState.waiting;
      case 'playing': return GameState.playing;
      case 'voting': return GameState.voting;
      case 'continue_voting': return GameState.continueVoting;
      case 'finished': return GameState.finished;
      default: return GameState.waiting;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<GameProvider>(
      builder: (context, gameProvider, child) {
        final room = gameProvider.currentRoom ?? widget.room;
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
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Text(
                    '$connectedCount/${room.maxPlayers} لاعبين',
                    key: ValueKey('$connectedCount-${room.maxPlayers}'),
                    style: TextStyle(
                      fontSize: 18,
                      color: hasEnoughPlayers ? Colors.green : Colors.orange,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                // مؤشر الحالة مع انيميشن
                const SizedBox(height: 15),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: hasEnoughPlayers
                        ? Colors.green.withOpacity(0.1)
                        : Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Text(
                      hasEnoughPlayers
                          ? '✓ العدد كافي لبدء اللعبة'
                          : 'نحتاج ${gameProvider.minimumPlayersRequired - connectedCount} لاعبين إضافيين على الأقل',
                      key: ValueKey(hasEnoughPlayers),
                      style: TextStyle(
                        color: hasEnoughPlayers ? Colors.green : Colors.orange,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // قائمة اللاعبين مع انيميشن
                AnimatedList(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  initialItemCount: room.players.length,
                  itemBuilder: (context, index, animation) {
                    if (index >= room.players.length) return const SizedBox();
                    return SlideTransition(
                      position: animation.drive(
                        Tween(begin: const Offset(1, 0), end: Offset.zero)
                            .chain(CurveTween(curve: Curves.easeOut)),
                      ),
                      child: _buildPlayerCard(
                          room.players[index],
                          gameProvider.currentPlayer?.id ?? ''
                      ),
                    );
                  },
                ),

                // زر بدء اللعبة أو رسالة الانتظار
                if (isCreator)
                  _buildStartGameButton(context, gameProvider, canStart, connectedCount)
                else
                  _buildWaitingMessage(hasEnoughPlayers),
              ],
            ),
          ),
        );
      },
    );
  }

  // باقي الدوال تبقى كما هي...
  Widget _buildPlayerCard(Player player, String currentPlayerId) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: player.isConnected ? Colors.blue.shade50 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: player.isConnected ? Colors.blue : Colors.grey,
          width: player.id == currentPlayerId ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            child: CircleAvatar(
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
                    if (player.id == currentPlayerId) ...[
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
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Text(
                    player.isConnected ? 'متصل' : 'غير متصل',
                    key: ValueKey('${player.id}-${player.isConnected}'),
                    style: TextStyle(
                      fontSize: 10,
                      color: player.isConnected ? Colors.green : Colors.red,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (player.id == widget.room.creatorId) ...[
            const Icon(Icons.star, color: Colors.amber, size: 20),
          ],
          AnimatedScale(
            duration: const Duration(milliseconds: 200),
            scale: player.isConnected ? 1.0 : 0.0,
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Colors.green,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // باقي دوال البناء تبقى كما هي...
  Widget _buildStartGameButton(BuildContext context, GameProvider gameProvider, bool canStart, int connectedCount) {
    // نفس الكود الموجود
    return Column(
      children: [
        const SizedBox(height: 25),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: canStart ? () => _showStartGameConfirmation(context, gameProvider, connectedCount) : null,
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
      ],
    );
  }

  Widget _buildWaitingMessage(bool hasEnoughPlayers) {
    // نفس الكود الموجود
    return Column(
      children: [
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
    );
  }

  Future<void> _showStartGameConfirmation(BuildContext context, GameProvider gameProvider, int connectedCount) async {
    // نفس الكود الموجود
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
            child: const Text('بدء اللعبة', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      _startGameWithLoadingDialog(context, gameProvider);
    }
  }

  Future<void> _startGameWithLoadingDialog(BuildContext context, GameProvider gameProvider) async {
    // نفس الكود الموجود
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

    final success = await gameProvider.startGameWithServer();
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
}