import 'package:flutter/material.dart';

import '../../models/game_room_model.dart';

class GameBottomControls extends StatelessWidget {
  final GameRoom room;
  final bool isMicrophoneOn;
  final VoidCallback onToggleMicrophone;

  const GameBottomControls({
    super.key,
    required this.room,
    required this.isMicrophoneOn,
    required this.onToggleMicrophone,
  });

  @override
  Widget build(BuildContext context) {
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
              onPressed: onToggleMicrophone,
              icon: Icon(
                isMicrophoneOn ? Icons.mic : Icons.mic_off,
                color: Colors.white,
                size: 30,
              ),
            ),
          ),
        ],
      ),
    );
  }
}