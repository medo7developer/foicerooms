import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voice_rooms_app/screens/stats_screen.dart';
import 'dart:developer';
import '../models/game_room_model.dart';
import '../providers/game_provider.dart';
import '../services/experience_service.dart';
import '../services/player_service.dart';
import '../services/supabase_service.dart';
import '../widgets/home/create_room_fab.dart';
import '../widgets/home/current_room_banner.dart';
import '../widgets/home/home_header.dart';
import '../widgets/home/player_name_section.dart';
import '../widgets/home/rooms_list_view.dart';
import '../widgets/home/rooms_tab_section.dart';
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
  UserStatus? _currentUserStatus;
  Timer? _autoRefreshTimer; // إضافة مؤقت للتحديث التلقائي
  bool _isRefreshing = false; // منع التحديث المتداخل

  late TabController _tabController;
  late AnimationController _refreshController;
  late AnimationController _floatingController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _startAutoRefresh();
    _refreshController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _floatingController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);

    _initializeApp();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _refreshController.dispose();
    _floatingController.dispose();
    _nameController.dispose();
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

// تعديل دالة _initializeApp:
  Future<void> _initializeApp() async {
    await _loadSavedData();
    await _checkUserStatus();

    // إضافة تهيئة الإحصائيات هنا
    await _initializePlayerStats();

    await _loadAvailableRooms();
  }

  // إضافة دالة للتحديث التلقائي
  void _startAutoRefresh() {
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (mounted && !_isRefreshing && !_isLoading) {
        _silentRefresh();
      }
    });
  }

  // تحديث صامت بدون مؤشرات تحميل
  Future<void> _silentRefresh() async {
    if (_isRefreshing || _playerId == null) return;

    _isRefreshing = true;
    try {
      // تحديث حالة المستخدم
      final supabaseService = context.read<SupabaseService>();
      final newStatus = await supabaseService.checkUserStatus(_playerId!);

      // تحديث قائمة الغرف
      final allRooms = await supabaseService.getAvailableRooms();

      // تصفية الغرف
      final availableRooms = <GameRoom>[];
      final myRooms = <GameRoom>[];

      for (final room in allRooms) {
        if (room.creatorId == _playerId) {
          myRooms.add(room);
        } else {
          final isPlayerInRoom = room.players.any((player) => player.id == _playerId);
          if (!isPlayerInRoom) {
            availableRooms.add(room);
          }
        }
      }
      // تحديث الواجهة فقط في حالة وجود تغييرات
      if (_hasChanges(newStatus, availableRooms, myRooms)) {
        if (mounted) {
          setState(() {
            _currentUserStatus = newStatus;
            _availableRooms = availableRooms;
            _myRooms = myRooms;
          });
        }
      }
    } catch (e) {
      log('خطأ في التحديث الصامت: $e');
    } finally {
      _isRefreshing = false;
    }
  }

  // فحص التغييرات لتجنب التحديث غير الضروري
  bool _hasChanges(UserStatus? newStatus, List<GameRoom> newAvailable, List<GameRoom> newMy) {
    // فحص تغيير حالة المستخدم
    if (_currentUserStatus?.inRoom != newStatus?.inRoom ||
        _currentUserStatus?.roomId != newStatus?.roomId) {
      return true;
    }

    // فحص تغيير عدد الغرف
    if (_availableRooms.length != newAvailable.length ||
        _myRooms.length != newMy.length) {
      return true;
    }

    // فحص تغيير عدد اللاعبين في الغرف
    for (int i = 0; i < _availableRooms.length && i < newAvailable.length; i++) {
      if (_availableRooms[i].players.length != newAvailable[i].players.length) {
        return true;
      }
    }

    return false;
  }

  // تحسين دالة _loadAvailableRooms
  Future<void> _loadAvailableRooms({bool showLoading = true}) async {
    if (_playerId == null || _isRefreshing) {
      log('معرف اللاعب غير متاح أو جاري التحديث');
      return;
    }

    if (showLoading) {
      setState(() => _isLoading = true);
      _refreshController.forward();
    }

    _isRefreshing = true;

    try {
      final supabaseService = context.read<SupabaseService>();
      final allRooms = await supabaseService.getAvailableRooms();

      // تصفية الغرف بناءً على معرف اللاعب
      final availableRooms = <GameRoom>[];
      final myRooms = <GameRoom>[];

      for (final room in allRooms) {
        if (room.creatorId == _playerId) {
          myRooms.add(room);
        } else {
          // التأكد من أن اللاعب ليس في هذه الغرفة
          final isPlayerInRoom = room.players.any((player) => player.id == _playerId);
          if (!isPlayerInRoom) {
            availableRooms.add(room);
          }
        }
      }

      if (mounted) {
        setState(() {
          _availableRooms = availableRooms;
          _myRooms = myRooms;
          if (showLoading) _isLoading = false;
        });
      }

      log('تم تحميل ${allRooms.length} غرفة، منها ${myRooms.length} غرف خاصة بي و ${availableRooms.length} غرف متاحة');
    } catch (e) {
      log('خطأ في تحميل الغرف: $e');
      if (mounted && showLoading) {
        setState(() => _isLoading = false);
      }
    } finally {
      if (showLoading) {
        _refreshController.reset();
      }
      _isRefreshing = false;
    }
  }

  // تحسين دالة _joinRoom
  Future<void> _joinRoom(GameRoom room) async {
    // التحقق من صحة البيانات
    if (_nameController.text.trim().isEmpty) {
      _showSnackBar('يرجى إدخال اسمك أولاً', isError: true);
      return;
    }

    if (_playerId == null) {
      _showSnackBar('خطأ في معرف اللاعب، يرجى إعادة تشغيل التطبيق', isError: true);
      return;
    }

    // التحقق من حالة المستخدم الحالية
    if (_currentUserStatus?.inRoom == true) {
      _showSnackBar('يجب مغادرة الغرفة الحالية أولاً', isError: true);
      return;
    }

    await _savePlayerName(_nameController.text.trim());

    // عرض مؤشر التحميل
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text('جاري الانضمام لغرفة "${room.name}"...'),
          ],
        ),
      ),
    );

    try {
      final gameProvider = context.read<GameProvider>();
      final supabaseService = context.read<SupabaseService>();

      // محاولة الانضمام في الخادم أولاً
      final result = await supabaseService.joinRoom(
        room.id,
        _playerId!,
        _nameController.text.trim(),
      );

      // إغلاق مؤشر التحميل
      Navigator.pop(context);

      if (result.success) {
        // انتظار قصير للتأكد من تحديث قاعدة البيانات
        await Future.delayed(const Duration(milliseconds: 500));

        // جلب بيانات الغرفة المحدثة من الخادم
        final updatedRoom = await supabaseService.getRoomById(room.id);

        if (updatedRoom != null) {
          // محاولة الانضمام في GameProvider بالبيانات المحدثة
          final success = gameProvider.joinRoom(updatedRoom.id, _playerId!, _nameController.text.trim());

          if (success) {
            // تحديث حالة المستخدم فوراً
            setState(() {
              _currentUserStatus = UserStatus(
                inRoom: true,
                roomId: updatedRoom.id,
                roomName: updatedRoom.name,
                isOwner: false,
                roomState: 'waiting',
              );
            });

            // تحديث قوائم الغرف فوراً
            await _loadAvailableRooms(showLoading: false);

            // الانتقال لشاشة اللعبة
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => GameScreen(playerId: _playerId!),
              ),
            ).then((_) {
              // عند العودة من شاشة اللعبة، تحديث الحالة
              _checkUserStatus();
              _loadAvailableRooms(showLoading: false);
            });
          } else {
            _showSnackBar('انضممت للغرفة في الخادم، جاري تحديث البيانات...', isError: false);
            // تحديث فوري للبيانات
            await _checkUserStatus();
            await _loadAvailableRooms(showLoading: false);
          }
        } else {
          _showSnackBar('انضممت للغرفة، جاري تحديث البيانات...', isError: false);
          await _checkUserStatus();
          await _loadAvailableRooms(showLoading: false);
        }
      } else {
        _showSnackBar(result.reason, isError: true);

        // إذا كان المستخدم في غرفة أخرى، تحديث الحالة
        if (result.existingRoomId != null) {
          await _checkUserStatus();
        }
      }
    } catch (e) {
      // إغلاق مؤشر التحميل في حالة الخطأ
      Navigator.pop(context);
      log('خطأ في الانضمام للغرفة: $e');
      _showSnackBar('خطأ في الاتصال، يرجى المحاولة مرة أخرى', isError: true);
    }
  }

  // تحسين دالة _onRefresh
  void _onRefresh() {
    log('تحديث يدوي للبيانات');
    _autoRefreshTimer?.cancel(); // إيقاف التحديث التلقائي مؤقتاً

    Future.wait([
      _checkUserStatus(),
      _loadAvailableRooms(),
    ]).then((_) {
      // إعادة تشغيل التحديث التلقائي بعد التحديث اليدوي
      _startAutoRefresh();
    });
  }

  // تحسين دالة _onCreateRoom
  Future<void> _onCreateRoom() async {
    if (_nameController.text.trim().isEmpty) {
      _showSnackBar('يرجى إدخال اسمك أولاً', isError: true);
      return;
    }

    if (_currentUserStatus?.inRoom == true) {
      _showSnackBar('يجب مغادرة الغرفة الحالية أولاً', isError: true);
      return;
    }

    if (_playerId == null) {
      _showSnackBar('خطأ في معرف اللاعب، يرجى إعادة تشغيل التطبيق', isError: true);
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

    // تحديث فوري بعد العودة من إنشاء الغرفة
    if (result == true) {
      await Future.delayed(const Duration(milliseconds: 300));
      await _checkUserStatus();
      await _loadAvailableRooms(showLoading: false);
    }
  }

  // تحسين دالة _leaveCurrentRoom
  Future<void> _leaveCurrentRoom() async {
    if (_playerId == null) return;

    try {
      final supabaseService = context.read<SupabaseService>();
      await supabaseService.leaveRoom(_playerId!);

      // تحديث فوري للحالة
      setState(() => _currentUserStatus = UserStatus.free);
      _showSnackBar('تم مغادرة الغرفة');

      // تحديث قوائم الغرف فوراً
      await Future.delayed(const Duration(milliseconds: 300));
      await _loadAvailableRooms(showLoading: false);
    } catch (e) {
      log('خطأ في مغادرة الغرفة: $e');
      _showSnackBar('فشل في مغادرة الغرفة', isError: true);
    }
  }

  // تحسين دالة _deleteRoom
  Future<void> _deleteRoom(GameRoom room) async {
    final confirmed = await _showDeleteDialog(room);
    if (confirmed == true && _playerId != null) {
      final supabaseService = context.read<SupabaseService>();
      final success = await supabaseService.deleteRoom(room.id, _playerId!);

      if (success) {
        _showSnackBar('تم حذف الغرفة بنجاح');

        // تحديث فوري للقوائم
        await Future.delayed(const Duration(milliseconds: 300));
        await _loadAvailableRooms(showLoading: false);
      } else {
        _showSnackBar('فشل في حذف الغرفة', isError: true);
      }
    }
  }

// إضافة هذه الدالة الجديدة:
  Future<void> _initializePlayerStats() async {
    if (_playerId == null || _nameController.text.trim().isEmpty) return;

    try {
      final experienceService = ExperienceService();
      await experienceService.initializePlayerStatsOnStart(
        _playerId!,
        _nameController.text.trim(),
      );
      log('تم تهيئة إحصائيات اللاعب بنجاح');
    } catch (e) {
      log('خطأ في تهيئة إحصائيات اللاعب: $e');
    }
  }

// تعديل دالة _savePlayerName لتحديث الإحصائيات أيضاً:
  Future<void> _savePlayerName(String name) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('player_name', name);
      setState(() => _savedPlayerName = name);

      // تحديث/إنشاء الإحصائيات مع الاسم الجديد
      if (_playerId != null) {
        final experienceService = ExperienceService();
        await experienceService.initializePlayerStatsOnStart(_playerId!, name);
      }

      log('تم حفظ اسم اللاعب وتحديث الإحصائيات: $name');
    } catch (e) {
      log('خطأ في حفظ اسم اللاعب: $e');
    }
  }

  Future<void> _loadSavedData() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // تحميل الاسم المحفوظ
      final savedName = prefs.getString('player_name');
      if (savedName != null && savedName.isNotEmpty) {
        setState(() {
          _savedPlayerName = savedName;
          _nameController.text = savedName;
        });
      }

      // تحميل أو إنشاء معرف ثابت للجهاز
      String? savedPlayerId = prefs.getString('player_id');
      if (savedPlayerId == null || savedPlayerId.isEmpty) {
        savedPlayerId = const Uuid().v4();
        await prefs.setString('player_id', savedPlayerId);
        log('تم إنشاء معرف جديد للاعب: $savedPlayerId');
      } else {
        log('تم تحميل معرف اللاعب المحفوظ: $savedPlayerId');
      }

      setState(() {
        _playerId = savedPlayerId;
      });
    } catch (e) {
      log('خطأ في تحميل البيانات المحفوظة: $e');
      // إنشاء معرف طوارئ
      setState(() {
        _playerId = const Uuid().v4();
      });
    }
  }

  Future<void> _checkUserStatus() async {
    if (_playerId == null) return;

    try {
      final supabaseService = context.read<SupabaseService>();
      final status = await supabaseService.checkUserStatus(_playerId!);

      setState(() {
        _currentUserStatus = status;
      });

      if (status.inRoom) {
        log('المستخدم موجود في غرفة: ${status.roomName} (${status.roomId})');
        _showUserInRoomDialog();
      }
    } catch (e) {
      log('خطأ في التحقق من حالة المستخدم: $e');
    }
  }

  void _showUserInRoomDialog() {
    if (_currentUserStatus?.inRoom != true) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.info, color: Colors.blue.shade600),
            const SizedBox(width: 10),
            const Text('أنت في غرفة نشطة'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('أنت موجود حالياً في غرفة:'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    _currentUserStatus?.isOwner == true ? Icons.star : Icons.meeting_room,
                    color: Colors.blue,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _currentUserStatus?.roomName ?? 'غير معروف',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          _currentUserStatus?.isOwner == true ? 'أنت مالك الغرفة' : 'أنت عضو في الغرفة',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _leaveCurrentRoom();
            },
            child: const Text('مغادرة الغرفة', style: TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _rejoinRoom();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            child: const Text('العودة للغرفة', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _rejoinRoom() async {
    if (_currentUserStatus?.roomId == null || _playerId == null) return;

    try {
      final gameProvider = context.read<GameProvider>();
      final supabaseService = context.read<SupabaseService>();

      // محاولة إعادة الانضمام للغرفة
      final room = await supabaseService.getRoomById(_currentUserStatus!.roomId!);
      if (room != null) {
        // تحديث GameProvider بمعلومات الغرفة
        gameProvider.rejoinRoom(room, _playerId!);

        // الانتقال لشاشة اللعبة
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => GameScreen(playerId: _playerId!),
          ),
        );
      } else {
        _showSnackBar('الغرفة غير موجودة', isError: true);
        setState(() => _currentUserStatus = UserStatus.free);
      }
    } catch (e) {
      log('خطأ في إعادة الانضمام: $e');
      _showSnackBar('فشل في العودة للغرفة', isError: true);
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
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('هل تريد حذف الغرفة "${room.name}"؟'),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'تحذير: سيتم إخراج جميع اللاعبين من الغرفة',
                style: TextStyle(fontSize: 12, color: Colors.red),
              ),
            ),
          ],
        ),
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
              const HomeHeader(),
              if (_currentUserStatus?.inRoom == true)
                CurrentRoomBanner(
                  userStatus: _currentUserStatus!,
                  onRejoinRoom: _rejoinRoom,
                ),
              PlayerNameSection(
                controller: _nameController,
                savedPlayerName: _savedPlayerName,
                isInRoom: _currentUserStatus?.inRoom == true,
                onNameChanged: (value) {
                  if (value.isNotEmpty && _currentUserStatus?.inRoom != true) {
                    _savePlayerName(value);
                  }
                },
              ),
              RoomsTabSection(
                tabController: _tabController,
                availableRoomsCount: _availableRooms.length,
                myRoomsCount: _myRooms.length,
                refreshController: _refreshController,
                totalConnectedUsers: _availableRooms.fold(0, (sum, room) => sum + room.players.length),
                totalActiveRooms: _availableRooms.length + _myRooms.length,
                onRefresh: _onRefresh,
              ),
              Expanded(
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
                      RoomsListView(
                        rooms: _availableRooms,
                        isLoading: _isLoading,
                        isMyRooms: false,
                        currentUserStatus: _currentUserStatus,
                        onJoinRoom: _joinRoom,
                        onDeleteRoom: _deleteRoom,
                      ),
                      RoomsListView(
                        rooms: _myRooms,
                        isLoading: _isLoading,
                        isMyRooms: true,
                        currentUserStatus: _currentUserStatus,
                        onJoinRoom: _joinRoom,
                        onDeleteRoom: _deleteRoom,
                      ),
                    ],
                  ),
                ),
              ),
              // إضافة هذا في HomeScreen في منطقة الأزرار

              FloatingActionButton.extended(
                onPressed: () {
                  if (_playerId != null) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => StatsScreen(playerId: _playerId!),
                      ),
                    );
                  }
                },
                backgroundColor: Colors.purple,
                icon: const Icon(Icons.leaderboard, color: Colors.white),
                label: const Text(
                  'الإحصائيات',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: CreateRoomFab(
        controller: _floatingController,
        canCreate: _currentUserStatus?.inRoom != true && _nameController.text.trim().isNotEmpty,
        isInRoom: _currentUserStatus?.inRoom == true,
        onCreateRoom: _onCreateRoom,
      ),

    );
  }
}