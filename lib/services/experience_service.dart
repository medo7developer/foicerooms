// ملف: lib/services/experience_service.dart - النسخة المحسنة
import 'dart:developer';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/experience_models.dart';
import '../models/game_room_model.dart';
import '../models/player_model.dart';
import '../providers/game_provider.dart';
import '../providers/game_state.dart';

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

  /// الحصول على إحصائيات اللاعب مع ضمان الاسم الصحيح
  Future<PlayerStats?> getPlayerStats(String playerId, {String? playerName}) async {
    try {
      final response = await _client
          .from('player_stats')
          .select()
          .eq('player_id', playerId)
          .maybeSingle();

      if (response == null) {
        // لا توجد إحصائيات، إرجاع null بدلاً من إنشاء جديدة
        return null;
      }

      final stats = PlayerStats.fromJson(response);

      // إذا تم تمرير اسم وهو مختلف عن المحفوظ، قم بتحديثه
      if (playerName != null &&
          playerName.isNotEmpty &&
          playerName != 'لاعب مجهول' &&
          stats.playerName != playerName) {

        await _client
            .from('player_stats')
            .update({
          'player_name': playerName,
          'last_updated': DateTime.now().toIso8601String(),
        })
            .eq('player_id', playerId);

        return stats.copyWith(playerName: playerName);
      }

      return stats;
    } catch (e) {
      log('خطأ في جلب إحصائيات اللاعب: $e');
      return null;
    }
  }

