import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:developer';

import '../providers/game_provider.dart';
import '../services/supabase_service.dart';
import '../screens/game_screen.dart';
import 'home_screen_state.dart';

mixin HomeScreenActions {

  Future<void> initializeApp(BuildContext context, HomeScreenState state,
      AnimationController refreshController) async {
    await loadSavedData(state);
    await checkUserStatus(context, state);
    await loadAvailableRooms(context, state, refreshController);
  }

  Future<void> loadSavedData(HomeScreenState state) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // تحميل الاسم المحفوظ
      final savedName = prefs.getString('player_name');
      if (savedName != null && savedName.isNotEmpty) {
        state.savedPlayerName = savedName;
        state.nameController.text = savedName;
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

      state.playerId = savedPlayerId;
    } catch (e) {
      log('خطأ في تحميل البيانات المحفوظة: $e');
      state.playerId = const Uuid().v4();
    }
  }

  Future<void> checkUserStatus(BuildContext context,
      HomeScreenState state) async {
    if (state.playerId == null) return;

    try {
      final supabaseService = context.read<SupabaseService>();
      final status = await supabaseService.checkUserStatus(state.playerId!);

      state.currentUserStatus = status;

      if (status.inRoom) {
        log('المستخدم موجود في غرفة: ${status.roomName} (${status.roomId})');
        _showUserInRoomDialog(context, state);
      }
    } catch (e) {
      log('خطأ في التحقق من حالة المستخدم: $e');
    }
  }

  void _showUserInRoomDialog(BuildContext context, HomeScreenState state) {
    if (state.currentUserStatus?.inRoom != true) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
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
                const Text('أنت موجود حالياً في غرفة:'),
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
                        state.currentUserStatus?.isOwner == true
                            ? Icons.star
                            : Icons.meeting_room,
                        color: Colors.blue,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              state.currentUserStatus?.roomName ?? 'غير معروف',
                              style: const TextStyle(fontWeight: FontWeight
                                  .bold),
                            ),
                            Text(
                              state.currentUserStatus?.isOwner == true
                                  ? 'أنت مالك الغرفة'
                                  : 'أنت عضو في الغرفة',
                              style: const TextStyle(fontSize: 12, color: Colors
                                  .grey),
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
                  leaveCurrentRoom(context, state);
                },
                child: const Text(
                    'مغادرة الغرفة', style: TextStyle(color: Colors.red)),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  rejoinRoom(context, state);
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                child: const Text(
                    'العودة للغرفة', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
    );
  }

