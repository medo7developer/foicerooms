import 'package:flutter/material.dart';

import '../../models/game_room_model.dart';

class GameBottomControls extends StatelessWidget {
  final GameRoom room;
  final bool isMicrophoneOn;
  final VoidCallback onToggleMicrophone;
  final VoidCallback? onFixAudio;

  const GameBottomControls({
    super.key,
    required this.room,
    required this.isMicrophoneOn,
    required this.onToggleMicrophone,
    this.onFixAudio,
  });


  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // زر الميكروفون
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              onPressed: onToggleMicrophone,
              icon: Icon(
                isMicrophoneOn ? Icons.mic : Icons.mic_off,
                color: Colors.white,
                size: 30,
              ),
            ),
          ),

          // زر إصلاح الصوت (إذا كان متاحاً)
          if (onFixAudio != null) ...[
            const SizedBox(width: 20),
            Container(
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.3),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                onPressed: onFixAudio,
                icon: const Icon(
                  Icons.build,
                  color: Colors.white,
                  size: 24,
                ),
                tooltip: 'إصلاح مشاكل الصوت',
              ),
            ),
          ],
        ],
      ),
    );
  }
}
