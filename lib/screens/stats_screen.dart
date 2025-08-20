// ملف: lib/screens/stats_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/experience_models.dart';
import '../services/experience_service.dart';
import '../providers/game_provider.dart';

class StatsScreen extends StatefulWidget {
  final String playerId;

  const StatsScreen({super.key, required this.playerId});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> with TickerProviderStateMixin {
  late TabController _tabController;
  final ExperienceService _experienceService = ExperienceService();

  PlayerStats? _playerStats;
  List<LeaderboardEntry> _leaderboard = [];
  List<LeaderboardEntry> _topSpies = [];
  List<LeaderboardEntry> _topDetectives = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      // تحميل إحصائيات اللاعب
      _playerStats = await _experienceService.getPlayerStats(widget.playerId);

      // تحميل قوائم المتصدرين
      final results = await Future.wait([
        _experienceService.getLeaderboard(limit: 50),
        _experienceService.getTopPlayersByCategory(category: 'spy_wins', limit: 20),
        _experienceService.getTopPlayersByCategory(category: 'times_detected_spy', limit: 20),
      ]);

      _leaderboard = results[0];
      _topSpies = results[1];
      _topDetectives = results[2];

    } catch (e) {
      debugPrint('خطأ في تحميل البيانات: $e');
    } finally {
      setState(() => _isLoading = false);
    }
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
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              _buildTabBar(),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: Colors.white))
                    : _buildTabContent(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back, color: Colors.white),
          ),
          const SizedBox(width: 10),
          const Text(
            'الإحصائيات والمتصدرين',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(25),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(25),
        ),
        labelColor: Colors.purple,
        unselectedLabelColor: Colors.white,
        labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        tabs: const [
          Tab(text: 'إحصائياتي'),
          Tab(text: 'المتصدرين'),
          Tab(text: 'أفضل الجواسيس'),
          Tab(text: 'أفضل الكاشفين'),
        ],
      ),
    );
  }

  Widget _buildTabContent() {
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
      child: TabBarView(
        controller: _tabController,
        children: [
          _buildMyStatsTab(),
          _buildLeaderboardTab(_leaderboard, 'أفضل اللاعبين عموماً'),
          _buildLeaderboardTab(_topSpies, 'أفضل الجواسيس المتخفين'),
          _buildLeaderboardTab(_topDetectives, 'أفضل كاشفي الجواسيس'),
        ],
      ),
    );
  }

  Widget _buildMyStatsTab() {
    if (_playerStats == null) {
      return const Center(child: Text('لا توجد إحصائيات متاحة'));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildLevelCard(_playerStats!),
          const SizedBox(height: 20),
          _buildStatsGrid(_playerStats!),
          const SizedBox(height: 20),
          _buildBadgesSection(_playerStats!),
        ],
      ),
    );
  }

  Widget _buildLevelCard(PlayerStats stats) {
    final currentLevelXP = stats.totalXP % RewardConstants.xpPerLevel;
    final progress = currentLevelXP / RewardConstants.xpPerLevel;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade400, Colors.purple.shade400],
        ),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: Colors.white,
                child: Text(
                  '${stats.level}',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.purple,
                  ),
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'المستوى الحالي',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    Text(
                      'مستوى ${stats.level}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${stats.totalXP} XP',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          LinearProgressIndicator(
            value: progress,
            backgroundColor: Colors.white30,
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
          ),
          const SizedBox(height: 5),
          Text(
            'التقدم نحو المستوى التالي: $currentLevelXP/${RewardConstants.xpPerLevel}',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsGrid(PlayerStats stats) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'الإحصائيات التفصيلية',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 15),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 15,
          crossAxisSpacing: 15,
          childAspectRatio: 1.5,
          children: [
            _buildStatCard('إجمالي الألعاب', '${stats.totalGames}', Icons.sports_esports, Colors.blue),
            _buildStatCard('الانتصارات', '${stats.wins}', Icons.emoji_events, Colors.green),
            _buildStatCard('معدل الفوز', '${stats.winRate.toStringAsFixed(1)}%', Icons.trending_up, Colors.orange),
            _buildStatCard('انتصارات التجسس', '${stats.spyWins}', Icons.psychology, Colors.purple),
            _buildStatCard('انتصارات الكشف', '${stats.detectiveWins}', Icons.search, Colors.teal),
            _buildStatCard('معدل كشف الجواسيس', '${stats.detectiveSuccessRate.toStringAsFixed(1)}%', Icons.visibility, Colors.indigo),
          ],
        ),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 30),
          const SizedBox(height: 8),
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
              color: Colors.grey.shade600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildBadgesSection(PlayerStats stats) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'الشارات المكتسبة',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 15),
        stats.badges.isEmpty
            ? Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Center(
            child: Text(
              'لم تحصل على أي شارات بعد\nاستمر في اللعب لكسب الشارات!',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ),
        )
            : Wrap(
          spacing: 15,
          runSpacing: 15,
          children: stats.badges.entries
              .map((entry) => _buildBadgeItem(entry.key, entry.value))
              .toList(),
        ),
      ],
    );
  }

  Widget _buildBadgeItem(BadgeType badgeType, int count) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: BadgeUtils.getBadgeColor(badgeType).withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: BadgeUtils.getBadgeColor(badgeType).withOpacity(0.3),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            BadgeUtils.getBadgeIcon(badgeType),
            color: BadgeUtils.getBadgeColor(badgeType),
            size: 40,
          ),
          const SizedBox(height: 8),
          Text(
            BadgeUtils.getBadgeName(badgeType),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: BadgeUtils.getBadgeColor(badgeType),
            ),
            textAlign: TextAlign.center,
          ),
          Text(
            BadgeUtils.getBadgeDescription(badgeType),
            style: const TextStyle(
              fontSize: 10,
              color: Colors.grey,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildLeaderboardTab(List<LeaderboardEntry> entries, String title) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.purple.shade50,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.purple,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        Expanded(
          child: entries.isEmpty
              ? const Center(child: Text('لا توجد بيانات متاحة'))
              : ListView.builder(
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[index];
              final isCurrentPlayer = entry.playerId == widget.playerId;
              return _buildLeaderboardItem(entry, isCurrentPlayer);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLeaderboardItem(LeaderboardEntry entry, bool isCurrentPlayer) {
    Color rankColor = Colors.grey;
    if (entry.rank == 1) rankColor = Colors.amber;
    if (entry.rank == 2) rankColor = Colors.grey.shade400;
    if (entry.rank == 3) rankColor = Colors.brown;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: isCurrentPlayer ? Colors.purple.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCurrentPlayer ? Colors.purple : Colors.grey.shade200,
          width: isCurrentPlayer ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: rankColor,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '${entry.rank}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      entry.playerName,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isCurrentPlayer ? Colors.purple : Colors.black,
                      ),
                    ),
                    if (isCurrentPlayer) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.purple,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'أنت',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Text(
                      'مستوى ${entry.level}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${entry.totalXP} XP',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.blue,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${entry.wins} فوز',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
              Text(
                '${entry.winRate.toStringAsFixed(1)}%',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}