import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/game_provider.dart';
import '../services/supabase_service.dart';
import 'game_screen.dart';

class CreateRoomScreen extends StatefulWidget {
  final String playerId;
  final String playerName;

  const CreateRoomScreen({
    super.key,
    required this.playerId,
    required this.playerName,
  });

  @override
  State<CreateRoomScreen> createState() => _CreateRoomScreenState();
}

class _CreateRoomScreenState extends State<CreateRoomScreen> {
  final TextEditingController _roomNameController = TextEditingController();
  int _maxPlayers = 4;
  int _totalRounds = 3;
  int _roundDuration = 300; // 5 دقائق
  bool _isCreating = false;

  Future<void> _createRoom() async {
    if (_roomNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إدخال اسم الغرفة')),
      );
      return;
    }

    setState(() => _isCreating = true);

    try {
      final supabaseService = context.read<SupabaseService>();
      final gameProvider = context.read<GameProvider>();

      // إنشاء الغرفة في قاعدة البيانات
      final roomId = await supabaseService.createRoom(
        name: _roomNameController.text.trim(),
        creatorId: widget.playerId,
        maxPlayers: _maxPlayers,
        totalRounds: _totalRounds,
        roundDuration: _roundDuration,
      );

      if (roomId != null) {
        // إنشاء الغرفة في GameProvider
        gameProvider.createRoom(
          name: _roomNameController.text.trim(),
          creatorId: widget.playerId,
          maxPlayers: _maxPlayers,
          totalRounds: _totalRounds,
          roundDuration: _roundDuration,
        );

        // الانضمام للغرفة كمنشئ
        await supabaseService.joinRoom(roomId, widget.playerId, widget.playerName);
        gameProvider.joinRoom(roomId, widget.playerId, widget.playerName);

        // الانتقال لشاشة اللعبة
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => GameScreen(playerId: widget.playerId),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('فشل في إنشاء الغرفة')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ: $e')),
      );
    } finally {
      setState(() => _isCreating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.purple, Colors.deepPurple],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              children: [
                // شريط التنقل العلوي
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                    ),
                    const Text(
                      'إنشاء غرفة جديدة',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 30),

                Expanded(
                  child: SingleChildScrollView(
                    child: Container(
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
                      padding: const EdgeInsets.all(30),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // اسم الغرفة
                          _buildSectionTitle('اسم الغرفة'),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _roomNameController,
                            decoration: InputDecoration(
                              hintText: 'أدخل اسم الغرفة',
                              prefixIcon: const Icon(Icons.meeting_room),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(15),
                              ),
                              filled: true,
                              fillColor: Colors.grey.shade50,
                            ),
                          ),

                          const SizedBox(height: 30),

                          // عدد اللاعبين
                          _buildSectionTitle('عدد اللاعبين الأقصى'),
                          const SizedBox(height: 10),
                          _buildPlayerCountSelector(),

                          const SizedBox(height: 30),

                          // عدد الجولات
                          _buildSectionTitle('عدد الجولات'),
                          const SizedBox(height: 10),
                          _buildRoundsSelector(),

                          const SizedBox(height: 30),

                          // مدة الجولة
                          _buildSectionTitle('مدة الجولة الواحدة'),
                          const SizedBox(height: 10),
                          _buildDurationSelector(),

                          const SizedBox(height: 40),

                          // زر الإنشاء
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _isCreating ? null : _createRoom,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.purple,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 15),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(15),
                                ),
                              ),
                              child: _isCreating
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
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: Colors.black87,
      ),
    );
  }

  Widget _buildPlayerCountSelector() {
    Widget _buildDurationSelector() {
      final durations = [
        {'seconds': 180, 'label': '3 دقائق'},
        {'seconds': 300, 'label': '5 دقائق'},
        {'seconds': 420, 'label': '7 دقائق'},
        {'seconds': 600, 'label': '10 دقائق'},
      ];

      return Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Column(
          children: durations.asMap().entries.map((entry) {
            final index = entry.key;
            final duration = entry.value;
            final isSelected = _roundDuration == duration['seconds'];
            final isFirst = index == 0;
            final isLast = index == durations.length - 1;

            return GestureDetector(
              onTap: () => setState(() => _roundDuration = duration['seconds'] as int),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.purple : Colors.transparent,
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
                child: Text(
                  duration['label'] as String,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.black,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 16,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      );
    }

    @override
    void dispose() {
      _roomNameController.dispose();
      super.dispose();
    }
  }Decoration(
  color: Colors.grey.shade50,
  borderRadius: BorderRadius.circular(15),
  border: Border.all(color: Colors.grey.shade300),
  ),
  child: Row(
  children: [3, 4, 5, 6, 7, 8].map((count) {
  final isSelected = _maxPlayers == count;
  return Expanded(
  child: GestureDetector(
  onTap: () => setState(() => _maxPlayers = count),
  child: Container(
  padding: const EdgeInsets.symmetric(vertical: 15),
  decoration: BoxDecoration(
  color: isSelected ? Colors.purple : Colors.transparent,
  borderRadius: BorderRadius.circular(12),
  ),
  child: Text(
  '$count',
  textAlign: TextAlign.center,
  style: TextStyle(
  color: isSelected ? Colors.white : Colors.black,
  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
  ),
  ),
  ),
  ),
  );
  }).toList(),
  ),
  );
}

Widget _buildRoundsSelector() {
  return Container(
    decoration: BoxDecoration(
      color: Colors.grey.shade50,
      borderRadius: BorderRadius.circular(15),
      border: Border.all(color: Colors.grey.shade300),
    ),
    child: Row(
      children: [1, 2, 3, 4, 5].map((rounds) {
        final isSelected = _totalRounds == rounds;
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _totalRounds = rounds),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 15),
              decoration: BoxDecoration(
                color: isSelected ? Colors.purple : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$rounds',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.black,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    ),
  );
}

Widget _buildDurationSelector() {
  final durations = [
    {'seconds': 180, 'label': '3 دقائق'},
    {'seconds': 300, 'label': '5 دقائق'},
    {'seconds': 420, 'label': '7 دقائق'},
    {'seconds': 600, 'label': '10 دقائق'},
  ];

  return Container(
      decoration: Box