import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../providers/game_provider.dart';
import '../services/supabase_service.dart';
import 'create_room_screen.dart';
import 'game_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _nameController = TextEditingController();
  List<GameRoom> _availableRooms = [];
  bool _isLoading = false;
  String? _playerId;

  @override
  void initState() {
    super.initState();
    _playerId = const Uuid().v4();
    _loadAvailableRooms();
  }

  Future<void> _loadAvailableRooms() async {
    setState(() => _isLoading = true);
    final supabaseService = context.read<SupabaseService>();
    final rooms = await supabaseService.getAvailableRooms();
    setState(() {
      _availableRooms = rooms;
      _isLoading = false;
    });
  }

  Future<void> _joinRoom(GameRoom room) async {
    if (_nameController.text.trim().isEmpty) {
      _showSnackBar('يرجى إدخال اسمك أولاً');
      return;
    }

    final gameProvider = context.read<GameProvider>();
    final supabaseService = context.read<SupabaseService>();

    final success = await supabaseService.joinRoom(
      room.id,
      _playerId!,
      _nameController.text.trim(),
    );

    if (success) {
      gameProvider.joinRoom(room.id, _playerId!, _nameController.text.trim());
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => GameScreen(playerId: _playerId!),
        ),
      );
    } else {
      _showSnackBar('الغرفة ممتلئة أو غير متاحة');
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
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
                const SizedBox(height: 40),

                // العنوان
                const Text(
                  '🎯 لعبة الجاسوس',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),

                const SizedBox(height: 10),

                const Text(
                  'اكتشف الجاسوس بينكم!',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white70,
                  ),
                ),

                const SizedBox(height: 40),

                // حقل الاسم
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      hintText: 'أدخل اسمك',
                      prefixIcon: Icon(Icons.person, color: Colors.purple),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.all(20),
                    ),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 18),
                  ),
                ),

                const SizedBox(height: 30),

                // أزرار الإجراءات
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          if (_nameController.text.trim().isEmpty) {
                            _showSnackBar('يرجى إدخال اسمك أولاً');
                            return;
                          }

                          final result = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => CreateRoomScreen(
                                playerId: _playerId!,
                                playerName: _nameController.text.trim(),
                              ),
                            ),
                          );

                          if (result == true) {
                            _loadAvailableRooms();
                          }
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('إنشاء غرفة'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.purple,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(width: 15),

                    ElevatedButton.icon(
                      onPressed: _loadAvailableRooms,
                      icon: _isLoading
                          ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                          : const Icon(Icons.refresh),
                      label: const Text('تحديث'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white.withOpacity(0.2),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          vertical: 15,
                          horizontal: 20,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 30),

                // قائمة الغرف
                Expanded(
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
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: const BoxDecoration(
                            color: Colors.purple,
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(20),
                              topRight: Radius.circular(20),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.groups, color: Colors.white),
                              const SizedBox(width: 10),
                              const Text(
                                'الغرف المتاحة',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '${_availableRooms.length}',
                                style: const TextStyle(
                                  fontSize: 16,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),

                        Expanded(
                          child: _availableRooms.isEmpty
                              ? const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.inbox_outlined,
                                  size: 60,
                                  color: Colors.grey,
                                ),
                                SizedBox(height: 10),
                                Text(
                                  'لا توجد غرف متاحة',
                                  style: TextStyle(
                                    fontSize: 18,
                                    color: Colors.grey,
                                  ),
                                ),
                                SizedBox(height: 5),
                                Text(
                                  'قم بإنشاء غرفة جديدة!',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          )
                              : ListView.builder(
                            padding: const EdgeInsets.all(10),
                            itemCount: _availableRooms.length,
                            itemBuilder: (context, index) {
                              final room = _availableRooms[index];
                              return _buildRoomCard(room);
                            },
                          ),
                        ),
                      ],
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

  Widget _buildRoomCard(GameRoom room) {
    final playersCount = room.players.length;
    final maxPlayers = room.maxPlayers;
    final isFull = playersCount >= maxPlayers;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isFull ? Colors.grey.shade100 : Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: isFull ? Colors.grey.shade300 : Colors.purple.shade100,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(15),
        leading: CircleAvatar(
          backgroundColor: isFull ? Colors.grey : Colors.purple,
          child: Text(
            '$playersCount',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          room.name,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isFull ? Colors.grey : Colors.black,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'اللاعبين: $playersCount/$maxPlayers',
              style: TextStyle(
                color: isFull ? Colors.grey : Colors.black54,
              ),
            ),
            Text(
              'الجولات: ${room.totalRounds} | المدة: ${room.roundDuration}ث',
              style: TextStyle(
                fontSize: 12,
                color: isFull ? Colors.grey : Colors.black45,
              ),
            ),
          ],
        ),
        trailing: ElevatedButton(
          onPressed: isFull ? null : () => _joinRoom(room),
          style: ElevatedButton.styleFrom(
            backgroundColor: isFull ? Colors.grey : Colors.purple,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: Text(isFull ? 'ممتلئة' : 'انضمام'),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }
}