// استبدال دالة rejoinRoom:
  Future<void> rejoinRoom(BuildContext context, HomeScreenState state) async {
    if (state.currentUserStatus?.roomId == null || state.playerId == null) return;

    try {
      // حفظ المراجع قبل العمليات غير المتزامنة
      final gameProvider = context.read<GameProvider>();
      final supabaseService = context.read<SupabaseService>();
      final navigator = Navigator.of(context);
      final scaffoldMessenger = ScaffoldMessenger.of(context);

      // محاولة إعادة الانضمام للغرفة
      final room = await supabaseService.getRoomById(state.currentUserStatus!.roomId!);

      if (room != null && context.mounted) {
        gameProvider.rejoinRoom(room, state.playerId!);

        navigator.push(
          MaterialPageRoute(
            builder: (context) => GameScreen(playerId: state.playerId!),
          ),
        );
      } else {
        if (context.mounted) {
          scaffoldMessenger.showSnackBar(
            const SnackBar(
              content: Text('الغرفة غير موجودة'),
              backgroundColor: Colors.red,
            ),
          );
        }
        state.currentUserStatus = UserStatus.free;
      }
    } catch (e) {
      log('خطأ في إعادة الانضمام: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('فشل في العودة للغرفة'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> leaveCurrentRoom(BuildContext context,
      HomeScreenState state) async {
    if (state.playerId == null) return;

    try {
      final supabaseService = context.read<SupabaseService>();
      await supabaseService.leaveRoom(state.playerId!);

      state.currentUserStatus = UserStatus.free;
      showSnackBar(context, 'تم مغادرة الغرفة');

      // إعادة تحميل القوائم - نحتاج refreshController هنا
    } catch (e) {
      log('خطأ في مغادرة الغرفة: $e');
      showSnackBar(context, 'فشل في مغادرة الغرفة', isError: true);
    }
  }

  Future<void> savePlayerName(HomeScreenState state, String name) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('player_name', name);
      state.savedPlayerName = name;
      log('تم حفظ اسم اللاعب: $name');
    } catch (e) {
      log('خطأ في حفظ اسم اللاعب: $e');
    }
  }

  Future<void> loadAvailableRooms(BuildContext context, HomeScreenState state,
      AnimationController refreshController) async {
    if (state.playerId == null) {
      log('معرف اللاعب غير متاح');
      return;
    }

    state.isLoading = true;
    refreshController.forward();

    try {
      final supabaseService = context.read<SupabaseService>();
      final allRooms = await supabaseService.getAvailableRooms();

      final availableRooms = <GameRoom>[];
      final myRooms = <GameRoom>[];

      for (final room in allRooms) {
        if (room.creatorId == state.playerId) {
          myRooms.add(room);
        } else {
          final isPlayerInRoom = room.players.any((player) =>
          player.id == state.playerId);
          if (!isPlayerInRoom) {
            availableRooms.add(room);
          }
        }
      }

      state.availableRooms = availableRooms;
      state.myRooms = myRooms;
      state.isLoading = false;

      log('تم تحميل ${allRooms.length} غرفة، منها ${myRooms
          .length} غرف خاصة بي و ${availableRooms.length} غرف متاحة');
    } catch (e) {
      log('خطأ في تحميل الغرف: $e');
      state.isLoading = false;
    } finally {
      refreshController.reset();
    }
  }

  Future<void> joinRoom(BuildContext context, HomeScreenState state,
      GameRoom room) async {
    // التحقق من صحة البيانات
    if (state.nameController.text
        .trim()
        .isEmpty) {
      showSnackBar(context, 'يرجى إدخال اسمك أولاً', isError: true);
      return;
    }

    if (state.playerId == null) {
      showSnackBar(context, 'خطأ في معرف اللاعب، يرجى إعادة تشغيل التطبيق',
          isError: true);
      return;
    }

    // التحقق من حالة المستخدم الحالية
    if (state.currentUserStatus?.inRoom == true) {
      showSnackBar(context, 'يجب مغادرة الغرفة الحالية أولاً', isError: true);
      return;
    }

    await savePlayerName(state, state.nameController.text.trim());

    // عرض مؤشر التحميل
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15)),
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

      final result = await supabaseService.joinRoom(
        room.id,
        state.playerId!,
        state.nameController.text.trim(),
      );

      // إغلاق مؤشر التحميل
      Navigator.pop(context);

      if (result.success) {
        // محاولة الانضمام في GameProvider
        final success = gameProvider.joinRoom(
            room.id, state.playerId!, state.nameController.text.trim());

        if (success) {
          // تحديث حالة المستخدم
          state.currentUserStatus = UserStatus(
            inRoom: true,
            roomId: room.id,
            roomName: room.name,
            isOwner: false,
            roomState: 'waiting',
          );

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => GameScreen(playerId: state.playerId!),
            ),
          ).then((_) {
            // عند العودة من شاشة اللعبة، تحديث الحالة
            checkUserStatus(context, state);
          });
        } else {
          showSnackBar(context, 'فشل في الانضمام للغرفة محلياً', isError: true);
        }
      } else {
        showSnackBar(context, result.reason, isError: true);

        // إذا كان المستخدم في غرفة أخرى، تحديث الحالة
        if (result.existingRoomId != null) {
          checkUserStatus(context, state);
        }
      }
    } catch (e) {
      // إغلاق مؤشر التحميل في حالة الخطأ
      Navigator.pop(context);
      log('خطأ في الانضمام للغرفة: $e');
      showSnackBar(
          context, 'خطأ في الاتصال، يرجى المحاولة مرة أخرى', isError: true);
    }
  }

  Future<void> deleteRoom(BuildContext context, HomeScreenState state,
      GameRoom room) async {
    final confirmed = await _showDeleteDialog(context, room);
    if (confirmed == true && state.playerId != null) {
      final supabaseService = context.read<SupabaseService>();
      final success = await supabaseService.deleteRoom(
          room.id, state.playerId!);

      if (success) {
        showSnackBar(context, 'تم حذف الغرفة بنجاح');
      } else {
        showSnackBar(context, 'فشل في حذف الغرفة', isError: true);
      }
    }
  }

  Future<bool?> _showDeleteDialog(BuildContext context, GameRoom room) {
    return showDialog<bool>(
      context: context,
      builder: (context) =>
          AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(
                20)),
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

  void showSnackBar(BuildContext context, String message,
      {bool isError = false}) {
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
}