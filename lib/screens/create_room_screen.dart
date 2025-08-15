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

  @override
  void initState() {
    super.initState();
    // إعطاء اسم افتراضي للغرفة
    _roomNameController.text = 'غرفة ${widget.playerName}';
  }

  Future<void> _createRoom() async {
    if (_roomNameController.text.trim().isEmpty) {
      _showSnackBar('يرجى إدخال اسم الغرفة', isError: true);
      return;
    }

    setState(() => _isCreating = true);

    try {
      final supabaseService = context.read<SupabaseService>();
      final gameProvider = context.read<GameProvider>();

      // التحقق من حالة المستخدم قبل الإنشاء
      final userStatus = await supabaseService.checkUserStatus(widget.playerId);
      if (userStatus.inRoom) {
        setState(() => _isCreating = false);
        _showSnackBar('أنت موجود بالفعل في غرفة "${userStatus.roomName}"', isError: true);
        return;
      }

      // إنشاء الغرفة في قاعدة البيانات أولاً
      final roomId = await supabaseService.createRoom(
        name: _roomNameController.text.trim(),
        creatorId: widget.playerId,
        maxPlayers: _maxPlayers,
        totalRounds: _totalRounds,
        roundDuration: _roundDuration,
      );

      if (roomId == null) {
        setState(() => _isCreating = false);
        _showSnackBar('فشل في إنشاء الغرفة، تأكد من عدم وجودك في غرفة أخرى', isError: true);
        return;
      }

      // إنشاء الغرفة في GameProvider
      final room = gameProvider.createRoom(
        name: _roomNameController.text.trim(),
        creatorId: widget.playerId,
        creatorName: widget.playerName,
        maxPlayers: _maxPlayers,
        totalRounds: _totalRounds,
        roundDuration: _roundDuration,
      );

      // عرض رسالة نجاح
      _showSnackBar('تم إنشاء الغرفة بنجاح!');

      // الانتقال لشاشة اللعبة
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => GameScreen(playerId: widget.playerId),
        ),
      );

    } catch (e) {
      setState(() => _isCreating = false);
      debugPrint('خطأ في إنشاء الغرفة: $e');
      _showSnackBar('حدث خطأ أثناء إنشاء الغرفة، يرجى المحاولة مرة أخرى', isError: true);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error : Icons.check_circle,
              color: Colors.white,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: Duration(seconds: isError ? 4 : 2),
      ),
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
                // شريط التنقل العلوي
                Row(
                  children: [
                    IconButton(
                      onPressed: _isCreating ? null : () => Navigator.pop(context, false),
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
                          // معلومات المستخدم
                          Container(
                            padding: const EdgeInsets.all(15),
                            decoration: BoxDecoration(
                              color: Colors.purple.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(15),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.person, color: Colors.purple),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'منشئ الغرفة',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey,
                                        ),
                                      ),
                                      Text(
                                        widget.playerName,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.purple,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 30),

                          // اسم الغرفة
                          _buildSectionTitle('اسم الغرفة'),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _roomNameController,
                            enabled: !_isCreating,
                            decoration: InputDecoration(
                              hintText: 'أدخل اسم الغرفة',
                              prefixIcon: const Icon(Icons.meeting_room),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(15),
                              ),
                              filled: true,
                              fillColor: _isCreating ? Colors.grey.shade100 : Colors.grey.shade50,
                            ),
                            maxLength: 30,
                          ),

                          const SizedBox(height: 20),

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

                          const SizedBox(height: 30),

                          // معلومات إضافية
                          Container(
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
                          ),

                          const SizedBox(height: 40),

                          // زر الإنشاء
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _isCreating ? null : _createRoom,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _isCreating ? Colors.grey : Colors.purple,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 15),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(15),
                                ),
                                elevation: _isCreating ? 0 : 5,
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

                          if (_isCreating) ...[
                            const SizedBox(height: 15),
                            const Text(
                              'يرجى الانتظار، جاري إنشاء الغرفة وإعداد الإعدادات...',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                                fontStyle: FontStyle.italic,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
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
    return Container(
      decoration: BoxDecoration(
        color: _isCreating ? Colors.grey.shade100 : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [3, 4, 5, 6, 7, 8].map((count) {
          final isSelected = _maxPlayers == count;
          return Expanded(
            child: GestureDetector(
              onTap: _isCreating ? null : () => setState(() => _maxPlayers = count),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 15),
                decoration: BoxDecoration(
                  color: isSelected ?
                  (_isCreating ? Colors.grey : Colors.purple) :
                  Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$count',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isSelected ? Colors.white :
                    (_isCreating ? Colors.grey.shade500 : Colors.black),
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

  Widget _buildRoundsSelector() {
    return Container(
      decoration: BoxDecoration(
        color: _isCreating ? Colors.grey.shade100 : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [1, 2, 3, 4, 5].map((rounds) {
          final isSelected = _totalRounds == rounds;
          return Expanded(
            child: GestureDetector(
              onTap: _isCreating ? null : () => setState(() => _totalRounds = rounds),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 15),
                decoration: BoxDecoration(
                  color: isSelected ?
                  (_isCreating ? Colors.grey : Colors.purple) :
                  Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$rounds',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isSelected ? Colors.white :
                    (_isCreating ? Colors.grey.shade500 : Colors.black),
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

  Widget _buildDurationSelector() {
    final durations = [
      {'seconds': 180, 'label': '3 دقائق', 'description': 'سريع'},
      {'seconds': 300, 'label': '5 دقائق', 'description': 'متوسط'},
      {'seconds': 420, 'label': '7 دقائق', 'description': 'طويل'},
      {'seconds': 600, 'label': '10 دقائق', 'description': 'مطول'},
    ];

    return Container(
      decoration: BoxDecoration(
        color: _isCreating ? Colors.grey.shade100 : Colors.grey.shade50,
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
            onTap: _isCreating ? null : () => setState(() => _roundDuration = duration['seconds'] as int),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
              decoration: BoxDecoration(
                color: isSelected ?
                (_isCreating ? Colors.grey : Colors.purple) :
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
                      (_isCreating ? Colors.grey.shade500 : Colors.black),
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    duration['description'] as String,
                    style: TextStyle(
                      color: isSelected ? Colors.white70 :
                      (_isCreating ? Colors.grey.shade400 : Colors.grey),
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

  @override
  void dispose() {
    _roomNameController.dispose();
    super.dispose();
  }
}