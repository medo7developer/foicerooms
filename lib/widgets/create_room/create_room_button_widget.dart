import 'package:flutter/material.dart';

class CreateRoomButtonWidget extends StatelessWidget {
  final bool isCreating;
  final VoidCallback onPressed;

  const CreateRoomButtonWidget({
    super.key,
    required this.isCreating,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: isCreating ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: isCreating ? Colors.grey : Colors.purple,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          elevation: isCreating ? 0 : 5,
        ),
        child: isCreating
            ? const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
            SizedBox(width: 10),
            Text('جاري الإنشاء...'),
          ],
        )
            : const Text(
          'إنشاء الغرفة',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}