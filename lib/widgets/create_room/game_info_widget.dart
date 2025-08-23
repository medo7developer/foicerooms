import 'package:flutter/material.dart';

class GameInfoWidget extends StatelessWidget {
  const GameInfoWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info, color: Colors.blue, size: 20),
              const SizedBox(width: 8),
              const Text(
                'معلومات اللعبة',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            '• سيتم اختيار جاسوس واحد عشوائياً في كل جولة\n'
                '• اللاعبون العاديون يرون الكلمة، الجاسوس لا يراها\n'
                '• الهدف للجاسوس: عدم الكشف عن هويته\n'
                '• الهدف للآخرين: اكتشاف الجاسوس',
            style: TextStyle(
              fontSize: 12,
              color: Colors.black54,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}