// تعديل دالة _createNewPlayerStats
  Future<PlayerStats> _createNewPlayerStats(String playerId, String playerName) async {
    try {
      // التأكد من وجود اللاعب في جدول players أولاً
      await _ensurePlayerExists(playerId, playerName);

      // فحص مرة أخرى قبل الإنشاء
      final existingStats = await _client
          .from('player_stats')
          .select('player_id')
          .eq('player_id', playerId)
          .maybeSingle();

      if (existingStats != null) {
        // الإحصائيات موجودة، فقط نحديث الاسم
        await _client
            .from('player_stats')
            .update({'player_name': playerName})
            .eq('player_id', playerId);

        return (await getPlayerStats(playerId))!;
      }

      final newStats = PlayerStats(
        playerId: playerId,
        playerName: playerName,
        lastUpdated: DateTime.now(),
      );

      final statsData = newStats.toJson();
      await _client.from('player_stats').insert(statsData);

      log('تم إنشاء إحصائيات جديدة للاعب: $playerId');
      return newStats;

    } catch (e) {
      log('خطأ في إنشاء إحصائيات اللاعب: $e');
      // إرجاع إحصائيات افتراضية بدلاً من إعادة المحاولة
      return PlayerStats(
        playerId: playerId,
        playerName: playerName,
        lastUpdated: DateTime.now(),
      );
    }
  }

  /// معالجة نتيجة اللعبة وتحديث الإحصائيات (محسن)
  Future<List<GameReward>> processGameResult({
    required String playerId,
    required String playerName,
    required bool won,
    required bool wasSpy,
    required bool detectedSpy,
    required bool survived,
  }) async {
    try {
      log('🎮 معالجة نتيجة اللعبة للاعب: $playerId');

      // التأكد من وجود اللاعب أولاً
      await _ensurePlayerExists(playerId, playerName);

      // جلب الإحصائيات الحالية بناءً على ID فقط
      final currentStats = await _client
          .from('player_stats')
          .select('*')
          .eq('player_id', playerId)
          .maybeSingle();

      PlayerStats stats;
      if (currentStats != null) {
        stats = PlayerStats.fromJson(currentStats);
        // تحديث الاسم إذا لزم الأمر
        if (stats.playerName != playerName && playerName.isNotEmpty) {
          stats = stats.copyWith(playerName: playerName);
        }
      } else {
        // إنشاء جديد إذا لم توجد إحصائيات
        stats = await _createNewPlayerStatsWithName(playerId, playerName);
      }

      final rewards = <GameReward>[];
      int xpGained = 0;

      // حساب المكافآت (نفس المنطق السابق)
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
      final updatedStats = stats.copyWith(
        totalGames: stats.totalGames + 1,
        wins: won ? stats.wins + 1 : stats.wins,
        losses: !won ? stats.losses + 1 : stats.losses,
        spyWins: (won && wasSpy) ? stats.spyWins + 1 : stats.spyWins,
        detectiveWins: (won && !wasSpy) ? stats.detectiveWins + 1 : stats.detectiveWins,
        timesWasSpy: wasSpy ? stats.timesWasSpy + 1 : stats.timesWasSpy,
        timesDetectedSpy: detectedSpy ? stats.timesDetectedSpy + 1 : stats.timesDetectedSpy,
        totalXP: stats.totalXP + xpGained,
        level: ((stats.totalXP + xpGained) / RewardConstants.xpPerLevel).floor() + 1,
        lastUpdated: DateTime.now(),
      );

      // التحقق من الشارات الجديدة
      final newBadges = await _checkForNewBadges(stats, updatedStats);
      rewards.addAll(newBadges);

      // حفظ مع إعادة المحاولة
      bool saved = false;
      int retryCount = 0;
      while (!saved && retryCount < 3) {
        try {
          await _client.from('player_stats').upsert(updatedStats.toJson());
          saved = true;
          log('✅ تم حفظ الإحصائيات المحدثة للاعب $playerId - المحاولة ${retryCount + 1}');
        } catch (e) {
          retryCount++;
          log('❌ فشلت المحاولة $retryCount في حفظ الإحصائيات: $e');
          if (retryCount < 3) {
            await Future.delayed(Duration(milliseconds: 500 * retryCount));
          }
        }
      }

      if (!saved) {
        log('❌ فشل نهائي في حفظ الإحصائيات للاعب $playerId');
      }

      log('🎉 تم تحديث إحصائيات اللاعب $playerId - XP: +$xpGained, المكافآت: ${rewards.length}');
      return rewards;
    } catch (e) {
      log('❌ خطأ في معالجة نتيجة اللعبة: $e');
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

  /// التأكد من وجود الإحصائيات مع الاسم الصحيح (محسن)
  Future<PlayerStats> ensurePlayerStatsWithName(String playerId, String playerName) async {
    try {
      // استخدام playerId فقط للبحث - لا نعتمد على الاسم
      final existingStats = await _client
          .from('player_stats')
          .select('*')
          .eq('player_id', playerId)
          .maybeSingle();

      if (existingStats != null) {
        final stats = PlayerStats.fromJson(existingStats);

        // تحديث الاسم فقط إذا كان مختلف ولا نعيد إنشاء البيانات
        if (stats.playerName != playerName &&
            playerName.isNotEmpty &&
            playerName != 'لاعب مجهول') {

          await _client
              .from('player_stats')
              .update({
            'player_name': playerName,
            'last_updated': DateTime.now().toIso8601String(),
          })
              .eq('player_id', playerId);

          log('تم تحديث اسم اللاعب في الإحصائيات: $playerId -> $playerName');
          return stats.copyWith(playerName: playerName);
        }

        return stats;
      } else {
        // إنشاء إحصائيات جديدة فقط إذا لم تكن موجودة
        return await _createNewPlayerStatsWithName(playerId, playerName);
      }
    } catch (e) {
      log('خطأ في التأكد من إحصائيات اللاعب: $e');
      // إرجاع الإحصائيات الموجودة حتى لو فشل التحديث
      try {
        final fallbackStats = await _client
            .from('player_stats')
            .select('*')
            .eq('player_id', playerId)
            .maybeSingle();

        if (fallbackStats != null) {
          return PlayerStats.fromJson(fallbackStats);
        }
      } catch (e2) {
        log('فشل في جلب الإحصائيات الاحتياطية: $e2');
      }

      // إنشاء افتراضي في حالة الفشل الكامل
      return PlayerStats(
        playerId: playerId,
        playerName: playerName,
        lastUpdated: DateTime.now(),
      );
    }
  }

  /// إنشاء إحصائيات جديدة مع الاسم
  Future<PlayerStats> _createNewPlayerStatsWithName(String playerId, String playerName) async {
    try {
      // التأكد من وجود اللاعب في جدول players أولاً
      await _ensurePlayerExists(playerId, playerName);

      // فحص مرة أخيرة قبل الإنشاء لتجنب التضارب
      final existingCheck = await _client
          .from('player_stats')
          .select('player_id')
          .eq('player_id', playerId)
          .maybeSingle();

      if (existingCheck != null) {
        // الإحصائيات موجودة، تحديث الاسم فقط
        await _client
            .from('player_stats')
            .update({
          'player_name': playerName,
          'last_updated': DateTime.now().toIso8601String(),
        })
            .eq('player_id', playerId);

        return (await getPlayerStats(playerId))!;
      }

      // إنشاء إحصائيات جديدة
      final newStats = PlayerStats(
        playerId: playerId,
        playerName: playerName, // استخدام الاسم المرسل
        lastUpdated: DateTime.now(),
      );

      await _client.from('player_stats').insert(newStats.toJson());
      log('تم إنشاء إحصائيات جديدة للاعب: $playerId باسم: $playerName');

      return newStats;
    } catch (e) {
      log('خطأ في إنشاء إحصائيات اللاعب: $e');

      // إرجاع إحصائيات افتراضية بدلاً من الفشل
      return PlayerStats(
        playerId: playerId,
        playerName: playerName,
        lastUpdated: DateTime.now(),
      );
    }
  }

  /// تهيئة إحصائيات اللاعب عند بدء التطبيق (محسنة)
  Future<void> initializePlayerStatsOnStart(String playerId, String playerName) async {
    try {
      // استخدام الدالة الجديدة المحسنة
      await ensurePlayerStatsWithName(playerId, playerName);
      log('تم تهيئة إحصائيات اللاعب عند بدء التطبيق: $playerId');
    } catch (e) {
      log('خطأ في تهيئة إحصائيات اللاعب عند البدء: $e');
    }
  }

  /// التحقق من تكامل بيانات اللاعب وإصلاحها
  Future<bool> validateAndFixPlayerData(String playerId, String playerName) async {
    try {
      // فحص جدول players
      final playerData = await _client
          .from('players')
          .select('id, name')
          .eq('id', playerId)
          .maybeSingle();

      // فحص جدول player_stats
      final statsData = await _client
          .from('player_stats')
          .select('player_id, player_name')
          .eq('player_id', playerId)
          .maybeSingle();

      bool needsFix = false;

      // إصلاح جدول players إذا لزم الأمر
      if (playerData == null) {
        await _client.from('players').upsert({
          'id': playerId,
          'name': playerName,
          'is_connected': false,
          'is_voted': false,
          'votes': 0,
          'role': 'normal',
          'room_id': null,
        });
        needsFix = true;
        log('تم إصلاح بيانات اللاعب في جدول players');
      } else if (playerData['name'] != playerName) {
        await _client.from('players')
            .update({'name': playerName})
            .eq('id', playerId);
        needsFix = true;
      }

      // إصلاح جدول player_stats إذا لزم الأمر
      if (statsData == null) {
        await _createNewPlayerStatsWithName(playerId, playerName);
        needsFix = true;
        log('تم إصلاح بيانات اللاعب في جدول player_stats');
      } else if (statsData['player_name'] != playerName) {
        await _client.from('player_stats')
            .update({
          'player_name': playerName,
          'last_updated': DateTime.now().toIso8601String(),
        })
            .eq('player_id', playerId);
        needsFix = true;
      }

      if (needsFix) {
        log('تم إصلاح بيانات اللاعب: $playerId');
      }

      return true;
    } catch (e) {
      log('خطأ في التحقق من تكامل بيانات اللاعب: $e');
      return false;
    }
  }

  /// تحديث جميع إحصائيات الاعبين بأسمائهم الحقيقية من جدول players
  Future<void> syncPlayerNamesFromPlayersTable() async {
    try {
      // جلب جميع اللاعبين من جدول players مع أسمائهم الحديثة
      final playersData = await _client
          .from('players')
          .select('id, name')
          .neq('name', '')
          .not('name', 'is', null);

      if (playersData.isNotEmpty) {
        // تحديث الأسماء في جدول player_stats
        for (final player in playersData) {
          try {
            await _client
                .from('player_stats')
                .update({'player_name': player['name']})
                .eq('player_id', player['id']);
          } catch (e) {
            log('خطأ في تحديث اسم اللاعب ${player['id']}: $e');
            continue;
          }
        }

        log('تم مزامنة أسماء ${playersData.length} لاعب');
      }
    } catch (e) {
      log('خطأ في مزامنة أسماء اللاعبين: $e');
    }
  }

  /// الحصول على قائمة المتصدرين (محسن لحماية البيانات)
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
          final playerId = data['player_id'] ?? '';

          if (playerId.isEmpty) continue;

          String playerName = data['player_name'] ?? 'لاعب مجهول';

          entries.add(LeaderboardEntry(
            playerId: playerId,
            playerName: playerName,
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

  // إضافة هذه الدوال الجديدة في ExperienceService

  /// التأكد من وجود اللاعب باستخدام بيانات المستخدم المصادق عليه
  Future<void> ensurePlayerExistsWithUserData({
    required String userId,
    required String email,
    required String displayName,
    String? photoUrl,
  }) async {
    try {
      // التحقق من وجود اللاعب في جدول players
      final existingPlayer = await _client
          .from('players')
          .select('id')
          .eq('id', userId)
          .maybeSingle();

      final playerData = {
        'id': userId,
        'name': displayName,
        'email': email, // إضافة الإيميل
        'photo_url': photoUrl, // إضافة الصورة
        'is_connected': false,
        'is_voted': false,
        'votes': 0,
        'role': 'normal',
        'room_id': null,
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (existingPlayer == null) {
        // إنشاء سجل جديد
        playerData['created_at'] = DateTime.now().toIso8601String();
        await _client.from('players').insert(playerData);
        log('تم إنشاء سجل اللاعب المصادق عليه: $displayName');
      } else {
        // تحديث البيانات الموجودة
        await _client.from('players')
            .update(playerData)
            .eq('id', userId);
        log('تم تحديث بيانات اللاعب المصادق عليه: $displayName');
      }
    } catch (e) {
      log('خطأ في التأكد من وجود اللاعب المصادق عليه: $e');
    }
  }

  /// إنشاء إحصائيات اللاعب مع البيانات الكاملة
  Future<PlayerStats> createPlayerStatsWithUserData({
    required String userId,
    required String email,
    required String displayName,
    String? photoUrl,
  }) async {
    try {
      // التأكد من وجود اللاعب أولاً
      await ensurePlayerExistsWithUserData(
        userId: userId,
        email: email,
        displayName: displayName,
        photoUrl: photoUrl,
      );

      // فحص الإحصائيات الموجودة
      final existingStats = await _client
          .from('player_stats')
          .select('*')
          .eq('player_id', userId)
          .maybeSingle();

      if (existingStats != null) {
        // تحديث البيانات الشخصية فقط
        await _client.from('player_stats').update({
          'player_name': displayName,
          'player_email': email,
          'player_photo_url': photoUrl,
          'last_updated': DateTime.now().toIso8601String(),
        }).eq('player_id', userId);

        return PlayerStats.fromJsonWithUserData(existingStats, email, photoUrl);
      }

      // إنشاء إحصائيات جديدة
      final newStats = PlayerStats(
        playerId: userId,
        playerName: displayName,
        lastUpdated: DateTime.now(),
      );

      final statsData = newStats.toJsonWithUserData(email, photoUrl);
      await _client.from('player_stats').insert(statsData);

      log('تم إنشاء إحصائيات جديدة للمستخدم المصادق عليه: $displayName');
      return newStats;
    } catch (e) {
      log('خطأ في إنشاء إحصائيات المستخدم: $e');
      return PlayerStats(
        playerId: userId,
        playerName: displayName,
        lastUpdated: DateTime.now(),
      );
    }
  }

  /// معالجة تسجيل الدخول الأولي للمستخدم
  Future<void> handleUserFirstLogin({
    required String userId,
    required String email,
    required String displayName,
    String? photoUrl,
  }) async {
    try {
      log('معالجة تسجيل دخول المستخدم: $displayName');

      await createPlayerStatsWithUserData(
        userId: userId,
        email: email,
        displayName: displayName,
        photoUrl: photoUrl,
      );

      log('تم إعداد حساب المستخدم بنجاح');
    } catch (e) {
      log('خطأ في معالجة تسجيل دخول المستخدم: $e');
    }
  }

  /// الحصول على أفضل اللاعبين في فئة معينة مع مزامنة الأسماء
  Future<List<LeaderboardEntry>> getTopPlayersByCategory({
    required String category,
    int limit = 10,
  }) async {
    try {
      // مزامنة الأسماء أولاً
      await syncPlayerNamesFromPlayersTable();

      final List<Map<String, dynamic>> response = await _client
          .from('player_stats')
          .select('*')
          .gt(category, 0)
          .order(category, ascending: false)
          .limit(limit);

      if (response.isEmpty) {
        log('لا توجد بيانات في فئة $category');
        return [];
      }

      final entries = <LeaderboardEntry>[];
      for (int i = 0; i < response.length; i++) {
        final data = response[i];

        // محاولة جلب الاسم الحديث
        String playerName = data['player_name'] ?? 'لاعب مجهول';

        if (playerName == 'لاعب مجهول' || playerName.isEmpty) {
          try {
            final playerData = await _client
                .from('players')
                .select('name')
                .eq('id', data['player_id'])
                .limit(1)
                .maybeSingle();

            if (playerData != null && playerData['name'] != null && playerData['name'].isNotEmpty) {
              playerName = playerData['name'];

              // تحديث الاسم في جدول الإحصائيات
              await _client
                  .from('player_stats')
                  .update({'player_name': playerName})
                  .eq('player_id', data['player_id']);
            }
          } catch (e) {
            log('خطأ في جلب اسم اللاعب من جدول players: $e');
          }
        }

        entries.add(LeaderboardEntry(
          playerId: data['player_id'] ?? '',
          playerName: playerName,
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

  /// التأكد من معالجة مكافآت اللعبة المنتهية
  Future<void> ensureGameRewardsProcessed(String playerId, GameRoom room) async {
    try {
      // التحقق من أن اللعبة انتهت فعلاً
      if (room.state != GameState.finished) return;

      // البحث عن اللاعب في الغرفة
      final player = room.players.firstWhere(
            (p) => p.id == playerId,
        orElse: () => Player(
          id: playerId,
          name: 'لاعب محذوف',
          role: PlayerRole.normal,
        ),
      );

      // تحديد النتيجة
      final wasSpy = player.role == PlayerRole.spy;
      final spyWon = room.winner == 'spy';
      final won = wasSpy ? spyWon : !spyWon;
      final detectedSpy = !wasSpy && !spyWon;

      // معالجة النتيجة
      final rewards = await processGameResult(
        playerId: playerId,
        playerName: player.name,
        won: won,
        wasSpy: wasSpy,
        detectedSpy: detectedSpy,
        survived: true,
      );

      log('تم معالجة مكافآت اللاعب $playerId: ${rewards.length} مكافآت');
    } catch (e) {
      log('خطأ في التأكد من معالجة المكافآت: $e');
    }
  }

}