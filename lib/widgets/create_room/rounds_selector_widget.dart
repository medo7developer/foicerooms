import 'package:flutter/material.dart';

class RoundsSelectorWidget extends StatelessWidget {
  final int totalRounds;
  final bool isEnabled;
  final Function(int) onSelected;

  const RoundsSelectorWidget({
    super.key,
    required this.totalRounds,
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
        children: [1, 2, 3, 4, 5].map((rounds) {
          final isSelected = totalRounds == rounds;
          return Expanded(
            child: GestureDetector(
              onTap: isEnabled ? () => onSelected(rounds) : null,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 15),
                decoration: BoxDecoration(
                  color: isSelected ?
                  (isEnabled ? Colors.purple : Colors.grey) :
                  Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$rounds',
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