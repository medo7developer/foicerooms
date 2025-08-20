import 'dart:developer';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'game_logic_service.dart';

/// خدمة إدارة التصويت - التصويت العادي وتصويت الإكمال
class VotingService {
  final SupabaseClient _client = Supabase.instance.client;
  final GameLogicService _gameLogicService = GameLogicService();

  /// تحديث التصويت على لاعب
  Future<void> updateVote(String playerId, String targetId) async {
    try {
      // الحصول على معلومات الغرفة
      final playerData = await _client
          .from('players')
          .select('room_id')
          .eq('id', playerId)
          .maybeSingle();

      if (playerData == null) return;
      final roomId = playerData['room_id'];

      // تحديث حالة التصويت للاعب
      await _client.from('players').update({
        'is_voted': true,
      }).eq('id', playerId);

      // زيادة عدد الأصوات للهدف
      final currentVotes = await _client
          .from('players')
          .select('votes')
          .eq('id', targetId)
          .maybeSingle();

      if (currentVotes != null) {
        await _client.from('players').update({
          'votes': (currentVotes['votes'] ?? 0) + 1,
        }).eq('id', targetId);
      }

      log('تم تسجيل صوت من $playerId لـ $targetId');

      // التحقق من انتهاء التصويت مع تأخير قصير للتأكد من تحديث البيانات
      Future.delayed(const Duration(milliseconds: 500), () {
        checkVotingComplete(roomId);
      });
    } catch (e) {
      log('خطأ في تسجيل التصويت: $e');
    }
  }

  /// التحقق من انتهاء التصويت
  Future<void> checkVotingComplete(String roomId) async {
    try {
      final roomData = await _client
          .from('rooms')
          .select('*, players!inner(*)')
          .eq('id', roomId)
          .eq('state', 'voting')
          .maybeSingle();

      if (roomData == null) return;

      final players = roomData['players'] as List;
      final connectedPlayers = players.where((p) => p['is_connected'] == true).toList();
      final votedPlayers = connectedPlayers.where((p) => p['is_voted'] == true).toList();

      // إذا صوت جميع اللاعبين المتصلين
      if (votedPlayers.length >= connectedPlayers.length && connectedPlayers.isNotEmpty) {
        await _endRound(roomId, connectedPlayers);
      }
    } catch (e) {
      log('خطأ في التحقق من انتهاء التصويت: $e');
    }
  }

