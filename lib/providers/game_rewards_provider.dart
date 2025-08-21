import 'dart:developer';
import 'package:flutter/material.dart';
import '../models/experience_models.dart';
import '../models/game_room_model.dart';
import '../models/player_model.dart';
import '../services/experience_service.dart';
import 'game_state.dart'; // استخدام الـ Enum من الملف المنفصل

class GameRewardsProvider extends ChangeNotifier {
  PlayerStats? _currentPlayerStats;
  List<GameReward>? _lastGameRewards;
  ExperienceService? _experienceService;

  // متغيرات التتبع
  bool _rewardsProcessed = false;

  // Getters
  PlayerStats? get currentPlayerStats => _currentPlayerStats;
  List<GameReward>? get lastGameRewards => _lastGameRewards;

  // Setters
  set currentPlayerStats(PlayerStats? stats) {
    _currentPlayerStats = stats;
    notifyListeners();
  }

  set lastGameRewards(List<GameReward>? rewards) {
    _lastGameRewards = rewards;
    notifyListeners();
  }

  // إعداد الخدمات
  void setExperienceService(ExperienceService service) {
    _experienceService = service;
  }

  // وظائف المكافآت
  Future<void> loadPlayerStats(
      String playerId,
      String playerName,
      ExperienceService? experienceService,
      ) async {
    if (experienceService == null) return;

    try {
      _currentPlayerStats = await experienceService.getPlayerStats(playerId, playerName: playerName);
      notifyListeners();
    } catch (e) {
      debugPrint('خطأ في تحميل إحصائيات اللاعب: $e');
    }
  }

  Future<void> processGameEndWithRewards(
      GameRoom? room,
      ExperienceService? experienceService,
      ) async {
    if (room == null || experienceService == null) {
      log('⚠️ لا يمكن معالجة المكافآت - بيانات مفقودة');
      return;
    }

    if (room.state != GameState.finished) { // استخدام الـ Enum من الملف المنفصل
      log('⚠️ اللعبة لم تنته بعد، لا يمكن معالجة المكافآت');
      return;
    }

    try {
      log('🎁 بدء معالجة مكافآت اللعبة...');

      // تحديد الفائز من بيانات الغرفة
      String winner = room.winner ?? 'normal_players';
      log('📊 الفائز: $winner، الجاسوس المكشوف: ${room.revealedSpyId}');

      // معالجة مكافآت جميع اللاعبين
      final allRewards = await experienceService.processRoomGameResult(
        room: room,
        winner: winner,
        revealedSpyId: room.revealedSpyId,
      );

      log('✅ تم معالجة مكافآت ${allRewards.length} لاعبين');

      // احفظ مكافآت اللاعب الحالي
      if (allRewards.isNotEmpty) {
        // في هذا السياق، لا نملك معرف اللاعب الحالي مباشرة
        // سنقوم بحفظ أول مكافأة كافتراض
        final firstPlayerId = allRewards.keys.first;
        _lastGameRewards = allRewards[firstPlayerId];
        log('🎁 تم حفظ مكافآت اللاعب: ${_lastGameRewards?.length} مكافأة');
      }

      notifyListeners();
    } catch (e) {
      log('❌ خطأ في معالجة مكافآت اللعبة: $e');
    }
  }

  void checkGameEndRewards(GameRoom? room, Player? currentPlayer) {
    if (room?.state == GameState.finished && // استخدام الـ Enum من الملف المنفصل
        room?.winner != null &&
        _lastGameRewards == null &&
        !_rewardsProcessed) {
      log('🏁 تم انتهاء اللعبة - الفائز: ${room?.winner}');
      _rewardsProcessed = true;

      // تأخير قصير للتأكد من استقرار البيانات
      Future.delayed(const Duration(seconds: 2), () {
        processGameEndWithRewards(room, _experienceService);
      });
    }

    // إعادة تعيين معالجة المكافآت للألعاب الجديدة
    if (room?.state == GameState.waiting) { // استخدام الـ Enum من الملف المنفصل
      _rewardsProcessed = false;
    }
  }

  void checkAndProcessGameRewards(GameRoom? room) {
    if (room?.state == GameState.finished && // استخدام الـ Enum من الملف المنفصل
        room?.winner != null &&
        _lastGameRewards == null) {
      log('🎁 معالجة مكافآت نهاية اللعبة');
      processGameEndWithRewards(room, _experienceService);
    }
  }

  void clearLastGameRewards() {
    _lastGameRewards = null;
    notifyListeners();
  }

  // إعادة تعيين المكافآت
  void resetRewards() {
    _currentPlayerStats = null;
    _lastGameRewards = null;
    _rewardsProcessed = false;
    notifyListeners();
  }

  // تنظيف الموارد
  @override
  void dispose() {
    _currentPlayerStats = null;
    _lastGameRewards = null;
    super.dispose();
  }
}