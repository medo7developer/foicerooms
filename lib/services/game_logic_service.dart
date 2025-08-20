import 'dart:developer';
import 'package:supabase_flutter/supabase_flutter.dart';

/// خدمة منطق اللعبة - بدء اللعبة، إدارة الجولات، انتهاء اللعبة
class GameLogicService {
  final SupabaseClient _client = Supabase.instance.client;

  // قائمة الكلمات المستخدمة في اللعبة
  static const List<String> gameWords = [
    'مدرسة', 'مستشفى', 'مطعم', 'مكتبة', 'حديقة',
    'بنك', 'صيدلية', 'سوق', 'سينما', 'متحف',
    'شاطئ', 'جبل', 'غابة', 'صحراء', 'نهر',
    'طائرة', 'سيارة', 'قطار', 'سفينة', 'دراجة',
    'طبيب', 'مدرس', 'مهندس', 'طباخ', 'فنان',
  ];

  /// التحقق من إمكانية بدء اللعبة
  Future<bool> canStartGame(String roomId, String creatorId) async {
    try {
      final room = await _client
          .from('rooms')
          .select('creator_id, state, players!inner(*)')
          .eq('id', roomId)
          .maybeSingle();

      if (room == null || room['creator_id'] != creatorId) {
        return false;
      }

      if (room['state'] != 'waiting') {
        return false;
      }

      final players = room['players'] as List;
      final connectedCount = players.where((p) => p['is_connected'] == true).length;

      return connectedCount >= 3;
    } catch (e) {
      log('خطأ في التحقق من إمكانية بدء اللعبة: $e');
      return false;
    }
  }

  /// بدء اللعبة بواسطة منشئ الغرفة
  Future<bool> startGameByCreator(String roomId, String creatorId) async {
    try {
      // التحقق من أن المستخدم هو مالك الغرفة
      final room = await _client
          .from('rooms')
          .select('creator_id, state, players!inner(*)')
          .eq('id', roomId)
          .maybeSingle();

      if (room == null) {
        log('الغرفة غير موجودة: $roomId');
        return false;
      }

      if (room['creator_id'] != creatorId) {
        log('المستخدم $creatorId غير مخول لبدء اللعبة');
        return false;
      }

      if (room['state'] != 'waiting') {
        log('اللعبة ليست في حالة الانتظار: ${room['state']}');
        return false;
      }

      final players = room['players'] as List;
      final connectedPlayers = players.where((p) => p['is_connected'] == true).toList();

      if (connectedPlayers.length < 3) {
        log('عدد اللاعبين المتصلين غير كافٍ: ${connectedPlayers.length}');
        return false;
      }

      // اختيار الجاسوس والكلمة
      final wordsToUse = List<String>.from(gameWords);

      // خلط اللاعبين واختيار الجاسوس
      connectedPlayers.shuffle();
      final spyIndex = DateTime.now().millisecond % connectedPlayers.length;
      final spyId = connectedPlayers[spyIndex]['id'];

      wordsToUse.shuffle();
      final selectedWord = wordsToUse.first;

      // تحديث حالة الغرفة
      await _client.from('rooms').update({
        'state': 'playing',
        'current_round': 1,
        'spy_id': spyId,
        'current_word': selectedWord,
        'round_start_time': DateTime.now().toIso8601String(),
        'ready_to_start': false,
      }).eq('id', roomId);

      // تحديث أدوار جميع اللاعبين المتصلين فقط
      for (final player in connectedPlayers) {
        await _client.from('players').update({
          'role': player['id'] == spyId ? 'spy' : 'normal',
          'votes': 0,
          'is_voted': false,
        }).eq('id', player['id']);
      }

      log('تم بدء اللعبة في الغرفة $roomId مع ${connectedPlayers.length} لاعبين');
      log('الجاسوس: $spyId، الكلمة: $selectedWord');

      return true;
    } catch (e) {
      log('خطأ في بدء اللعبة: $e');
      return false;
    }
  }

  /// بدء اللعبة (دالة أساسية)
  Future<void> startGame(String roomId, String spyId, String word) async {
    try {
      await _client.from('rooms').update({
        'state': 'playing',
        'current_round': 1,
        'spy_id': spyId,
        'current_word': word,
        'round_start_time': DateTime.now().toIso8601String(),
      }).eq('id', roomId);

      log('تم بدء اللعبة في الغرفة $roomId');
    } catch (e) {
      log('خطأ في بدء اللعبة: $e');
    }
  }

