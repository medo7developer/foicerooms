import 'dart:async';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/game_room_model.dart';
import '../player_service.dart';
import '../../providers/game_provider.dart';
import '../../providers/user_providers/auth_provider.dart';
import '../../services/experience_service.dart';
import '../../services/player_service.dart';
import '../../services/supabase_service.dart';
import '../../services/user_services/online_users_service.dart';

class HomeScreenService {
  final TextEditingController nameController = TextEditingController();
  List<GameRoom> availableRooms = [];
  List<GameRoom> myRooms = [];
  bool isLoading = false;
  String? playerId;
  String? savedPlayerName;
  UserStatus? currentUserStatus;
  Timer? autoRefreshTimer;
  bool isRefreshing = false;
  final OnlineUsersService onlineUsersService = OnlineUsersService();

// تعديلات مطلوبة في lib/services/home/home_screen_service.dart

// استبدل دالة initializeApp بهذه النسخة المحدثة:
  Future<void> initializeApp(BuildContext context) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    // استخدام بيانات المستخدم المصادق عليه
    playerId = authProvider.playerId;

    // تحديث اسم اللاعب من بيانات المصادقة
    if (authProvider.playerName.isNotEmpty) {
      nameController.text = authProvider.playerName;
      savedPlayerName = authProvider.playerName;
      // حفظ الاسم محلياً أيضاً
      await savePlayerName(authProvider.playerName);
    }

    if (playerId != null && authProvider.playerName.isNotEmpty) {
      // تحديث الخدمات لاستخدام البيانات الجديدة
      final experienceService = Provider.of<ExperienceService>(context, listen: false);
      await experienceService.handleUserFirstLogin(
        userId: authProvider.playerId,
        email: authProvider.playerEmail,
        displayName: authProvider.playerName,
        photoUrl: authProvider.playerImageUrl,
      );

      await onlineUsersService.updateUserStatus(
        playerId!,
        authProvider.playerName,
        true,
      );
    }

    await checkUserStatus(context);
    await loadAvailableRooms(context);
  }

// إضافة دالة جديدة للحصول على اسم اللاعب الصحيح:
  String getPlayerName(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    // إعطاء أولوية لبيانات المصادقة
    if (authProvider.isAuthenticated && authProvider.playerName.isNotEmpty) {
      return authProvider.playerName;
    }

    // الرجوع للاسم المحفوظ أو المدخل يدوياً
    return nameController.text.trim();
  }

// تحديث دالة joinRoom لاستخدام الاسم الصحيح:
  Future<bool> joinRoom(BuildContext context, GameRoom room) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    if (!authProvider.isAuthenticated) {
      showSnackBar(context, 'يجب تسجيل الدخول أولاً', isError: true);
      return false;
    }

    // الحصول على الاسم الصحيح
    final playerName = getPlayerName(context);

    // التحقق من صحة البيانات
    if (playerName.isEmpty) {
      showSnackBar(context, 'خطأ في الحصول على اسم اللاعب', isError: true);
      return false;
    }

    if (playerId == null) {
      showSnackBar(context, 'خطأ في معرف اللاعب، يرجى إعادة تشغيل التطبيق', isError: true);
      return false;
    }

    // التحقق من حالة المستخدم الحالية
    if (currentUserStatus?.inRoom == true) {
      showSnackBar(context, 'يجب مغادرة الغرفة الحالية أولاً', isError: true);
      return false;
    }

    try {
      final gameProvider = context.read<GameProvider>();
      final supabaseService = context.read<SupabaseService>();

      // محاولة الانضمام في الخادم أولاً
      final result = await supabaseService.joinRoom(
        room.id,
        playerId!,
        playerName, // استخدام الاسم الصحيح
      );

      if (result.success) {
        // باقي الكود كما هو...
        await Future.delayed(const Duration(milliseconds: 500));

        await onlineUsersService.updateUserStatus(
          playerId!,
          playerName,
          true,
          roomId: room.id,
          roomName: room.name,
        );

        final updatedRoom = await supabaseService.getRoomById(room.id);

        if (updatedRoom != null) {
          final success = gameProvider.joinRoom(updatedRoom.id, playerId!, playerName);

          if (success) {
            currentUserStatus = UserStatus(
              inRoom: true,
              roomId: updatedRoom.id,
              roomName: updatedRoom.name,
              isOwner: false,
              roomState: 'waiting',
            );

            await loadAvailableRooms(context, showLoading: false);
            return true;
          } else {
            showSnackBar(context, 'انضممت للغرفة في الخادم، جاري تحديث البيانات...', isError: false);
            await checkUserStatus(context);
            await loadAvailableRooms(context, showLoading: false);
            return false;
          }
        } else {
          showSnackBar(context, 'انضممت للغرفة، جاري تحديث البيانات...', isError: false);
          await checkUserStatus(context);
          await loadAvailableRooms(context, showLoading: false);
          return false;
        }
      } else {
        showSnackBar(context, result.reason, isError: true);

        if (result.existingRoomId != null) {
          await checkUserStatus(context);
        }

        return false;
      }
    } catch (e) {
      log('خطأ في الانضمام للغرفة: $e');
      showSnackBar(context, 'خطأ في الاتصال، يرجى المحاولة مرة أخرى', isError: true);
      return false;
    }
  }

