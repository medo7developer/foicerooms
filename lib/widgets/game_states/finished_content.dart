import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../providers/game_provider.dart';

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
      orElse: () => Player(
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
}