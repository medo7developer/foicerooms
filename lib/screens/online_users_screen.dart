// lib/screens/online_users_screen.dart
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';

import '../providers/game_provider.dart';
import '../services/supabase_service.dart';
import '../services/user_services/online_users_service.dart';
import 'game_screen.dart';

class OnlineUsersScreen extends StatefulWidget {
  final String currentPlayerId;
  final String currentPlayerName;
  final String? currentRoomId;
  final String? currentRoomName;

  const OnlineUsersScreen({
    super.key,
    required this.currentPlayerId,
    required this.currentPlayerName,
    this.currentRoomId,
    this.currentRoomName,
  });

  @override
  State<OnlineUsersScreen> createState() => _OnlineUsersScreenState();
}

class _OnlineUsersScreenState extends State<OnlineUsersScreen> with TickerProviderStateMixin {
  final OnlineUsersService _onlineUsersService = OnlineUsersService();
  late TabController _tabController;

  List<OnlineUser> _onlineUsers = [];
  List<Invitation> _pendingInvitations = [];
  bool _isLoading = true;

  StreamSubscription? _usersSubscription;
  StreamSubscription? _invitationsSubscription;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initializeData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _usersSubscription?.cancel();
    _invitationsSubscription?.cancel();
    _onlineUsersService.dispose();
    super.dispose();
  }

  Future<void> _initializeData() async {
    try {
      // الاستماع للمستخدمين المتصلين
      _usersSubscription = _onlineUsersService
          .listenToOnlineUsers(widget.currentPlayerId)
          .listen((users) {
        if (mounted) {
          setState(() {
            _onlineUsers = users;
            _isLoading = false;
          });
        }
      });

      // الاستماع للدعوات
      _invitationsSubscription = _onlineUsersService
          .listenToInvitations(widget.currentPlayerId)
          .listen((invitations) {
        if (mounted) {
          setState(() => _pendingInvitations = invitations);
        }
      });

      // تنظيف الدعوات القديمة
      await _onlineUsersService.cleanupOldInvitations();
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnackBar('خطأ في تحميل البيانات', isError: true);
      }
    }
  }

  Future<void> _sendInvitation(OnlineUser user) async {
    if (widget.currentRoomId == null || widget.currentRoomName == null) {
      _showSnackBar('يجب أن تكون في غرفة لإرسال دعوات', isError: true);
      return;
    }

    final success = await _onlineUsersService.sendInvitation(
      fromPlayerId: widget.currentPlayerId,
      fromPlayerName: widget.currentPlayerName,
      toPlayerId: user.id,
      roomId: widget.currentRoomId!,
      roomName: widget.currentRoomName!,
    );

    if (success) {
      _showSnackBar('تم إرسال دعوة إلى ${user.name}');
    } else {
      _showSnackBar('فشل في إرسال الدعوة', isError: true);
    }
  }