// تحديث دالة leaveCurrentRoom:
  Future<void> leaveCurrentRoom(BuildContext context) async {
    if (playerId == null) return;

    try {
      final supabaseService = context.read<SupabaseService>();
      await supabaseService.leaveRoom(playerId!);

      final playerName = getPlayerName(context);
      await onlineUsersService.updateUserStatus(
        playerId!,
        playerName,
        true,
      );

      currentUserStatus = UserStatus.free;
      showSnackBar(context, 'تم مغادرة الغرفة');

      await Future.delayed(const Duration(milliseconds: 300));
      await loadAvailableRooms(context, showLoading: false);
    } catch (e) {
      log('خطأ في مغادرة الغرفة: $e');
      showSnackBar(context, 'فشل في مغادرة الغرفة', isError: true);
    }
  }

  // بدء التحديث التلقائي
  void startAutoRefresh(BuildContext context) {
    autoRefreshTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (isRefreshing || isLoading) return;
      silentRefresh(context);
    });
  }

  // تحديث صامت بدون مؤشرات تحميل
  Future<void> silentRefresh(BuildContext context) async {
    if (isRefreshing || playerId == null) return;
    isRefreshing = true;

    try {
      final supabaseService = context.read<SupabaseService>();
      final newStatus = await supabaseService.checkUserStatus(playerId!);

      // تحديث قائمة الغرف
      final allRooms = await supabaseService.getAvailableRooms();

      // تصفية الغرف
      final newAvailableRooms = <GameRoom>[];
      final newMyRooms = <GameRoom>[];

      for (final room in allRooms) {
        if (room.creatorId == playerId) {
          newMyRooms.add(room);
        } else {
          final isPlayerInRoom = room.players.any((player) => player.id == playerId);
          if (!isPlayerInRoom) {
            newAvailableRooms.add(room);
          }
        }
      }

      // تحديث الواجهة فقط في حالة وجود تغييرات
      if (hasChanges(newStatus, newAvailableRooms, newMyRooms)) {
        currentUserStatus = newStatus;
        availableRooms = newAvailableRooms;
        myRooms = newMyRooms;
      }
    } catch (e) {
      log('خطأ في التحديث الصامت: $e');
    } finally {
      isRefreshing = false;
    }
  }

  // فحص التغييرات لتجنب التحديث غير الضروري
  bool hasChanges(UserStatus? newStatus, List<GameRoom> newAvailable, List<GameRoom> newMy) {
    // فحص تغيير حالة المستخدم
    if (currentUserStatus?.inRoom != newStatus?.inRoom ||
        currentUserStatus?.roomId != newStatus?.roomId) {
      return true;
    }

    // فحص تغيير عدد الغرف
    if (availableRooms.length != newAvailable.length ||
        myRooms.length != newMy.length) {
      return true;
    }

    // فحص تغيير عدد اللاعبين في الغرف
    for (int i = 0; i < availableRooms.length && i < newAvailable.length; i++) {
      if (availableRooms[i].players.length != newAvailable[i].players.length) {
        return true;
      }
    }

    return false;
  }

  // تحميل الغرف المتاحة
  Future<void> loadAvailableRooms(BuildContext context, {bool showLoading = true}) async {
    if (playerId == null || isRefreshing) {
      log('معرف اللاعب غير متاح أو جاري التحديث');
      return;
    }

    if (showLoading) {
      isLoading = true;
    }

    isRefreshing = true;

    try {
      final supabaseService = context.read<SupabaseService>();
      final allRooms = await supabaseService.getAvailableRooms();

      // تصفية الغرف بناءً على معرف اللاعب
      final newAvailableRooms = <GameRoom>[];
      final newMyRooms = <GameRoom>[];

      for (final room in allRooms) {
        if (room.creatorId == playerId) {
          newMyRooms.add(room);
        } else {
          // التأكد من أن اللاعب ليس في هذه الغرفة
          final isPlayerInRoom = room.players.any((player) => player.id == playerId);
          if (!isPlayerInRoom) {
            newAvailableRooms.add(room);
          }
        }
      }

      availableRooms = newAvailableRooms;
      myRooms = newMyRooms;

      if (showLoading) {
        isLoading = false;
      }

      log('تم تحميل ${allRooms.length} غرفة، منها ${myRooms.length} غرف خاصة بي و ${availableRooms.length} غرف متاحة');
    } catch (e) {
      log('خطأ في تحميل الغرف: $e');
      if (showLoading) {
        isLoading = false;
      }
    } finally {
      isRefreshing = false;
    }
  }

  // حذف غرفة
  Future<void> deleteRoom(BuildContext context, GameRoom room) async {
    if (playerId == null) return;

    try {
      final supabaseService = context.read<SupabaseService>();
      final success = await supabaseService.deleteRoom(room.id, playerId!);

      if (success) {
        showSnackBar(context, 'تم حذف الغرفة بنجاح');
        // تحديث فوري للقوائم
        await Future.delayed(const Duration(milliseconds: 300));
        await loadAvailableRooms(context, showLoading: false);
      } else {
        showSnackBar(context, 'فشل في حذف الغرفة', isError: true);
      }
    } catch (e) {
      log('خطأ في حذف الغرفة: $e');
      showSnackBar(context, 'فشل في حذف الغرفة', isError: true);
    }
  }

  // التحقق من حالة المستخدم
  Future<void> checkUserStatus(BuildContext context) async {
    if (playerId == null) return;

    try {
      final supabaseService = context.read<SupabaseService>();
      final status = await supabaseService.checkUserStatus(playerId!);
      currentUserStatus = status;

      if (status.inRoom) {
        log('المستخدم موجود في غرفة: ${status.roomName} (${status.roomId})');
      }
    } catch (e) {
      log('خطأ في التحقق من حالة المستخدم: $e');
    }
  }

  // حفظ اسم اللاعب
  Future<void> savePlayerName(String name) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('player_name', name);
      savedPlayerName = name;

      // تحديث/إنشاء الإحصائيات فوراً مع الاسم الجديد
      if (playerId != null) {
        final experienceService = ExperienceService();
        await experienceService.ensurePlayerStatsWithName(playerId!, name);
        log('تم حفظ اسم اللاعب وتحديث الإحصائيات: $name');
      }
    } catch (e) {
      log('خطأ في حفظ اسم اللاعب: $e');
    }
  }

  // تحميل البيانات المحفوظة
  Future<void> loadSavedData() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // تحميل الاسم المحفوظ
      final savedName = prefs.getString('player_name');
      if (savedName != null && savedName.isNotEmpty) {
        savedPlayerName = savedName;
        nameController.text = savedName;
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

      playerId = savedPlayerId;
    } catch (e) {
      log('خطأ في تحميل البيانات المحفوظة: $e');
      // إنشاء معرف طوارئ
      playerId = const Uuid().v4();
    }
  }

  // تهيئة إحصائيات اللاعب
  Future<void> initializePlayerStats() async {
    if (playerId == null || nameController.text.trim().isEmpty) return;

    try {
      final experienceService = ExperienceService();
      // استخدام الدالة الجديدة للتأكد من الإحصائيات مع الاسم
      await experienceService.ensurePlayerStatsWithName(
        playerId!,
        nameController.text.trim(),
      );
      log('تم تهيئة إحصائيات اللاعب بنجاح');
    } catch (e) {
      log('خطأ في تهيئة إحصائيات اللاعب: $e');
    }
  }

  // عرض رسالة SnackBar
  void showSnackBar(BuildContext context, String message, {bool isError = false}) {
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

  // تنظيف الموارد
  void dispose() {
    // تحديث حالة المستخدم كغير متصل عند الخروج
    if (playerId != null && nameController.text.trim().isNotEmpty) {
      onlineUsersService.updateUserStatus(
        playerId!,
        nameController.text.trim(),
        false,
      );
    }

    onlineUsersService.dispose();
    nameController.dispose();
    autoRefreshTimer?.cancel();
  }
}