import 'dart:developer';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/game_provider.dart';

class SupabaseService {
  final SupabaseClient _client = Supabase.instance.client;

  // إنشاء غرفة جديدة مع التحقق من الحالة الحالية
  Future<String?> createRoom({
    required String name,
    required String creatorId,
    required int maxPlayers,
    required int totalRounds,
    required int roundDuration,
  }) async {
    try {
      // التحقق من وجود المستخدم في غرفة أخرى أولاً
      final existingPlayer = await _client
          .from('players')
          .select('room_id, rooms!inner(state)')
          .eq('id', creatorId)
          .maybeSingle();

      if (existingPlayer != null) {
        final roomState = existingPlayer['rooms']['state'];
        if (roomState == 'waiting' || roomState == 'playing' || roomState == 'voting') {
          log('المستخدم موجود بالفعل في غرفة نشطة');
          return null; // المستخدم في غرفة نشطة
        }
      }

      final roomId = DateTime.now().millisecondsSinceEpoch.toString();

      // إنشاء الغرفة
      await _client.from('rooms').insert({
        'id': roomId,
        'name': name,
        'creator_id': creatorId,
        'max_players': maxPlayers,
        'total_rounds': totalRounds,
        'round_duration': roundDuration,
        'state': 'waiting',
        'created_at': DateTime.now().toIso8601String(),
      });

      // إضافة المنشئ كلاعب في الغرفة
      await _client.from('players').insert({
        'id': creatorId,
        'name': 'منشئ الغرفة', // سيتم تحديثه لاحقاً
        'room_id': roomId,
        'is_connected': true,
        'is_voted': false,
        'votes': 0,
        'role': 'normal',
      });

      log('تم إنشاء الغرفة: $roomId بواسطة $creatorId');
      return roomId;
    } catch (e) {
      log('خطأ في إنشاء الغرفة: $e');
      return null;
    }
  }

  // الحصول على الغرف المتاحة مع فلترة أفضل
  Future<List<GameRoom>> getAvailableRooms() async {
    try {
      final response = await _client
          .from('rooms')
          .select('*, players(*)')
          .inFilter('state', ['waiting', 'playing', 'voting'])
          .order('created_at', ascending: false);

      final List<GameRoom> rooms = [];

      for (final roomData in response) {
        try {
          final players = (roomData['players'] as List? ?? [])
              .map((p) => Player(
            id: p['id'] ?? '',
            name: p['name'] ?? 'لاعب',
            isConnected: p['is_connected'] ?? false,
            isVoted: p['is_voted'] ?? false,
            votes: p['votes'] ?? 0,
            role: (p['role'] == 'spy') ? PlayerRole.spy : PlayerRole.normal,
          ))
              .toList();

          rooms.add(GameRoom(
            id: roomData['id'] ?? '',
            name: roomData['name'] ?? 'غرفة بدون اسم',
            creatorId: roomData['creator_id'] ?? '',
            maxPlayers: roomData['max_players'] ?? 4,
            totalRounds: roomData['total_rounds'] ?? 3,
            roundDuration: roomData['round_duration'] ?? 300,
            players: players,
            state: _parseGameState(roomData['state']),
            currentRound: roomData['current_round'] ?? 0,
            currentWord: roomData['current_word'],
            spyId: roomData['spy_id'],
          ));
        } catch (e) {
          log('خطأ في معالجة غرفة: $e');
          continue; // تخطي الغرفة المعطوبة
        }
      }

      log('تم جلب ${rooms.length} غرفة من قاعدة البيانات');
      return rooms;
    } catch (e) {
      log('خطأ في جلب الغرف: $e');
      return [];
    }
  }

  // التحقق من حالة المستخدم الحالية
  Future<UserStatus> checkUserStatus(String playerId) async {
    try {
      final playerData = await _client
          .from('players')
          .select('room_id, rooms!inner(id, name, state, creator_id)')
          .eq('id', playerId)
          .maybeSingle();

      if (playerData == null) {
        return UserStatus.free;
      }

      final roomState = playerData['rooms']['state'];
      final roomId = playerData['rooms']['id'];
      final creatorId = playerData['rooms']['creator_id'];

      if (roomState == 'finished') {
        // تنظيف الغرف المنتهية
        await _cleanupFinishedRoom(roomId);
        return UserStatus.free;
      }

      if (roomState == 'waiting' || roomState == 'playing' || roomState == 'voting') {
        return UserStatus(
          inRoom: true,
          roomId: roomId,
          roomName: playerData['rooms']['name'],
          isOwner: creatorId == playerId,
          roomState: roomState,
        );
      }

      return UserStatus.free;
    } catch (e) {
      log('خطأ في التحقق من حالة المستخدم: $e');
      return UserStatus.free;
    }
  }

