import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/game_room_model.dart';
import '../models/player_model.dart';
import '../providers/game_provider.dart';
import '../services/supabase_service.dart';
import 'game_screen.dart';
import '../widgets/create_room/user_info_widget.dart';
import '../widgets/create_room/room_name_input_widget.dart';
import '../widgets/create_room/player_count_selector_widget.dart';
import '../widgets/create_room/rounds_selector_widget.dart';
import '../widgets/create_room/duration_selector_widget.dart';
import '../widgets/create_room/game_info_widget.dart';
import '../widgets/create_room/create_room_button_widget.dart';
import '../widgets/create_room/creating_room_info_widget.dart';
import '../widgets/create_room/section_title_widget.dart';

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

      // إنشاء الغرفة في قاعدة البيانات مع تمرير اسم المنشئ
      final roomId = await supabaseService.createRoom(
        name: _roomNameController.text.trim(),
        creatorId: widget.playerId,
        maxPlayers: _maxPlayers,
        totalRounds: _totalRounds,
        roundDuration: _roundDuration,
        creatorName: widget.playerName,
      );

      if (roomId == null) {
        setState(() => _isCreating = false);
        _showSnackBar('فشل في إنشاء الغرفة، تأكد من عدم وجودك في غرفة أخرى', isError: true);
        return;
      }

      // انتظار قصير للتأكد من إنشاء البيانات في قاعدة البيانات
      await Future.delayed(const Duration(milliseconds: 500));

      // جلب بيانات الغرفة من الخادم للتأكد من صحتها
      final serverRoom = await supabaseService.getRoomById(roomId);
      GameRoom localRoom;

      if (serverRoom != null) {
        // استخدام بيانات الخادم
        localRoom = serverRoom;
        debugPrint('✅ تم جلب بيانات الغرفة من الخادم');
      } else {
        // إنشاء بيانات محلية كخطة احتياطية
        localRoom = GameRoom(
          id: roomId,
          name: _roomNameController.text.trim(),
          creatorId: widget.playerId,
          maxPlayers: _maxPlayers,
          totalRounds: _totalRounds,
          roundDuration: _roundDuration,
          players: [
            Player(
              id: widget.playerId,
              name: widget.playerName,
              isConnected: true,
            )
          ],
        );
        debugPrint('⚠️ تم إنشاء بيانات محلية للغرفة');
      }

      // تحديث GameProvider بالبيانات الصحيحة
      gameProvider.currentRoom = localRoom;
      gameProvider.currentPlayer = localRoom.players.firstWhere(
            (p) => p.id == widget.playerId,
        orElse: () => Player(
          id: widget.playerId,
          name: widget.playerName,
          isConnected: true,
        ),
      );

      // إضافة الغرفة لقائمة الغرف المتاحة محلياً
      gameProvider.availableRooms.add(localRoom);

      // إشعار فوري بالتحديث
      gameProvider.notifyListeners();

      // عرض رسالة نجاح
      _showSnackBar('تم إنشاء الغرفة بنجاح!');

      // تأخير قصير للتأكد من اكتمال العمليات
      await Future.delayed(const Duration(milliseconds: 200));

      // الانتقال لشاشة اللعبة
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => GameScreen(playerId: widget.playerId),
        ),
      );
    } catch (e) {
      setState(() => _isCreating = false);
      debugPrint('❌ خطأ في إنشاء الغرفة: $e');

      // التحقق من إنشاء الغرفة رغم الخطأ
      try {
        final supabaseService = context.read<SupabaseService>();
        final rooms = await supabaseService.getAvailableRooms();
        final createdRoom = rooms.firstWhere(
              (room) => room.creatorId == widget.playerId && room.name == _roomNameController.text.trim(),
          orElse: () => GameRoom(id: '', name: '', creatorId: '', maxPlayers: 0, totalRounds: 0, roundDuration: 0),
        );

        if (createdRoom.id.isNotEmpty) {
          // الغرفة تم إنشاؤها بنجاح رغم الخطأ
          debugPrint('✅ تم العثور على الغرفة المنشأة رغم الخطأ');
          final gameProvider = context.read<GameProvider>();
          gameProvider.currentRoom = createdRoom;
          gameProvider.currentPlayer = createdRoom.players.firstWhere(
                (p) => p.id == widget.playerId,
            orElse: () => Player(
              id: widget.playerId,
              name: widget.playerName,
              isConnected: true,
            ),
          );
          gameProvider.notifyListeners();
          _showSnackBar('تم إنشاء الغرفة بنجاح!');
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => GameScreen(playerId: widget.playerId),
            ),
          );
          return;
        }
      } catch (recoveryError) {
        debugPrint('❌ فشل في محاولة الاسترداد: $recoveryError');
      }

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
                          UserInfoWidget(playerName: widget.playerName),

                          const SizedBox(height: 30),

                          // اسم الغرفة
                          const SectionTitleWidget(title: 'اسم الغرفة'),
                          const SizedBox(height: 10),
                          RoomNameInputWidget(
                            controller: _roomNameController,
                            isEnabled: !_isCreating,
                          ),

                          const SizedBox(height: 20),

                          // عدد اللاعبين
                          const SectionTitleWidget(title: 'عدد اللاعبين الأقصى'),
                          const SizedBox(height: 10),
                          PlayerCountSelectorWidget(
                            maxPlayers: _maxPlayers,
                            isEnabled: !_isCreating,
                            onSelected: (value) => setState(() => _maxPlayers = value),
                          ),

                          const SizedBox(height: 30),

                          // عدد الجولات
                          const SectionTitleWidget(title: 'عدد الجولات'),
                          const SizedBox(height: 10),
                          RoundsSelectorWidget(
                            totalRounds: _totalRounds,
                            isEnabled: !_isCreating,
                            onSelected: (value) => setState(() => _totalRounds = value),
                          ),

                          const SizedBox(height: 30),

                          // مدة الجولة
                          const SectionTitleWidget(title: 'مدة الجولة الواحدة'),
                          const SizedBox(height: 10),
                          DurationSelectorWidget(
                            roundDuration: _roundDuration,
                            isEnabled: !_isCreating,
                            onSelected: (value) => setState(() => _roundDuration = value),
                          ),

                          const SizedBox(height: 30),

                          // معلومات إضافية
                          const GameInfoWidget(),

                          const SizedBox(height: 40),

                          // زر الإنشاء
                          CreateRoomButtonWidget(
                            isCreating: _isCreating,
                            onPressed: _createRoom,
                          ),

                          if (_isCreating) ...[
                            const SizedBox(height: 15),
                            const CreatingRoomInfoWidget(),
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

  @override
  void dispose() {
    _roomNameController.dispose();
    super.dispose();
  }
}