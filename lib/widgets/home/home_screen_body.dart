import 'package:flutter/material.dart';
import 'package:voice_rooms_app/widgets/home/rooms_list_view.dart';
import 'package:voice_rooms_app/widgets/home/rooms_tab_section.dart';
import '../../models/game_room_model.dart';
import '../../services/player_service.dart';
import '../user/user_profile_widget.dart';
import 'create_room_fab.dart';
import 'current_room_banner.dart';
import 'home_header.dart';

class HomeScreenBody extends StatelessWidget {
  final TabController tabController;
  final AnimationController refreshController;
  final AnimationController floatingController;
  final TextEditingController nameController;
  final List<GameRoom> availableRooms;
  final List<GameRoom> myRooms;
  final bool isLoading;
  final UserStatus? currentUserStatus;
  final String? playerId;
  final VoidCallback onShowOnlineUsers;
  final VoidCallback onRefresh;
  final VoidCallback onCreateRoom;
  final VoidCallback onRejoinRoom;
  final Function(GameRoom) onJoinRoom;
  final Function(GameRoom) onDeleteRoom;
  final VoidCallback onLogout;
  final VoidCallback onStatsPressed;

  const HomeScreenBody({
    super.key,
    required this.tabController,
    required this.refreshController,
    required this.floatingController,
    required this.nameController,
    required this.availableRooms,
    required this.myRooms,
    required this.isLoading,
    required this.currentUserStatus,
    required this.playerId,
    required this.onShowOnlineUsers,
    required this.onRefresh,
    required this.onCreateRoom,
    required this.onRejoinRoom,
    required this.onJoinRoom,
    required this.onDeleteRoom,
    required this.onLogout,
    required this.onStatsPressed,
  });

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

              // زر المستخدمين المتصلين
              if (nameController.text.trim().isNotEmpty)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: onShowOnlineUsers,
                          icon: const Icon(Icons.people, color: Colors.white),
                          label: const Text(
                            'المستخدمون المتصلون',
                            style: TextStyle(color: Colors.white),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.deepPurple,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // شعار الغرفة الحالية
              if (currentUserStatus?.inRoom == true)
                CurrentRoomBanner(
                  userStatus: currentUserStatus!,
                  onRejoinRoom: onRejoinRoom,
                ),

              // معلومات المستخدم
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: UserProfileWidget(
                  showLogoutButton: true,
                  onLogout: onLogout,
                ),
              ),

              // تبويبات الغرف
              RoomsTabSection(
                tabController: tabController,
                availableRoomsCount: availableRooms.length,
                myRoomsCount: myRooms.length,
                refreshController: refreshController,
                totalConnectedUsers: availableRooms.fold(0, (sum, room) => sum + room.players.length),
                totalActiveRooms: availableRooms.length + myRooms.length,
                onRefresh: onRefresh,
              ),

              // قائمة الغرف
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
                    controller: tabController,
                    children: [
                      RoomsListView(
                        rooms: availableRooms,
                        isLoading: isLoading,
                        isMyRooms: false,
                        currentUserStatus: currentUserStatus,
                        onJoinRoom: onJoinRoom,
                        onDeleteRoom: onDeleteRoom,
                      ),
                      RoomsListView(
                        rooms: myRooms,
                        isLoading: isLoading,
                        isMyRooms: true,
                        currentUserStatus: currentUserStatus,
                        onJoinRoom: onJoinRoom,
                        onDeleteRoom: onDeleteRoom,
                      ),
                    ],
                  ),
                ),
              ),

              // زر الإحصائيات
              FloatingActionButton.extended(
                onPressed: onStatsPressed,
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
        controller: floatingController,
        canCreate: currentUserStatus?.inRoom != true && nameController.text.trim().isNotEmpty,
        isInRoom: currentUserStatus?.inRoom == true,
        onCreateRoom: onCreateRoom,
      ),
    );
  }
}