  // تعديل دالة الانضمام لتتضمن إشعار المنشئ
  Future<JoinResult> joinRoom(String roomId, String playerId, String playerName) async {
    try {
      final userStatus = await checkUserStatus(playerId);
      if (userStatus.inRoom) {
        log('المستخدم موجود بالفعل في غرفة: ${userStatus.roomId}');
        return JoinResult(
          success: false,
          reason: 'أنت موجود بالفعل في غرفة "${userStatus.roomName}"',
          existingRoomId: userStatus.roomId,
        );
      }

      final roomData = await _client
          .from('rooms')
          .select('id, max_players, state, creator_id, players(*)')
          .eq('id', roomId)
          .maybeSingle();

      if (roomData == null) {
        return JoinResult(success: false, reason: 'الغرفة غير موجودة');
      }

      final roomState = roomData['state'];
      if (roomState != 'waiting') {
        return JoinResult(success: false, reason: 'الغرفة غير متاحة للانضمام');
      }

      final currentPlayers = (roomData['players'] as List? ?? []).length;
      final maxPlayers = roomData['max_players'] ?? 4;

      if (currentPlayers >= maxPlayers) {
        return JoinResult(success: false, reason: 'الغرفة ممتلئة');
      }

      // إضافة اللاعب
      await _client.from('players').upsert({
        'id': playerId,
        'name': playerName,
        'room_id': roomId,
        'is_connected': true,
        'is_voted': false,
        'votes': 0,
        'role': 'normal',
      });

      // التحقق من اكتمال العدد وإشعار المنشئ
      final updatedCount = currentPlayers + 1;
      if (updatedCount >= maxPlayers) {
        await _notifyRoomFull(roomId, roomData['creator_id']);
      }

      log('انضم اللاعب $playerName للغرفة $roomId (${updatedCount}/$maxPlayers)');
      return JoinResult(success: true, reason: 'تم الانضمام بنجاح');

    } catch (e) {
      log('خطأ في الانضمام للغرفة: $e');
      return JoinResult(success: false, reason: 'خطأ في الاتصال، حاول مرة أخرى');
    }
  }

