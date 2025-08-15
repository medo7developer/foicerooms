import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:developer';
import '../providers/game_provider.dart';
import '../services/supabase_service.dart';
import 'create_room_screen.dart';
import 'game_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final TextEditingController _nameController = TextEditingController();
  List<GameRoom> _availableRooms = [];
  List<GameRoom> _myRooms = [];
  bool _isLoading = false;
  String? _playerId;
  String? _savedPlayerName;

  late TabController _tabController;
  late AnimationController _refreshController;
  late AnimationController _floatingController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _refreshController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _floatingController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);

    // إزالة إنشاء UUID هنا - سيتم في _loadSavedData
    _loadSavedData();
    _loadAvailableRooms();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _refreshController.dispose();
    _floatingController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedData() async {
    final prefs = await SharedPreferences.getInstance();

    // تحميل الاسم المحفوظ
    final savedName = prefs.getString('player_name');
    if (savedName != null) {
      setState(() {
        _savedPlayerName = savedName;
        _nameController.text = savedName;
      });
    }

    // تحميل أو إنشاء معرف ثابت للجهاز
    String? savedPlayerId = prefs.getString('player_id');
    if (savedPlayerId == null) {
      savedPlayerId = const Uuid().v4();
      await prefs.setString('player_id', savedPlayerId);
    }

    setState(() {
      _playerId = savedPlayerId;
    });

    log('معرف اللاعب المحفوظ: $_playerId');
  }

  Future<void> _savePlayerName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('player_name', name);
    setState(() => _savedPlayerName = name);
  }

  Future<void> _loadAvailableRooms() async {
    if (_playerId == null) {
      // إذا لم يتم تحميل معرف اللاعب بعد، انتظار قليل
      await Future.delayed(const Duration(milliseconds: 500));
      if (_playerId == null) return;
    }

    setState(() => _isLoading = true);
    _refreshController.forward();

    final supabaseService = context.read<SupabaseService>();
    final allRooms = await supabaseService.getAvailableRooms();

    setState(() {
      // تصفية الغرف بناءً على معرف اللاعب المحفوظ
      _availableRooms = allRooms.where((room) => room.creatorId != _playerId).toList();
      _myRooms = allRooms.where((room) => room.creatorId == _playerId).toList();
      _isLoading = false;
    });

    _refreshController.reset();

    log('تم تحميل ${allRooms.length} غرفة، منها ${_myRooms.length} غرف خاصة بي');
  }

  Future<void> _joinRoom(GameRoom room) async {
    if (_nameController.text.trim().isEmpty) {
      _showSnackBar('يرجى إدخال اسمك أولاً', isError: true);
      return;
    }

    if (_playerId == null) {
      _showSnackBar('خطأ في معرف اللاعب، يرجى إعادة تشغيل التطبيق', isError: true);
      return;
    }

    await _savePlayerName(_nameController.text.trim());

    // عرض مؤشر التحميل
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Text('جاري الانضمام للغرفة...'),
          ],
        ),
      ),
    );

    try {
      final gameProvider = context.read<GameProvider>();
      final supabaseService = context.read<SupabaseService>();

      final success = await supabaseService.joinRoom(
        room.id,
        _playerId!,
        _nameController.text.trim(),
      );

      // إغلاق مؤشر التحميل
      Navigator.pop(context);

      if (success) {
        final joinedSuccessfully = gameProvider.joinRoom(room.id, _playerId!, _nameController.text.trim());

        if (joinedSuccessfully) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => GameScreen(playerId: _playerId!),
            ),
          );
        } else {
          _showSnackBar('الغرفة ممتلئة بالفعل', isError: true);
        }
      } else {
        _showSnackBar('فشل في الانضمام للغرفة، يرجى المحاولة مرة أخرى', isError: true);
      }
    } catch (e) {
      // إغلاق مؤشر التحميل في حالة الخطأ
      Navigator.pop(context);
      log('خطأ في الانضمام للغرفة: $e');
      _showSnackBar('خطأ في الاتصال، يرجى المحاولة مرة أخرى', isError: true);
    }
  }

  Future<void> _deleteRoom(GameRoom room) async {
    final confirmed = await _showDeleteDialog(room);
    if (confirmed == true) {
      final supabaseService = context.read<SupabaseService>();
      final success = await supabaseService.deleteRoom(room.id);

      if (success) {
        _showSnackBar('تم حذف الغرفة بنجاح');
        _loadAvailableRooms();
      } else {
        _showSnackBar('فشل في حذف الغرفة', isError: true);
      }
    }
  }

  Future<bool?> _showDeleteDialog(GameRoom room) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.red),
            SizedBox(width: 10),
            Text('حذف الغرفة'),
          ],
        ),
        content: Text('هل تريد حذف الغرفة "${room.name}"؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('حذف', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String message, {bool isError = false}) {
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF667eea),
              Color(0xFF764ba2),
              Color(0xFFf093fb),
            ],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              _buildPlayerNameSection(),
              _buildTabSection(),
              _buildRoomsList(),
            ],
          ),
        ),
      ),
      floatingActionButton: _buildFloatingActionButton(),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.games,
                  color: Colors.white,
                  size: 40,
                ),
              ),
              const SizedBox(width: 15),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'لعبة الجاسوس',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    'اكتشف الجاسوس بينكم!',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerNameSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person, color: Color(0xFF667eea)),
              const SizedBox(width: 10),
              const Text(
                'اسم اللاعب',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              if (_savedPlayerName != null) ...[
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'محفوظ',
                    style: TextStyle(
                      color: Colors.green,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 15),
          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              hintText: 'أدخل اسمك هنا',
              prefixIcon: const Icon(Icons.edit, color: Color(0xFF667eea)),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: const Color(0xFF667eea).withOpacity(0.1),
              contentPadding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
            ),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            onChanged: (value) {
              if (value.isNotEmpty) {
                _savePlayerName(value);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTabSection() {
    return Container(
      margin: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          TabBar(
            controller: _tabController,
            tabs: [
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.public),
                    const SizedBox(width: 8),
                    Text('الغرف العامة (${_availableRooms.length})'),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.person),
                    const SizedBox(width: 8),
                    Text('غرفي (${_myRooms.length})'),
                  ],
                ),
              ),
            ],
            labelColor: const Color(0xFF667eea),
            unselectedLabelColor: Colors.grey,
            indicator: BoxDecoration(
              color: const Color(0xFF667eea).withOpacity(0.1),
              borderRadius: BorderRadius.circular(15),
            ),
            dividerColor: Colors.transparent,
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildRefreshButton(),
              _buildStatsCard('المتصلون', '12', Icons.people, Colors.green),
              _buildStatsCard('الغرف النشطة', '${_availableRooms.length + _myRooms.length}', Icons.meeting_room, Colors.blue),
            ],
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _buildRefreshButton() {
    return AnimatedBuilder(
      animation: _refreshController,
      builder: (context, child) {
        return GestureDetector(
          onTap: _loadAvailableRooms,
          child: Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: const Color(0xFF667eea).withOpacity(0.1),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Transform.rotate(
              angle: _refreshController.value * 2 * 3.14159,
              child: Icon(
                Icons.refresh,
                color: const Color(0xFF667eea),
                size: 24,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatsCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 5),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: color.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoomsList() {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(left: 20, right: 20, bottom: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: TabBarView(
          controller: _tabController,
          children: [
            _buildRoomsListView(_availableRooms, false),
            _buildRoomsListView(_myRooms, true),
          ],
        ),
      ),
    );
  }

  Widget _buildRoomsListView(List<GameRoom> rooms, bool isMyRooms) {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 20),
            Text('جاري تحميل الغرف...'),
          ],
        ),
      );
    }

    if (rooms.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isMyRooms ? Icons.inbox : Icons.search_off,
              size: 80,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 20),
            Text(
              isMyRooms ? 'لم تقم بإنشاء أي غرف بعد' : 'لا توجد غرف متاحة حالياً',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              isMyRooms ? 'قم بإنشاء غرفة جديدة!' : 'تحقق مرة أخرى لاحقاً',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(15),
      itemCount: rooms.length,
      itemBuilder: (context, index) {
        final room = rooms[index];
        return _buildRoomCard(room, isMyRooms);
      },
    );
  }

  Widget _buildRoomCard(GameRoom room, bool isMyRoom) {
    final playersCount = room.players.length;
    final maxPlayers = room.maxPlayers;
    final isFull = playersCount >= maxPlayers;
    final fillPercentage = playersCount / maxPlayers;

    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            isFull ? Colors.grey.shade100 : const Color(0xFF667eea).withOpacity(0.1),
            isFull ? Colors.grey.shade200 : const Color(0xFF764ba2).withOpacity(0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isFull ? Colors.grey.shade300 : const Color(0xFF667eea).withOpacity(0.3),
          width: 2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isFull ? Colors.grey : const Color(0xFF667eea),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isMyRoom ? Icons.star : Icons.groups,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              room.name,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: isFull ? Colors.grey : Colors.black87,
                              ),
                            ),
                          ),
                          if (isMyRoom)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.amber,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Text(
                                'مالك',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.people,
                            size: 16,
                            color: isFull ? Colors.grey : Colors.black54,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$playersCount/$maxPlayers',
                            style: TextStyle(
                              color: isFull ? Colors.grey : Colors.black54,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 15),
                          Icon(
                            Icons.timer,
                            size: 16,
                            color: isFull ? Colors.grey : Colors.black54,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${room.roundDuration ~/ 60}د',
                            style: TextStyle(
                              color: isFull ? Colors.grey : Colors.black54,
                            ),
                          ),
                          const SizedBox(width: 15),
                          Icon(
                            Icons.repeat,
                            size: 16,
                            color: isFull ? Colors.grey : Colors.black54,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${room.totalRounds} جولات',
                            style: TextStyle(
                              color: isFull ? Colors.grey : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),

            // شريط التقدم
            Container(
              height: 8,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(4),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: fillPercentage,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isFull
                          ? [Colors.grey, Colors.grey.shade400]
                          : [const Color(0xFF667eea), const Color(0xFF764ba2)],
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 15),

            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: isFull || isMyRoom ? null : () => _joinRoom(room),
                    icon: Icon(
                      isFull ? Icons.lock : Icons.login,
                      size: 20,
                    ),
                    label: Text(
                      isFull ? 'ممتلئة' : isMyRoom ? 'غرفتك' : 'انضمام',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isFull || isMyRoom ? Colors.grey : const Color(0xFF667eea),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                if (isMyRoom) ...[
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    onPressed: () => _deleteRoom(room),
                    icon: const Icon(Icons.delete, size: 20),
                    label: const Text('حذف'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingActionButton() {
    return AnimatedBuilder(
      animation: _floatingController,
      builder: (context, child) {
        return Transform.scale(
          scale: 1.0 + (_floatingController.value * 0.1),
          child: FloatingActionButton.extended(
            onPressed: () async {
              if (_nameController.text.trim().isEmpty) {
                _showSnackBar('يرجى إدخال اسمك أولاً', isError: true);
                return;
              }

              await _savePlayerName(_nameController.text.trim());

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
            backgroundColor: const Color(0xFF667eea),
            foregroundColor: Colors.white,
            elevation: 8,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(25),
            ),
          ),
        );
      },
    );
  }
}