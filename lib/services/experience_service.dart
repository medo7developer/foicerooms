// ملف: lib/services/experience_service.dart - النسخة المحسنة
import 'dart:developer';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/experience_models.dart';
import '../models/game_room_model.dart';
import '../providers/game_provider.dart';

class ExperienceService {
  final SupabaseClient _client = Supabase.instance.client;

  /// التأكد من وجود اللاعب في جدول players قبل إنشاء الإحصائيات
  Future<void> _ensurePlayerExists(String playerId, String playerName) async {
    try {
      // التحقق من وجود اللاعب
      final existingPlayer = await _client
          .from('players')
          .select('id')
          .eq('id', playerId)
          .maybeSingle();

      if (existingPlayer == null) {
        // إنشاء سجل اللاعب إذا لم يكن موجوداً
        await _client.from('players').upsert({
          'id': playerId,
          'name': playerName,
          'is_connected': false,
          'is_voted': false,
          'votes': 0,
          'role': 'normal',
          'room_id': null, // لا يوجد في غرفة حالياً
        });
        log('تم إنشاء سجل جديد للاعب: $playerId');
      } else {
        // تحديث الاسم إذا كان اللاعب موجوداً
        await _client.from('players')
            .update({'name': playerName})
            .eq('id', playerId);
      }
    } catch (e) {
      log('خطأ في التأكد من وجود اللاعب: $e');
    }
  }

  /// الحصول على إحصائيات اللاعب
  Future<PlayerStats?> getPlayerStats(String playerId, {String? playerName}) async {
    try {
      final response = await _client
          .from('player_stats')
          .select()
          .eq('player_id', playerId)
          .maybeSingle();

      if (response == null) {
        // إنشاء إحصائيات جديدة للاعب
        return await _createNewPlayerStats(playerId, playerName ?? 'لاعب مجهول');
      }

      return PlayerStats.fromJson(response);
    } catch (e) {
      log('خطأ في جلب إحصائيات اللاعب: $e');
      return null;
    }
  }

  /// إنشاء إحصائيات جديدة للاعب
  Future<PlayerStats> _createNewPlayerStats(String playerId, String playerName) async {
    try {
      // التأكد من وجود اللاعب في جدول players أولاً
      await _ensurePlayerExists(playerId, playerName);

      final newStats = PlayerStats(
        playerId: playerId,
        playerName: playerName,
        lastUpdated: DateTime.now(),
      );

      // محاولة إنشاء الإحصائيات
      final statsData = newStats.toJson();

      await _client.from('player_stats').insert(statsData);
      log('تم إنشاء إحصائيات جديدة للاعب: $playerId');
      return newStats;

    } catch (e) {
      log('خطأ في إنشاء إحصائيات اللاعب: $e');

      // إذا فشل الإنشاء، إرجاع إحصائيات افتراضية
      return PlayerStats(
        playerId: playerId,
        playerName: playerName,
        lastUpdated: DateTime.now(),
      );
    }
  }

