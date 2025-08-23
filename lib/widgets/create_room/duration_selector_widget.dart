import 'package:flutter/material.dart';

class DurationSelectorWidget extends StatelessWidget {
  final int roundDuration;
  final bool isEnabled;
  final Function(int) onSelected;

  const DurationSelectorWidget({
    super.key,
    required this.roundDuration,
    required this.isEnabled,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final durations = [
      {'seconds': 180, 'label': '3 دقائق', 'description': 'سريع'},
      {'seconds': 300, 'label': '5 دقائق', 'description': 'متوسط'},
      {'seconds': 420, 'label': '7 دقائق', 'description': 'طويل'},
      {'seconds': 600, 'label': '10 دقائق', 'description': 'مطول'},
    ];

    return Container(
      decoration: BoxDecoration(
        color: isEnabled ? Colors.grey.shade50 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        children: durations.asMap().entries.map((entry) {
          final index = entry.key;
          final duration = entry.value;
          final isSelected = roundDuration == duration['seconds'];
          final isFirst = index == 0;
          final isLast = index == durations.length - 1;

          return GestureDetector(
            onTap: isEnabled ? () => onSelected(duration['seconds'] as int) : null,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
              decoration: BoxDecoration(
                color: isSelected ?
                (isEnabled ? Colors.purple : Colors.grey) :
                Colors.transparent,
                borderRadius: BorderRadius.only(
                  topLeft: isFirst ? const Radius.circular(12) : Radius.zero,
                  topRight: isFirst ? const Radius.circular(12) : Radius.zero,
                  bottomLeft: isLast ? const Radius.circular(12) : Radius.zero,
                  bottomRight: isLast ? const Radius.circular(12) : Radius.zero,
                ),
                border: index > 0 ? Border(
                    top: BorderSide(color: Colors.grey.shade300, width: 0.5)
                ) : null,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    duration['label'] as String,
                    style: TextStyle(
                      color: isSelected ? Colors.white :
                      (isEnabled ? Colors.black : Colors.grey.shade500),
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    duration['description'] as String,
                    style: TextStyle(
                      color: isSelected ? Colors.white70 :
                      (isEnabled ? Colors.grey : Colors.grey.shade400),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}