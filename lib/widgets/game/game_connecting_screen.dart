import 'package:flutter/material.dart';

class GameConnectingScreen extends StatelessWidget {
  final AnimationController pulseController;

  const GameConnectingScreen({
    super.key,
    required this.pulseController,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: pulseController,
            builder: (context, child) {
              return Transform.scale(
                scale: 1.0 + (pulseController.value * 0.3),
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
}