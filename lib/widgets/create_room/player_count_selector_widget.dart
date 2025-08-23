import 'package:flutter/material.dart';

class PlayerCountSelectorWidget extends StatelessWidget {
  final int maxPlayers;
  final bool isEnabled;
  final Function(int) onSelected;

  const PlayerCountSelectorWidget({
    super.key,
    required this.maxPlayers,
    required this.isEnabled,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isEnabled ? Colors.grey.shade50 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [3, 4, 5, 6, 7, 8].map((count) {
          final isSelected = maxPlayers == count;
          return Expanded(
            child: GestureDetector(
              onTap: isEnabled ? () => onSelected(count) : null,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 15),
                decoration: BoxDecoration(
                  color: isSelected ?
                  (isEnabled ? Colors.purple : Colors.grey) :
                  Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$count',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isSelected ? Colors.white :
                    (isEnabled ? Colors.black : Colors.grey.shade500),
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}