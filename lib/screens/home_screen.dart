import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/game_room_model.dart';
import '../providers/user_providers/auth_provider.dart';
import '../services/experience_service.dart';
import '../services/home/home_screen_service.dart';
import '../services/supabase_service.dart';
import '../screens/stats_screen.dart';
import '../screens/online_users_screen.dart';
import '../screens/create_room_screen.dart';
import '../widgets/home/home_screen_body.dart';
import '../widgets/home/home_screen_dialogs.dart';
import 'game_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  late HomeScreenService _service;
  late TabController _tabController;
  late AnimationController _refreshController;
  late AnimationController _floatingController;

  @override
  void initState() {
    super.initState();
    _service = HomeScreenService();
    _tabController = TabController(length: 2, vsync: this);

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
    _service.dispose();
    _tabController.dispose();
    _refreshController.dispose();
    _floatingController.dispose();
    super.dispose();
  }

  Future<void> _initializeApp() async {
    await _service.loadSavedData();
    await _service.initializeApp(context);
    _service.startAutoRefresh(context);
  }

  Future<void> _onRefresh() async {
    _service.autoRefreshTimer?.cancel(); // إيقاف التحديث التلقائي مؤقتاً
    await Future.wait([
      _service.checkUserStatus(context),
      _service.loadAvailableRooms(context),
    ]);
    // إعادة تشغيل التحديث التلقائي بعد التحديث اليدوي
    _service.startAutoRefresh(context);
    setState(() {});
  }

  Future<void> _onCreateRoom() async {
    if (_service.nameController.text.trim().isEmpty) {
      _service.showSnackBar(context, 'يرجى إدخال اسمك أولاً', isError: true);
      return;
    }

    if (_service.currentUserStatus?.inRoom == true) {
      _service.showSnackBar(context, 'يجب مغادرة الغرفة الحالية أولاً', isError: true);
      return;
    }

    if (_service.playerId == null) {
      _service.showSnackBar(context, 'خطأ في معرف اللاعب، يرجى إعادة تشغيل التطبيق', isError: true);
      return;
    }

    await _service.savePlayerName(_service.nameController.text.trim());

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreateRoomScreen(
          playerId: _service.playerId!,
          playerName: _service.nameController.text.trim(),
        ),
      ),
    );

    // تحديث فوري بعد العودة من إنشاء الغرفة
    if (result == true) {
      await Future.delayed(const Duration(milliseconds: 300));
      await _service.checkUserStatus(context);
      await _service.loadAvailableRooms(context, showLoading: false);
      setState(() {});
    }
  }

  Future<void> _joinRoom(GameRoom room) async {
    // عرض مؤشر التحميل
    HomeScreenDialogs.showJoiningRoomDialog(context, room.name);

    final success = await _service.joinRoom(context, room);

    // إغلاق مؤشر التحميل
    Navigator.pop(context);

    if (success) {
      // الانتقال لشاشة اللعبة
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => GameScreen(playerId: _service.playerId!),
        ),
      ).then((_) {
        // عند العودة من شاشة اللعبة، تحديث الحالة
        _service.checkUserStatus(context);
        _service.loadAvailableRooms(context, showLoading: false);
        setState(() {});
      });
    }
  }

  Future<void> _deleteRoom(GameRoom room) async {
    final confirmed = await HomeScreenDialogs.showDeleteDialog(context, room);
    if (confirmed == true) {
      await _service.deleteRoom(context, room);
      setState(() {});
    }
  }

  Future<void> _leaveCurrentRoom() async {
    await _service.leaveCurrentRoom(context);
    setState(() {});
  }

  void _rejoinRoom() {
    HomeScreenDialogs.rejoinRoom(
      context: context,
      currentUserStatus: _service.currentUserStatus,
      playerId: _service.playerId,
    );
  }

  void _showOnlineUsers() {
    if (_service.playerId == null || _service.nameController.text.trim().isEmpty) {
      _service.showSnackBar(context, 'يرجى إدخال اسمك أولاً', isError: true);
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => OnlineUsersScreen(
          currentPlayerId: _service.playerId!,
          currentPlayerName: _service.nameController.text.trim(),
          currentRoomId: _service.currentUserStatus?.roomId,
          currentRoomName: _service.currentUserStatus?.roomName,
        ),
      ),
    ).then((result) {
      // تحديث البيانات عند العودة
      if (result == true) {
        _service.checkUserStatus(context);
        _service.loadAvailableRooms(context, showLoading: false);
        setState(() {});
      }
    });
  }

  void _onStatsPressed() {
    if (_service.playerId != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => StatsScreen(),
        ),
      );
    }
  }

  void _onLogout() {
    // تنظيف أي بيانات محلية أخرى
    _service.currentUserStatus = null;
    _service.availableRooms.clear();
    _service.myRooms.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // التحقق من وجود المستخدم في غرفة وعرض مربع الحوار
    if (_service.currentUserStatus?.inRoom == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        HomeScreenDialogs.showUserInRoomDialog(
          context: context,
          currentUserStatus: _service.currentUserStatus!,
          onLeaveRoom: _leaveCurrentRoom,
          onRejoinRoom: _rejoinRoom,
        );
      });
    }

    return HomeScreenBody(
      tabController: _tabController,
      refreshController: _refreshController,
      floatingController: _floatingController,
      nameController: _service.nameController,
      availableRooms: _service.availableRooms,
      myRooms: _service.myRooms,
      isLoading: _service.isLoading,
      currentUserStatus: _service.currentUserStatus,
      playerId: _service.playerId,
      onShowOnlineUsers: _showOnlineUsers,
      onRefresh: _onRefresh,
      onCreateRoom: _onCreateRoom,
      onRejoinRoom: _rejoinRoom,
      onJoinRoom: _joinRoom,
      onDeleteRoom: _deleteRoom,
      onLogout: _onLogout,
      onStatsPressed: _onStatsPressed,
    );
  }
}