  /// انتهاء الجولة المحدثة
  Future<void> _endRound(String roomId, List<dynamic> players) async {
    try {
      log('🔄 بدء معالجة انتهاء الجولة في الغرفة: $roomId');

      // العثور على اللاعب الأكثر تصويتاً
      players.sort((a, b) => (b['votes'] ?? 0).compareTo(a['votes'] ?? 0));
      final mostVoted = players.first;
      final mostVotedId = mostVoted['id'];
      final mostVotedRole = mostVoted['role'];

      log('📊 اللاعب الأكثر تصويتاً: ${mostVoted['name']} (${mostVoted['votes']} أصوات) - الدور: $mostVotedRole');

      // إزالة اللاعب الأكثر تصويتاً
      await _client.from('players').delete().eq('id', mostVotedId);
      log('❌ تم حذف اللاعب: $mostVotedId');

      // الحصول على اللاعبين المتبقين بعد الحذف
      final remainingPlayersResponse = await _client
          .from('players')
          .select('*')
          .eq('room_id', roomId);

      final remainingPlayers = remainingPlayersResponse as List<dynamic>;
      final remainingSpies = remainingPlayers.where((p) => p['role'] == 'spy').toList();
      final remainingNormal = remainingPlayers.where((p) => p['role'] == 'normal').toList();

      log('👥 اللاعبين المتبقين: ${remainingPlayers.length} - جواسيس: ${remainingSpies.length} - عاديين: ${remainingNormal.length}');

      // الحصول على معلومات الغرفة الحالية
      final roomData = await _client
          .from('rooms')
          .select('current_round, total_rounds, state')
          .eq('id', roomId)
          .maybeSingle();

      if (roomData == null) {
        log('❌ الغرفة غير موجودة');
        return;
      }

      final currentRound = roomData['current_round'] ?? 1;
      final totalRounds = roomData['total_rounds'] ?? 3;

      log('🎮 الجولة الحالية: $currentRound من $totalRounds');

      // تحديد نتيجة اللعبة
      String? winner;
      String? nextState;

      if (remainingSpies.isEmpty) {
        // فوز اللاعبين العاديين - تم إقصاء الجاسوس
        winner = 'normal_players';
        nextState = 'finished';
        log('🎉 فوز اللاعبين العاديين - تم إقصاء الجاسوس');

      } else if (remainingNormal.length <= remainingSpies.length) {
        // فوز الجاسوس - عدد اللاعبين العاديين أصبح قليل
        winner = 'spy';
        nextState = 'finished';
        log('🎉 فوز الجاسوس - عدد اللاعبين العاديين قليل');

      } else if (currentRound >= totalRounds) {
        // انتهاء الجولات المحددة - التصويت على الإكمال
        nextState = 'continue_voting';
        log('🗳️ انتهاء الجولات المحددة - بدء التصويت على الإكمال');

      } else {
        // إكمال الجولة التالية
        nextState = 'playing';
        log('▶️ الانتقال للجولة التالية: ${currentRound + 1}');
      }

      // تطبيق التحديث المناسب
      if (nextState == 'finished' && winner != null) {
        await _gameLogicService.endGame(roomId, winner);

      } else if (nextState == 'continue_voting') {
        await _gameLogicService.startContinueVoting(roomId, currentRound + 1, remainingPlayers);

      } else if (nextState == 'playing') {
        // بدء الجولة الجديدة
        await _gameLogicService.startNewRound(roomId, currentRound + 1, remainingPlayers);
      }

      // تأكيد التحديث في قاعدة البيانات
      await Future.delayed(const Duration(milliseconds: 500));

      final updatedRoom = await _client
          .from('rooms')
          .select('state, current_round')
          .eq('id', roomId)
          .maybeSingle();

      log('✅ تم تحديث الغرفة - الحالة الجديدة: ${updatedRoom?['state']} - الجولة: ${updatedRoom?['current_round']}');

    } catch (e) {
      log('❌ خطأ في انتهاء الجولة: $e');
      rethrow;
    }
  }

  /// التصويت على إكمال الجولات
  Future<void> voteToContinue(String playerId, bool continuePlaying) async {
    try {
      // الحصول على معلومات الغرفة
      final playerData = await _client
          .from('players')
          .select('room_id')
          .eq('id', playerId)
          .maybeSingle();

      if (playerData == null) return;
      final roomId = playerData['room_id'];

      // تحديث صوت اللاعب
      await _client.from('players').update({
        'is_voted': true,
        'votes': continuePlaying ? 1 : 0, // 1 = إكمال، 0 = إنهاء
      }).eq('id', playerId);

      log('صوت اللاعب $playerId على ${continuePlaying ? "الإكمال" : "الإنهاء"}');

      // التحقق من انتهاء التصويت
      Future.delayed(const Duration(milliseconds: 500), () {
        _checkContinueVotingComplete(roomId);
      });
    } catch (e) {
      log('خطأ في التصويت على الإكمال: $e');
    }
  }

  /// التحقق من انتهاء تصويت الإكمال
  Future<void> _checkContinueVotingComplete(String roomId) async {
    try {
      log('🔍 التحقق من انتهاء تصويت الإكمال في الغرفة: $roomId');

      // استخدام دالة GameLogicService المحدثة
      await _gameLogicService.processContinueVotingResult(roomId);

    } catch (e) {
      log('❌ خطأ في التحقق من تصويت الإكمال: $e');
    }
  }
}