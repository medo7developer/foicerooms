import 'package:flutter/material.dart';
import '../../../providers/game_provider.dart';
import '../../models/game_room_model.dart';
import '../../models/player_model.dart';
import '../../providers/game_state.dart';

class PlayingContent extends StatefulWidget {
  final GameRoom room;
  final Player currentPlayer;
  final GameProvider gameProvider;
  final String playerId;
  final AnimationController cardController;
  final Function(List<Player>) onConnectToOtherPlayers;

  const PlayingContent({
    super.key,
    required this.room,
    required this.currentPlayer,
    required this.gameProvider,
    required this.playerId,
    required this.cardController,
    required this.onConnectToOtherPlayers,
  });

  @override
  State<PlayingContent> createState() => _PlayingContentState();
}

class _PlayingContentState extends State<PlayingContent> {
  bool _hasTriedConnection = false;
  String? _currentWord; // متغير محلي لتخزين الكلمة

  @override
  void initState() {
    super.initState();
    // تحديث الكلمة عند بدء الحالة
    _updateWord();
  }

  @override
  void didUpdateWidget(PlayingContent oldWidget) {
    super.didUpdateWidget(oldWidget);

    // إعادة تعيين حالة الاتصال إذا تغيرت قائمة اللاعبين
    if (oldWidget.room.players.length != widget.room.players.length) {
      _hasTriedConnection = false;
    }

    // تحديث الكلمة إذا تغيرت حالة الغرفة
    if (oldWidget.room.state != widget.room.state ||
        oldWidget.room.currentWord != widget.room.currentWord ||
        oldWidget.currentPlayer.role != widget.currentPlayer.role) {
      _updateWord();
    }
  }

  // دالة لتحديث الكلمة الحالية
  void _updateWord() {
    if (!mounted) return;

    setState(() {
      // تحديد الكلمة بناءً على دور اللاعب
      if (widget.currentPlayer.role == PlayerRole.spy) {
        _currentWord = '??? أنت الجاسوس';
      } else {
        _currentWord = widget.room.currentWord ?? '';
      }
    });

    // طباعة معلومات التصحيح
    debugPrint('تحديث الكلمة: ${widget.currentPlayer.role}, الكلمة: $_currentWord, كلمة الغرفة: ${widget.room.currentWord}');
  }

  @override
  Widget build(BuildContext context) {
    // محاولة الاتصال بالآخرين مرة واحدة فقط عند وجود لاعبين جدد
    if (!_hasTriedConnection && widget.room.players.length > 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_hasTriedConnection) {
          _hasTriedConnection = true;
          widget.onConnectToOtherPlayers(widget.room.players);

          // محاولة إضافية بعد 3 ثوانٍ للتأكد
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) {
              widget.onConnectToOtherPlayers(widget.room.players);
            }
          });
        }
      });
    }

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // عرض الكلمة
          _buildWordCard(),
          const SizedBox(height: 30),
          // قائمة اللاعبين مع مؤشرات الصوت
          Expanded(child: _buildPlayersList()),
        ],
      ),
    );
  }

  Widget _buildWordCard() {
    return AnimatedBuilder(
      animation: widget.cardController,
      builder: (context, child) {
        return Transform.scale(
          scale: 1.0 + (widget.cardController.value * 0.1),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(30),
            decoration: BoxDecoration(
              color: widget.currentPlayer.role == PlayerRole.spy
                  ? Colors.red.shade100
                  : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: widget.currentPlayer.role == PlayerRole.spy
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
                  widget.currentPlayer.role == PlayerRole.spy
                      ? Icons.visibility_off
                      : Icons.visibility,
                  size: 50,
                  color: widget.currentPlayer.role == PlayerRole.spy
                      ? Colors.red
                      : Colors.green,
                ),
                const SizedBox(height: 20),
                Text(
                  _currentWord ?? '', // استخدام المتغير المحلي بدلاً من gameProvider.currentWordForPlayer
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: widget.currentPlayer.role == PlayerRole.spy
                        ? Colors.red
                        : Colors.green,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  widget.currentPlayer.role == PlayerRole.spy
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
    );
  }

  Widget _buildPlayersList() {
    return Container(
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
          _buildPlayersListHeader(),
          Expanded(child: _buildPlayersListBody()),
        ],
      ),
    );
  }

  Widget _buildPlayersListHeader() {
    return Container(
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
            'الجولة ${widget.room.currentRound}/${widget.room.totalRounds}',
            style: const TextStyle(
              fontSize: 14,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayersListBody() {
    return ListView.builder(
      padding: const EdgeInsets.all(10),
      itemCount: widget.room.players.length,
      itemBuilder: (context, index) {
        final player = widget.room.players[index];
        final isCurrentPlayer = player.id == widget.playerId;

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: isCurrentPlayer ? Colors.green.shade50 : Colors.white,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: isCurrentPlayer ? Colors.green : Colors.grey.shade300,
            ),
          ),
          child: Row(
            children: [
              // أفاتار اللاعب مع مؤشر الصوت
              Stack(
                children: [
                  CircleAvatar(
                    backgroundColor: isCurrentPlayer ? Colors.green : Colors.grey,
                    child: Text(
                      player.name[0].toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  // مؤشر نشاط الصوت
                  if (player.isConnected)
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          player.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        if (isCurrentPlayer) ...[
                          const SizedBox(width: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
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
                    Row(
                      children: [
                        Text(
                          player.isConnected ? 'متصل' : 'غير متصل',
                          style: TextStyle(
                            color: player.isConnected ? Colors.green : Colors.red,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (player.isConnected && !isCurrentPlayer) ...[
                          const SizedBox(width: 10),
                          // مؤشر جودة الصوت
                          Row(
                            children: [
                              Icon(
                                Icons.graphic_eq,
                                size: 12,
                                color: Colors.green.shade700,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                'صوت نشط',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.green.shade700,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              // مؤشرات الحالة
              Column(
                children: [
                  Icon(
                    player.isConnected ? Icons.mic : Icons.mic_off,
                    color: player.isConnected ? Colors.green : Colors.red,
                    size: 20,
                  ),
                  if (player.id == widget.room.creatorId) ...[
                    const SizedBox(height: 5),
                    const Icon(Icons.star, color: Colors.amber, size: 16),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}