  /// انتهاء الجولة والانتقال للتصويت
  Future<bool> endRoundAndStartVoting(String roomId) async {
    try {
      // التحقق من حالة الغرفة الحالية
      final currentRoom = await _client
          .from('rooms')
          .select('state, current_round')
          .eq('id', roomId)
          .maybeSingle();

      if (currentRoom == null || currentRoom['state'] != 'playing') {
        log('الغرفة غير صالحة للانتقال للتصويت: ${currentRoom?['state']}');
        return false;
      }

      // تحديث الحالة إلى التصويت فقط إذا كانت في حالة اللعب
      await _client.from('rooms').update({
        'state': 'voting',
        'round_start_time': null, // إزالة وقت بدء الجولة
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', roomId).eq('state', 'playing'); // شرط إضافي للتأكد

      // إعادة تعيين أصوات جميع اللاعبين
      await _client.from('players').update({
        'votes': 0,
        'is_voted': false,
      }).eq('room_id', roomId);

      log('تم الانتقال للتصويت في الغرفة $roomId');
      return true;
    } catch (e) {
      log('خطأ في انتهاء الجولة: $e');
      return false;
    }
  }

  /// بدء جولة جديدة
  Future<void> startNewRound(String roomId, int roundNumber, List<dynamic> players) async {
    try {
      // اختيار جاسوس جديد
      final connectedPlayers = players.where((p) => p['is_connected'] == true).toList();
      connectedPlayers.shuffle();
      final newSpyIndex = DateTime.now().millisecond % connectedPlayers.length;
      final newSpyId = connectedPlayers[newSpyIndex]['id'];

      // اختيار كلمة جديدة
      final wordsToUse = List<String>.from(gameWords);
      wordsToUse.shuffle();
      final newWord = wordsToUse.first;

      // تحديث الغرفة
      await _client.from('rooms').update({
        'state': 'playing',
        'current_round': roundNumber,
        'spy_id': newSpyId,
        'current_word': newWord,
        'round_start_time': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', roomId);

      // إعادة تعيين جميع اللاعبين
      for (final player in connectedPlayers) {
        await _client.from('players').update({
          'role': player['id'] == newSpyId ? 'spy' : 'normal',
          'votes': 0,
          'is_voted': false,
        }).eq('id', player['id']);
      }

      log('بدأت جولة جديدة: $roundNumber في الغرفة: $roomId');
    } catch (e) {
      log('خطأ في بدء جولة جديدة: $e');
    }
  }

  /// إنهاء اللعبة
  Future<void> endGame(String roomId, String winner) async {
    try {
      await _client.from('rooms').update({
        'state': 'finished',
        'winner': winner,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', roomId);
      log('انتهت اللعبة في الغرفة $roomId - الفائز: $winner');
    } catch (e) {
      log('خطأ في إنهاء اللعبة: $e');
    }
  }

  /// بدء التصويت على إكمال الجولات
  Future<void> startContinueVoting(String roomId, int nextRound, List<dynamic> remainingPlayers) async {
    try {
      log('🗳️ بدء التصويت على إكمال الجولات في الغرفة: $roomId');

      // تحديث حالة الغرفة للتصويت على الإكمال
      await _client.from('rooms').update({
        'state': 'continue_voting',
        'next_round': nextRound,
        'round_start_time': null, // إزالة وقت الجولة
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', roomId);

      // إعادة تعيين حالة التصويت لجميع اللاعبين المتبقين
      for (final player in remainingPlayers) {
        await _client.from('players').update({
          'is_voted': false,
          'votes': 0, // سنستخدم votes لحفظ خيار الإكمال (1 = إكمال، 0 = إنهاء)
        }).eq('id', player['id']);
      }

      log('✅ تم بدء التصويت على إكمال الجولات - اللاعبين: ${remainingPlayers.length}');

      // التحقق من أن التحديث تم بنجاح
      final verification = await _client
          .from('rooms')
          .select('state')
          .eq('id', roomId)
          .maybeSingle();

      log('✓ تأكيد حالة الغرفة: ${verification?['state']}');

    } catch (e) {
      log('❌ خطأ في بدء تصويت الإكمال: $e');
      rethrow;
    }
  }

// وأضف هذه الدالة الجديدة أيضاً:

  /// التحقق من انتهاء تصويت الإكمال ومعالجة النتيجة
  Future<void> processContinueVotingResult(String roomId) async {
    try {
      log('🔍 التحقق من نتائج التصويت على الإكمال في الغرفة: $roomId');

      final roomData = await _client
          .from('rooms')
          .select('next_round, players!inner(*)')
          .eq('id', roomId)
          .eq('state', 'continue_voting')
          .maybeSingle();

      if (roomData == null) {
        log('❌ الغرفة غير موجودة أو ليست في حالة تصويت الإكمال');
        return;
      }

      final players = roomData['players'] as List;
      final connectedPlayers = players.where((p) => p['is_connected'] == true).toList();
      final votedPlayers = connectedPlayers.where((p) => p['is_voted'] == true).toList();

      // التحقق من أن جميع اللاعبين صوتوا
      if (votedPlayers.length < connectedPlayers.length) {
        log('⏳ لم يصوت جميع اللاعبين بعد: ${votedPlayers.length}/${connectedPlayers.length}');
        return;
      }

      // حساب الأصوات
      final continueVotes = votedPlayers.where((p) => p['votes'] == 1).length;
      final endVotes = votedPlayers.where((p) => p['votes'] == 0).length;
      final nextRound = roomData['next_round'] ?? 2;

      log('📊 نتائج التصويت - إكمال: $continueVotes، إنهاء: $endVotes');

      if (continueVotes > endVotes) {
        // الأغلبية تريد الإكمال
        log('▶️ الأغلبية تريد الإكمال - بدء الجولة: $nextRound');
        await startNewRound(roomId, nextRound, connectedPlayers);
      } else {
        // الأغلبية تريد الإنهاء أو تعادل
        final remainingSpies = connectedPlayers.where((p) => p['role'] == 'spy').toList();
        final winner = remainingSpies.isNotEmpty ? 'spy' : 'normal_players';
        log('🏁 الأغلبية تريد الإنهاء - الفائز: $winner');
        await endGame(roomId, winner);
      }

    } catch (e) {
      log('❌ خطأ في معالجة نتائج تصويت الإكمال: $e');
      rethrow;
    }
  }

  /// الاستماع لتحديثات الغرفة
  Stream<Map<String, dynamic>> listenToRoom(String roomId) {
    return _client
        .from('rooms')
        .stream(primaryKey: ['id'])
        .eq('id', roomId)
        .map((List<Map<String, dynamic>> data) => data.isNotEmpty ? data.first : {});
  }
}