  /// معالجة نتيجة اللعبة وتحديث الإحصائيات
  Future<List<GameReward>> processGameResult({
    required String playerId,
    required String playerName,
    required bool won,
    required bool wasSpy,
    required bool detectedSpy,
    required bool survived,
  }) async {
    try {
      // التأكد من وجود اللاعب أولاً
      await _ensurePlayerExists(playerId, playerName);

      final currentStats = await getPlayerStats(playerId, playerName: playerName);
      if (currentStats == null) {
        log('فشل في الحصول على إحصائيات اللاعب: $playerId');
        return [];
      }

      final rewards = <GameReward>[];
      int xpGained = 0;

      // حساب الخبرة الأساسية
      if (won) {
        xpGained += RewardConstants.xpForWin;
        rewards.add(GameReward(
          type: RewardType.xp,
          xpAmount: RewardConstants.xpForWin,
          description: 'مكافأة الفوز',
        ));
      } else {
        xpGained += RewardConstants.xpForLoss;
        rewards.add(GameReward(
          type: RewardType.xp,
          xpAmount: RewardConstants.xpForLoss,
          description: 'مكافأة المشاركة',
        ));
      }

      // مكافآت إضافية
      if (won && wasSpy) {
        xpGained += RewardConstants.xpForSpyWin;
        rewards.add(GameReward(
          type: RewardType.xp,
          xpAmount: RewardConstants.xpForSpyWin,
          description: 'فوز ماهر كجاسوس',
        ));
      }

      if (won && !wasSpy) {
        xpGained += RewardConstants.xpForDetectivWin;
        rewards.add(GameReward(
          type: RewardType.xp,
          xpAmount: RewardConstants.xpForDetectivWin,
          description: 'كشف الجاسوس بنجاح',
        ));
      }

      if (survived) {
        xpGained += RewardConstants.xpForSurviving;
        rewards.add(GameReward(
          type: RewardType.xp,
          xpAmount: RewardConstants.xpForSurviving,
          description: 'البقاء حتى النهاية',
        ));
      }

      // تحديث الإحصائيات
      final updatedStats = currentStats.copyWith(
        playerName: playerName, // تحديث الاسم
        totalGames: currentStats.totalGames + 1,
        wins: won ? currentStats.wins + 1 : currentStats.wins,
        losses: !won ? currentStats.losses + 1 : currentStats.losses,
        spyWins: (won && wasSpy) ? currentStats.spyWins + 1 : currentStats.spyWins,
        detectiveWins: (won && !wasSpy) ? currentStats.detectiveWins + 1 : currentStats.detectiveWins,
        timesWasSpy: wasSpy ? currentStats.timesWasSpy + 1 : currentStats.timesWasSpy,
        timesDetectedSpy: detectedSpy ? currentStats.timesDetectedSpy + 1 : currentStats.timesDetectedSpy,
        totalXP: currentStats.totalXP + xpGained,
        level: ((currentStats.totalXP + xpGained) / RewardConstants.xpPerLevel).floor() + 1,
        lastUpdated: DateTime.now(),
      );

      // التحقق من الشارات الجديدة
      final newBadges = await _checkForNewBadges(currentStats, updatedStats);
      rewards.addAll(newBadges);

      // حفظ الإحصائيات المحدثة
      final finalStats = updatedStats.copyWith(
          badges: updatedStats.badges.isEmpty ?
          newBadges.where((r) => r.type == RewardType.badge)
              .fold<Map<BadgeType, int>>({}, (map, reward) {
            if (reward.badgeType != null) {
              map[reward.badgeType!] = 1;
            }
            return map;
          }) : updatedStats.badges
      );

      await _savePlayerStats(finalStats);

      log('تم تحديث إحصائيات اللاعب $playerId - XP: +$xpGained');
      return rewards;
    } catch (e) {
      log('خطأ في معالجة نتيجة اللعبة: $e');
      return [];
    }
  }

  /// التحقق من الشارات الجديدة
  Future<List<GameReward>> _checkForNewBadges(PlayerStats oldStats, PlayerStats newStats) async {
    final rewards = <GameReward>[];

    // شارة ماستر الجواسيس
    if (newStats.spyWins >= RewardConstants.spyWinsForMaster &&
        (oldStats.badges[BadgeType.masterSpy] ?? 0) == 0) {
      rewards.add(GameReward(
        type: RewardType.badge,
        badgeType: BadgeType.masterSpy,
        description: 'حصلت على شارة ${BadgeUtils.getBadgeName(BadgeType.masterSpy)}',
        isNew: true,
      ));
    }

    // شارة صائد الجواسيس
    if (newStats.timesDetectedSpy >= RewardConstants.detectionsForHunter &&
        (oldStats.badges[BadgeType.spyHunter] ?? 0) == 0) {
      rewards.add(GameReward(
        type: RewardType.badge,
        badgeType: BadgeType.spyHunter,
        description: 'حصلت على شارة ${BadgeUtils.getBadgeName(BadgeType.spyHunter)}',
        isNew: true,
      ));
    }

    // شارة المحقق البارع
    if (newStats.detectiveSuccessRate >= RewardConstants.detectiveRateForSharp &&
        newStats.totalGames >= 10 &&
        (oldStats.badges[BadgeType.sharpDetective] ?? 0) == 0) {
      rewards.add(GameReward(
        type: RewardType.badge,
        badgeType: BadgeType.sharpDetective,
        description: 'حصلت على شارة ${BadgeUtils.getBadgeName(BadgeType.sharpDetective)}',
        isNew: true,
      ));
    }

    return rewards;
  }

  /// حفظ إحصائيات اللاعب مع معالجة الأخطاء
  Future<bool> _savePlayerStats(PlayerStats stats) async {
    try {
      await _client.from('player_stats').upsert(stats.toJson());
      return true;
    } catch (e) {
      log('خطأ في حفظ إحصائيات اللاعب: $e');

      // محاولة إعادة إنشاء السجل
      try {
        await _ensurePlayerExists(stats.playerId, stats.playerName);
        await _client.from('player_stats').insert(stats.toJson());
        return true;
      } catch (e2) {
        log('فشل في إعادة إنشاء إحصائيات اللاعب: $e2');
        return false;
      }
    }
  }