// استبدال دالة _respondToInvitation في ملف lib/screens/online_users_screen.dart

  Future<void> _respondToInvitation(Invitation invitation, bool accept) async {
    final status = accept ? 'accepted' : 'declined';
    final success = await _onlineUsersService.respondToInvitation(invitation.id, status);

    if (success && accept) {
      // إظهار مؤشر التحميل
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
              Text('جاري الانضمام لغرفة "${invitation.roomName}"...'),
            ],
          ),
        ),
      );

      try {
        // استيراد SupabaseService إذا لم يكن موجوداً
        final supabaseService = context.read<SupabaseService>();

        // محاولة الانضمام في الخادم أولاً (تماماً مثل home_screen.dart)
        final result = await supabaseService.joinRoom(
          invitation.roomId,
          widget.currentPlayerId,
          widget.currentPlayerName,
        );

        // إغلاق مؤشر التحميل
        Navigator.pop(context);

        if (result.success) {
          // انتظار قصير للتأكد من تحديث قاعدة البيانات
          await Future.delayed(const Duration(milliseconds: 500));

          // تحديث حالة المستخدم عند الانضمام
          await _onlineUsersService.updateUserStatus(
            widget.currentPlayerId,
            widget.currentPlayerName,
            true,
            roomId: invitation.roomId,
            roomName: invitation.roomName,
          );

          // جلب بيانات الغرفة المحدثة من الخادم
          final updatedRoom = await supabaseService.getRoomById(invitation.roomId);

          if (updatedRoom != null) {
            // محاولة الانضمام في GameProvider بالبيانات المحدثة
            final gameProvider = context.read<GameProvider>();
            final localSuccess = gameProvider.joinRoom(
                updatedRoom.id,
                widget.currentPlayerId,
                widget.currentPlayerName
            );

            if (localSuccess) {
              _showSnackBar('تم قبول الدعوة والانضمام للغرفة');

              // الانتقال لشاشة اللعبة
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => GameScreen(playerId: widget.currentPlayerId),
                ),
              ).then((_) {
                // عند العودة من شاشة اللعبة، العودة للشاشة السابقة
                Navigator.pop(context, true);
              });
            } else {
              _showSnackBar('انضممت للغرفة في الخادم، جاري تحديث البيانات...', isError: false);
              // العودة مع نتيجة النجاح للتحديث
              Navigator.pop(context, true);
            }
          } else {
            _showSnackBar('انضممت للغرفة، جاري تحديث البيانات...', isError: false);
            Navigator.pop(context, true);
          }
        } else {
          _showSnackBar(result.reason, isError: true);
          // إذا كان المستخدم في غرفة أخرى، تحديث الحالة
          if (result.existingRoomId != null) {
            await _onlineUsersService.updateUserStatus(
              widget.currentPlayerId,
              widget.currentPlayerName,
              true,
              roomId: result.existingRoomId,
              roomName: 'غرفة أخرى',
            );
          }
        }
      } catch (e) {
        // إغلاق مؤشر التحميل في حالة الخطأ
        Navigator.pop(context);
        log('خطأ في الانضمام للغرفة من الدعوة: $e');
        _showSnackBar('خطأ في الاتصال، يرجى المحاولة مرة أخرى', isError: true);
      }
    } else if (success) {
      _showSnackBar('تم رفض الدعوة');
    } else {
      _showSnackBar('خطأ في الرد على الدعوة', isError: true);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('المستخدمون المتصلون'),
        backgroundColor: Colors.purple,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: [
            Tab(
              icon: const Icon(Icons.people),
              text: 'المتصلون (${_onlineUsers.length})',
            ),
            Tab(
              icon: const Icon(Icons.mail),
              text: 'الدعوات (${_pendingInvitations.length})',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOnlineUsersTab(),
          _buildInvitationsTab(),
        ],
      ),
    );
  }

  Widget _buildOnlineUsersTab() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_onlineUsers.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 80, color: Colors.grey),
            SizedBox(height: 16),
            Text('لا يوجد مستخدمون متصلون حالياً'),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _onlineUsers.length,
      itemBuilder: (context, index) => _buildUserCard(_onlineUsers[index]),
    );
  }

  Widget _buildInvitationsTab() {
    if (_pendingInvitations.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.mail_outline, size: 80, color: Colors.grey),
            SizedBox(height: 16),
            Text('لا توجد دعوات معلقة'),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _pendingInvitations.length,
      itemBuilder: (context, index) => _buildInvitationCard(_pendingInvitations[index]),
    );
  }

  Widget _buildUserCard(OnlineUser user) {
    final canInvite = widget.currentRoomId != null &&
        !user.isInGame &&
        user.currentRoomId != widget.currentRoomId;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: user.isInGame ? Colors.orange : Colors.green,
          child: Text(
            user.name[0].toUpperCase(),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(
          user.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  user.isInGame ? Icons.sports_esports : Icons.circle,
                  size: 12,
                  color: user.isInGame ? Colors.orange : Colors.green,
                ),
                const SizedBox(width: 4),
                Text(
                  user.isInGame ? 'في لعبة' : 'متاح',
                  style: TextStyle(
                    fontSize: 12,
                    color: user.isInGame ? Colors.orange : Colors.green,
                  ),
                ),
              ],
            ),
            if (user.isInGame && user.currentRoomName != null) ...[
              const SizedBox(height: 2),
              Text(
                'غرفة: ${user.currentRoomName}',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ],
        ),
        trailing: canInvite
            ? ElevatedButton.icon(
          onPressed: () => _sendInvitation(user),
          icon: const Icon(Icons.send, size: 16),
          label: const Text('دعوة'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          ),
        )
            : Chip(
          label: Text(
            user.isInGame ? 'مشغول' :
            user.currentRoomId == widget.currentRoomId ? 'في نفس الغرفة' : 'غير متاح',
            style: const TextStyle(fontSize: 10),
          ),
          backgroundColor: Colors.grey.shade200,
        ),
      ),
    );
  }

  Widget _buildInvitationCard(Invitation invitation) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: Colors.blue,
                  child: Text(
                    invitation.fromPlayerName[0].toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'دعوة من ${invitation.fromPlayerName}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        'للانضمام لغرفة "${invitation.roomName}"',
                        style: const TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => _respondToInvitation(invitation, false),
                  child: const Text('رفض'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => _respondToInvitation(invitation, true),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  child: const Text('قبول', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}