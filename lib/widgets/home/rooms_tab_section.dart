import 'package:flutter/material.dart';

class RoomsTabSection extends StatelessWidget {
  final TabController tabController;
  final int availableRoomsCount;
  final int myRoomsCount;
  final AnimationController refreshController;
  final int totalConnectedUsers;
  final int totalActiveRooms;
  final VoidCallback onRefresh;

  const RoomsTabSection({
    super.key,
    required this.tabController,
    required this.availableRoomsCount,
    required this.myRoomsCount,
    required this.refreshController,
    required this.totalConnectedUsers,
    required this.totalActiveRooms,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
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
            controller: tabController,
            tabs: [
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.public),
                    const SizedBox(width: 8),
                    Text('الغرف العامة ($availableRoomsCount)'),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.person),
                    const SizedBox(width: 8),
                    Text('غرفي ($myRoomsCount)'),
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
              _buildStatsCard('المتصلون', '$totalConnectedUsers', Icons.people, Colors.green),
              _buildStatsCard('الغرف النشطة', '$totalActiveRooms', Icons.meeting_room, Colors.blue),
            ],
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _buildRefreshButton() {
    return AnimatedBuilder(
      animation: refreshController,
      builder: (context, child) {
        return GestureDetector(
          onTap: onRefresh,
          child: Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: const Color(0xFF667eea).withOpacity(0.1),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Transform.rotate(
              angle: refreshController.value * 2 * 3.14159,
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
}