  /// الحصول على قائمة المتصدرين مع معالجة محسنة للأخطاء
  Future<List<LeaderboardEntry>> getLeaderboard({int limit = 50}) async {
    try {
      final response = await _client
          .from('player_stats')
          .select('*')
          .order('total_xp', ascending: false)
          .limit(limit);

      if (response.isEmpty) {
        log('لا توجد بيانات في جدول player_stats');
        return [];
      }

      final entries = <LeaderboardEntry>[];

      for (int i = 0; i < response.length; i++) {
        try {
          final data = response[i];

          entries.add(LeaderboardEntry(
            playerId: data['player_id'] ?? '',
            playerName: data['player_name'] ?? 'لاعب مجهول',
            totalXP: (data['total_xp'] as num?)?.toInt() ?? 0,
            level: (data['level'] as num?)?.toInt() ?? 1,
            wins: (data['wins'] as num?)?.toInt() ?? 0,
            winRate: _calculateWinRate(data),
            badges: _parseBadges(data['badges']),
            rank: i + 1,
          ));
        } catch (itemError) {
          log('خطأ في معالجة عنصر المتصدرين: $itemError');
          continue;
        }
      }

      log('تم جلب ${entries.length} عنصر في قائمة المتصدرين');
      return entries;
    } catch (e) {
      log('خطأ في جلب قائمة المتصدرين: $e');
      return [];
    }
  }

  /// الحصول على أفضل اللاعبين في فئة معينة
  Future<List<LeaderboardEntry>> getTopPlayersByCategory({
    required String category,
    int limit = 10,
  }) async {
    try {
      final List<Map<String, dynamic>> response = await _client
          .from('player_stats')
          .select('*')
          .gt(category, 0) // ✅ الفلترة الأول
          .order(category, ascending: false) // ✅ الترتيب بعد الفلترة
          .limit(limit);

      if (response.isEmpty) {
        log('لا توجد بيانات في فئة $category');
        return [];
      }

      final entries = <LeaderboardEntry>[];
      for (int i = 0; i < response.length; i++) {
        final data = response[i];
        entries.add(LeaderboardEntry(
          playerId: data['player_id'] ?? '',
          playerName: data['player_name'] ?? 'لاعب مجهول',
          totalXP: (data['total_xp'] as num?)?.toInt() ?? 0,
          level: (data['level'] as num?)?.toInt() ?? 1,
          wins: (data['wins'] as num?)?.toInt() ?? 0,
          winRate: _calculateWinRate(data),
          badges: _parseBadges(data['badges']),
          rank: i + 1,
        ));
      }

      log('تم جلب ${entries.length} عنصر في فئة $category');
      return entries;
    } catch (e) {
      log('خطأ في جلب أفضل اللاعبين في فئة $category: $e');
      return [];
    }
  }

  /// حساب معدل الفوز مع معالجة الأخطاء
  double _calculateWinRate(Map<String, dynamic> data) {
    try {
      final totalGames = (data['total_games'] as num?)?.toInt() ?? 0;
      final wins = (data['wins'] as num?)?.toInt() ?? 0;

      return totalGames > 0 ? (wins / totalGames) * 100 : 0.0;
    } catch (e) {
      return 0.0;
    }
  }

  /// تحويل الشارات من JSON مع معالجة الأخطاء
  Map<BadgeType, int> _parseBadges(dynamic badgesData) {
    try {
      if (badgesData == null) return {};

      final badgesMap = badgesData as Map<String, dynamic>? ?? {};
      final result = <BadgeType, int>{};

      for (final entry in badgesMap.entries) {
        try {
          final badgeType = BadgeType.values.firstWhere(
                (e) => e.name == entry.key,
            orElse: () => BadgeType.masterSpy,
          );
          result[badgeType] = (entry.value as num?)?.toInt() ?? 0;
        } catch (e) {
          continue;
        }
      }

      return result;
    } catch (e) {
      return {};
    }
  }

  /// معالجة مكافآت الغرفة
  Future<Map<String, List<GameReward>>> processRoomGameResult({
    required GameRoom room,
    required String winner,
    String? revealedSpyId,
  }) async {
    final allRewards = <String, List<GameReward>>{};

    for (final player in room.players) {
      if (!player.isConnected) continue;

      try {
        final wasSpy = player.id == room.spyId;
        final won = (winner == 'spy' && wasSpy) || (winner == 'normal_players' && !wasSpy);
        final detectedSpy = winner == 'normal_players' && !wasSpy;
        final survived = true;

        final rewards = await processGameResult(
          playerId: player.id,
          playerName: player.name,
          won: won,
          wasSpy: wasSpy,
          detectedSpy: detectedSpy,
          survived: survived,
        );

        allRewards[player.id] = rewards;
      } catch (e) {
        log('خطأ في معالجة مكافآت اللاعب ${player.id}: $e');
        allRewards[player.id] = [];
      }
    }

    log('تم معالجة مكافآت ${allRewards.length} لاعبين');
    return allRewards;
  }

  /// تحديث اسم اللاعب في الإحصائيات
  Future<void> updatePlayerName(String playerId, String newName) async {
    try {
      await _client
          .from('player_stats')
          .update({'player_name': newName})
          .eq('player_id', playerId);

      log('تم تحديث اسم اللاعب $playerId إلى: $newName');
    } catch (e) {
      log('خطأ في تحديث اسم اللاعب: $e');
    }
  }
}