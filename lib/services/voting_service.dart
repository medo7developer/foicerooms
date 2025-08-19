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
      // العثور على اللاعب الأكثر تصويتاً
      players.sort((a, b) => (b['votes'] ?? 0).compareTo(a['votes'] ?? 0));
      final mostVoted = players.first;
      final mostVotedId = mostVoted['id'];

      // إزالة اللاعب الأكثر تصويتاً
      await _client.from('players').delete().eq('id', mostVotedId);

      // الحصول على اللاعبين المتبقين
      final remainingPlayers = await _client
          .from('players')
          .select('*')
          .eq('room_id', roomId);

      final remainingSpies = remainingPlayers.where((p) => p['role'] == 'spy').toList();

      // تحديد نتيجة اللعبة
      final roomUpdate = await _client
          .from('rooms')
          .select('current_round, total_rounds')
          .eq('id', roomId)
          .maybeSingle();

      if (roomUpdate == null) return;

      final currentRound = roomUpdate['current_round'] ?? 1;
      final totalRounds = roomUpdate['total_rounds'] ?? 3;

      // التحقق من شروط انتهاء اللعبة
      if (remainingSpies.isEmpty) {
        // فوز اللاعبين العاديين - تم إقصاء الجاسوس
        await _gameLogicService.endGame(roomId, 'normal_players');
      } else if (remainingPlayers.length < 3) {
        // انتهاء اللعبة - عدد اللاعبين قليل جداً
        await _gameLogicService.endGame(roomId, remainingSpies.isNotEmpty ? 'spy' : 'normal_players');
      } else if (currentRound >= totalRounds) {
        // انتهاء الجولات - فوز الجاسوس
        await _gameLogicService.endGame(roomId, 'spy');
      } else {
        // التصويت على إكمال الجولات
        await _gameLogicService.startContinueVoting(roomId, currentRound + 1, remainingPlayers);
      }

      log('انتهت الجولة - اللاعب المحذوف: $mostVotedId، اللاعبين المتبقين: ${remainingPlayers.length}');
    } catch (e) {
      log('خطأ في انتهاء الجولة: $e');
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
      final roomData = await _client
          .from('rooms')
          .select('*, players!inner(*)')
          .eq('id', roomId)
          .eq('state', 'continue_voting')
          .maybeSingle();

      if (roomData == null) return;

      final players = roomData['players'] as List;
      final connectedPlayers = players.where((p) => p['is_connected'] == true).toList();
      final votedPlayers = connectedPlayers.where((p) => p['is_voted'] == true).toList();

      // إذا صوت جميع اللاعبين المتصلين
      if (votedPlayers.length >= connectedPlayers.length && connectedPlayers.isNotEmpty) {
        // حساب الأصوات
        final continueVotes = votedPlayers.where((p) => p['votes'] == 1).length;
        final endVotes = votedPlayers.where((p) => p['votes'] == 0).length;

        final nextRound = roomData['next_round'] ?? 2;

        if (continueVotes > endVotes) {
          // الأغلبية تريد الإكمال
          await _gameLogicService.startNewRound(roomId, nextRound, connectedPlayers);
        } else {
          // الأغلبية تريد الإنهاء أو تعادل
          final remainingSpies = connectedPlayers.where((p) => p['role'] == 'spy').toList();
          await _gameLogicService.endGame(roomId, remainingSpies.isNotEmpty ? 'spy' : 'normal_players');
        }

        log('انتهى التصويت على الإكمال - إكمال: $continueVotes، إنهاء: $endVotes');
      }
    } catch (e) {
      log('خطأ في التحقق من تصويت الإكمال: $e');
    }
  }
}