  // دالة جديدة لإشعار المنشئ باكتمال العدد
  Future<void> _notifyRoomFull(String roomId, String creatorId) async {
    try {
      // يمكن إضافة إشعار في قاعدة البيانات أو إشعار مباشر
      await _client.from('rooms').update({
        'ready_to_start': true,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', roomId);

      log('تم إشعار المنشئ $creatorId باكتمال العدد في الغرفة $roomId');
    } catch (e) {
      log('خطأ في إشعار اكتمال العدد: $e');
    }
  }

  // دالة محسنة لبدء اللعبة مع التحقق المحسن
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
      final gameWords = [
        'مدرسة', 'مستشفى', 'مطعم', 'مكتبة', 'حديقة',
        'بنك', 'صيدلية', 'سوق', 'سينما', 'متحف',
        'شاطئ', 'جبل', 'غابة', 'صحراء', 'نهر',
        'طائرة', 'سيارة', 'قطار', 'سفينة', 'دراجة',
        'طبيب', 'مدرس', 'مهندس', 'طباخ', 'فنان',
      ];

      // خلط اللاعبين واختيار الجاسوس
      connectedPlayers.shuffle();
      final spyIndex = DateTime.now().millisecond % connectedPlayers.length;
      final spyId = connectedPlayers[spyIndex]['id'];

      gameWords.shuffle();
      final selectedWord = gameWords.first;

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

  // إضافة دالة للتحكم في انتهاء الجولة بشكل صحيح:
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

  // إضافة دالة للتحقق من انتهاء التصويت
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

// دالة انتهاء الجولة المحدثة
  Future<void> _endRound(String roomId, List<dynamic> players) async {
    try {
      // العثور على اللاعب الأكثر تصويتاً
      players.sort((a, b) => (b['votes'] ?? 0).compareTo(a['votes'] ?? 0));
      final mostVoted = players.first;
      final mostVotedId = mostVoted['id'];
      final isSpyEliminated = mostVoted['role'] == 'spy';

      // إزالة اللاعب الأكثر تصويتاً
      await _client.from('players').delete().eq('id', mostVotedId);

      // الحصول على اللاعبين المتبقين
      final remainingPlayers = await _client
          .from('players')
          .select('*')
          .eq('room_id', roomId);

      final remainingSpies = remainingPlayers.where((p) => p['role'] == 'spy').toList();
      final normalPlayers = remainingPlayers.where((p) => p['role'] == 'normal').toList();

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
        await _endGame(roomId, 'normal_players');
      } else if (remainingPlayers.length < 3) {
        // انتهاء اللعبة - عدد اللاعبين قليل جداً
        await _endGame(roomId, remainingSpies.isNotEmpty ? 'spy' : 'normal_players');
      } else if (currentRound >= totalRounds) {
        // انتهاء الجولات - فوز الجاسوس
        await _endGame(roomId, 'spy');
      } else {
        // التصويت على إكمال الجولات
        await _startContinueVoting(roomId, currentRound + 1, remainingPlayers);
      }

      log('انتهت الجولة - اللاعب المحذوف: $mostVotedId، اللاعبين المتبقين: ${remainingPlayers.length}');
    } catch (e) {
      log('خطأ في انتهاء الجولة: $e');
    }
  }

// دالة جديدة لإنهاء اللعبة
  Future<void> _endGame(String roomId, String winner) async {
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

// دالة جديدة لبدء التصويت على إكمال الجولات
  Future<void> _startContinueVoting(String roomId, int nextRound, List<dynamic> remainingPlayers) async {
    try {
      // تحديث حالة الغرفة للتصويت على الإكمال
      await _client.from('rooms').update({
        'state': 'continue_voting',
        'next_round': nextRound,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', roomId);

      // إعادة تعيين حالة التصويت لجميع اللاعبين
      for (final player in remainingPlayers) {
        await _client.from('players').update({
          'is_voted': false,
          'votes': 0, // سنستخدم votes لحفظ خيار الإكمال (1 = إكمال، 0 = إنهاء)
        }).eq('id', player['id']);
      }

      log('بدء التصويت على إكمال الجولات في الغرفة $roomId');
    } catch (e) {
      log('خطأ في بدء تصويت الإكمال: $e');
    }
  }

  // دالة التصويت على إكمال الجولات
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

// دالة التحقق من انتهاء تصويت الإكمال
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
          await _startNewRound(roomId, nextRound, connectedPlayers);
        } else {
          // الأغلبية تريد الإنهاء أو تعادل
          final remainingSpies = connectedPlayers.where((p) => p['role'] == 'spy').toList();
          await _endGame(roomId, remainingSpies.isNotEmpty ? 'spy' : 'normal_players');
        }

        log('انتهى التصويت على الإكمال - إكمال: $continueVotes، إنهاء: $endVotes');
      }
    } catch (e) {
      log('خطأ في التحقق من تصويت الإكمال: $e');
    }
  }

// دالة بدء جولة جديدة
  Future<void> _startNewRound(String roomId, int roundNumber, List<dynamic> players) async {
    try {
      // اختيار جاسوس جديد
      final connectedPlayers = players.where((p) => p['is_connected'] == true).toList();
      connectedPlayers.shuffle();
      final newSpyIndex = DateTime.now().millisecond % connectedPlayers.length;
      final newSpyId = connectedPlayers[newSpyIndex]['id'];

      // اختيار كلمة جديدة
      final gameWords = [
        'مدرسة', 'مستشفى', 'مطعم', 'مكتبة', 'حديقة',
        'بنك', 'صيدلية', 'سوق', 'سينما', 'متحف',
        'شاطئ', 'جبل', 'غابة', 'صحراء', 'نهر',
        'طائرة', 'سيارة', 'قطار', 'سفينة', 'دراجة',
        'طبيب', 'مدرس', 'مهندس', 'طباخ', 'فنان',
      ];
      gameWords.shuffle();
      final newWord = gameWords.first;

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

  // إضافة دالة للتحقق من إمكانية بدء اللعبة
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

  // تنظيف الغرف المنتهية
  Future<void> _cleanupFinishedRoom(String roomId) async {
    try {
      await _client.from('players').delete().eq('room_id', roomId);
      await _client.from('rooms').delete().eq('id', roomId);
      log('تم تنظيف الغرفة المنتهية: $roomId');
    } catch (e) {
      log('خطأ في تنظيف الغرفة: $e');
    }
  }

  // بدء اللعبة
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

// تعديل دالة updateVote في SupabaseService
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

  // إرسال إشارة WebRTC
  Future<void> sendSignal({
    required String roomId,
    required String fromPeer,
    required String toPeer,
    required String type,
    required Map<String, dynamic> data,
  }) async {
    try {
      await _client.from('signaling').insert({
        'room_id': roomId,
        'from_peer': fromPeer,
        'to_peer': toPeer,
        'type': type,
        'data': data,
        'created_at': DateTime.now().toIso8601String(),
      });

      log('تم إرسال إشارة $type من $fromPeer إلى $toPeer');
    } catch (e) {
      log('خطأ في إرسال الإشارة: $e');
    }
  }

  // الاستماع للإشارات
  Stream<Map<String, dynamic>> listenToSignals(String peerId) {
    return _client
        .from('signaling')
        .stream(primaryKey: ['id'])
        .eq('to_peer', peerId)
        .map((List<Map<String, dynamic>> data) => data.isNotEmpty ? data.last : {});
  }

  // الاستماع لتحديثات الغرفة
  Stream<Map<String, dynamic>> listenToRoom(String roomId) {
    return _client
        .from('rooms')
        .stream(primaryKey: ['id'])
        .eq('id', roomId)
        .map((List<Map<String, dynamic>> data) => data.isNotEmpty ? data.first : {});
  }

  // الاستماع لتحديثات اللاعبين
  Stream<List<Map<String, dynamic>>> listenToPlayers(String roomId) {
    return _client
        .from('players')
        .stream(primaryKey: ['id'])
        .eq('room_id', roomId);
  }

  // مغادرة الغرفة
  Future<void> leaveRoom(String playerId) async {
    try {
      // الحصول على معلومات الغرفة قبل المغادرة
      final playerData = await _client
          .from('players')
          .select('room_id, rooms!inner(creator_id)')
          .eq('id', playerId)
          .maybeSingle();

      if (playerData != null) {
        final roomId = playerData['room_id'];
        final creatorId = playerData['rooms']['creator_id'];

        // حذف اللاعب
        await _client.from('players').delete().eq('id', playerId);

        // إذا كان منشئ الغرفة، احذف الغرفة كاملة
        if (creatorId == playerId) {
          await _client.from('rooms').delete().eq('id', roomId);
          log('تم حذف الغرفة $roomId لأن المنشئ غادر');
        }
      }

      log('غادر اللاعب $playerId الغرفة');
    } catch (e) {
      log('خطأ في مغادرة الغرفة: $e');
    }
  }

  // حذف إشارة بعد المعالجة
  Future<void> deleteSignal(int signalId) async {
    try {
      await _client.from('signaling').delete().eq('id', signalId);
    } catch (e) {
      log('خطأ في حذف الإشارة: $e');
    }
  }

  // حذف غرفة (للمالك فقط)
  Future<bool> deleteRoom(String roomId, String userId) async {
    try {
      // التحقق من أن المستخدم هو مالك الغرفة
      final room = await _client
          .from('rooms')
          .select('creator_id')
          .eq('id', roomId)
          .maybeSingle();

      if (room == null || room['creator_id'] != userId) {
        log('المستخدم غير مخول لحذف هذه الغرفة');
        return false;
      }

      // حذف الغرفة (سيتم حذف اللاعبين تلقائياً بسبب cascade)
      await _client.from('rooms').delete().eq('id', roomId);
      log('تم حذف الغرفة: $roomId');
      return true;
    } catch (e) {
      log('خطأ في حذف الغرفة: $e');
      return false;
    }
  }

  // الحصول على معلومات الغرفة بأمان
  Future<GameRoom?> getRoomById(String roomId) async {
    try {
      final response = await _client
          .from('rooms')
          .select('*, players(*)')
          .eq('id', roomId)
          .maybeSingle();

      if (response == null) {
        log('الغرفة $roomId غير موجودة');
        return null;
      }

      final players = (response['players'] as List? ?? [])
          .map((p) => Player(
        id: p['id'] ?? '',
        name: p['name'] ?? 'لاعب',
        isConnected: p['is_connected'] ?? false,
        isVoted: p['is_voted'] ?? false,
        votes: p['votes'] ?? 0,
        role: (p['role'] == 'spy') ? PlayerRole.spy : PlayerRole.normal,
      ))
          .toList();

      return GameRoom(
        id: response['id'] ?? '',
        name: response['name'] ?? 'غرفة',
        creatorId: response['creator_id'] ?? '',
        maxPlayers: response['max_players'] ?? 4,
        totalRounds: response['total_rounds'] ?? 3,
        roundDuration: response['round_duration'] ?? 300,
        players: players,
        state: _parseGameState(response['state']),
        currentRound: response['current_round'] ?? 0,
        currentWord: response['current_word'],
        spyId: response['spy_id'],
      );
    } catch (e) {
      log('خطأ في جلب معلومات الغرفة: $e');
      return null;
    }
  }

  GameState _parseGameState(String? state) {
    switch (state?.toLowerCase()) {
      case 'waiting':
        return GameState.waiting;
      case 'playing':
        return GameState.playing;
      case 'voting':
        return GameState.voting;
      case 'continue_voting':
        return GameState.continueVoting;
      case 'finished':
        return GameState.finished;
      default:
        log('حالة غير معروفة: $state');
        return GameState.waiting;
    }
  }
}

// كلاسات مساعدة لإدارة حالة المستخدم
class UserStatus {
  final bool inRoom;
  final String? roomId;
  final String? roomName;
  final bool isOwner;
  final String? roomState;

  UserStatus({
    this.inRoom = false,
    this.roomId,
    this.roomName,
    this.isOwner = false,
    this.roomState,
  });

  static UserStatus get free => UserStatus();
}

class JoinResult {
  final bool success;
  final String reason;
  final String? existingRoomId;

  JoinResult({
    required this.success,
    required this.reason,
    this.existingRoomId,
  });
}