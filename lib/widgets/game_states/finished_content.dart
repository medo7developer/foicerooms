import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../providers/game_provider.dart';
import '../../models/experience_models.dart';
import '../../models/game_room_model.dart';
import '../../models/player_model.dart';
import '../../providers/game_state.dart';

class FinishedContent extends StatelessWidget {
  final GameRoom room;
  final Player currentPlayer;

  const FinishedContent({
    super.key,
    required this.room,
    required this.currentPlayer,
  });

  @override
  Widget build(BuildContext context) {
    final wasPlayerSpy = currentPlayer.role == PlayerRole.spy;
    final gameProvider = context.watch<GameProvider>();
    final rewards = gameProvider.lastGameRewards ?? [];
    final playerStats = gameProvider.currentPlayerStats;

    // تحديد الفائز بناءً على بيانات الغرفة
    bool spyWon = false;
    if (room.winner != null) {
      spyWon = room.winner == 'spy';
    } else {
      // fallback للطريقة القديمة
      spyWon = room.players.any((p) => p.role == PlayerRole.spy);
    }

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
            _buildResultIcon(playerWon),
            const SizedBox(height: 20),
            _buildResultTitle(playerWon),
            const SizedBox(height: 10),
            _buildResultDescription(wasPlayerSpy, spyWon),

            // *** إضافة عرض الجاسوس المكشوف ***
            if (room.revealedSpyId != null) ...[
              const SizedBox(height: 20),
              _buildRevealedSpySection(),
            ],

            const SizedBox(height: 30),
            _buildBackToHomeButton(context),

            // عرض المكافآت الجديدة
            if (rewards.isNotEmpty) ...[
              const SizedBox(height: 20),
              _buildRewardsSection(rewards),
            ],

            // عرض الإحصائيات
            if (playerStats != null) ...[
              const SizedBox(height: 20),
              _buildStatsSection(playerStats),
            ],
          ],
        ),
      ),
    );
  }

// *** دالة جديدة لعرض الجاسوس المكشوف ***
  Widget _buildRevealedSpySection() {
    // البحث عن اسم الجاسوس من البيانات المحفوظة
    String spyName = 'الجاسوس';

    // محاولة العثور على اسم الجاسوس من اللاعبين الحاليين أو السابقين
    final allPlayersIncludingEliminated = [...room.players];

    // في حالة عدم وجود الجاسوس في القائمة الحالية (تم إقصاؤه)
    final spyPlayer = allPlayersIncludingEliminated.firstWhere(
          (p) => p.id == room.revealedSpyId,
      orElse: () =>
          Player(
            id: room.revealedSpyId!,
            name: 'الجاسوس المكشوف',
            role: PlayerRole.spy,
          ),
    );

    spyName = spyPlayer.name;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.red.shade100, Colors.red.shade200],
        ),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.red, width: 2),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.visibility,
            size: 40,
            color: Colors.red,
          ),
          const SizedBox(height: 10),
          const Text(
            'كشف الجاسوس!',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.red,
            ),
          ),
          const SizedBox(height: 8),
          RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              style: const TextStyle(fontSize: 16, color: Colors.black87),
              children: [
                const TextSpan(text: 'الجاسوس الحقيقي كان: '),
                TextSpan(
                  text: spyName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                    fontSize: 18,
                  ),
                ),
                const TextSpan(text: ' 🕵️'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultIcon(bool playerWon) {
    return Icon(
      playerWon ? Icons.emoji_events : Icons.sentiment_dissatisfied,
      size: 80,
      color: playerWon ? Colors.amber : Colors.grey,
    );
  }

  Widget _buildResultTitle(bool playerWon) {
    return Text(
      playerWon ? '🎉 فزت!' : '😔 خسرت',
      style: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.bold,
        color: playerWon ? Colors.amber : Colors.grey,
      ),
    );
  }

  Widget _buildResultDescription(bool wasPlayerSpy, bool spyWon) {
    String description;

    if (wasPlayerSpy) {
      description = spyWon ? 'نجحت في خداع الآخرين!' : 'تم اكتشافك!';
    } else {
      description = spyWon
          ? 'لم تتمكنوا من اكتشاف الجاسوس'
          : 'نجحتم في اكتشاف الجاسوس!';
    }

    return Text(
      description,
      style: const TextStyle(
        fontSize: 16,
        color: Colors.black54,
      ),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildBackToHomeButton(BuildContext context) {
    return ElevatedButton(
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
    );
  }

  Widget _buildRewardsSection(List<GameReward> rewards) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.amber.shade100, Colors.amber.shade200],
        ),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.amber, width: 2),
      ),
      child: Column(
        children: [
          const Row(
            children: [
              Icon(Icons.emoji_events, color: Colors.amber, size: 30),
              SizedBox(width: 10),
              Text(
                'المكافآت المكتسبة',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.amber,
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          ...rewards.map((reward) => _buildRewardItem(reward)),
        ],
      ),
    );
  }

  Widget _buildRewardItem(GameReward reward) {
    IconData icon;
    Color color;

    switch (reward.type) {
      case RewardType.xp:
        icon = Icons.stars;
        color = Colors.blue;
        break;
      case RewardType.badge:
        icon = BadgeUtils.getBadgeIcon(reward.badgeType!);
        color = BadgeUtils.getBadgeColor(reward.badgeType!);
        break;
      case RewardType.title:
        icon = Icons.military_tech;
        color = Colors.purple;
        break;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              reward.description,
              style: const TextStyle(fontSize: 14),
            ),
          ),
          if (reward.xpAmount > 0)
            Text(
              '+${reward.xpAmount} XP',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatsSection(PlayerStats stats) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.person, color: Colors.blue.shade600, size: 24),
              const SizedBox(width: 10),
              Text(
                'مستوى ${stats.level}',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade700,
                ),
              ),
              const Spacer(),
              Text(
                '${stats.totalXP} XP',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.blue.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem('الانتصارات', '${stats.wins}', Colors.green),
              _buildStatItem(
                  'معدل الفوز', '${stats.winRate.toStringAsFixed(1)}%',
                  Colors.orange),
              _buildStatItem(
                  'الشارات', '${stats.badges.length}', Colors.purple),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }
}