import 'dart:developer';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/game_provider.dart';

class SupabaseService {
  final SupabaseClient _client = Supabase.instance.client;

  // إنشاء جداول قاعدة البيانات
  // يجب تشغيل هذه الاستعلامات في Supabase SQL Editor:
  /*
  CREATE TABLE rooms (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    creator_id TEXT NOT NULL,
    max_players INTEGER NOT NULL,
    total_rounds INTEGER NOT NULL,
    round_duration INTEGER NOT NULL,
    state TEXT DEFAULT 'waiting',
    current_round INTEGER DEFAULT 0,
    current_word TEXT,
    spy_id TEXT,
    round_start_time TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW()
  );

  CREATE TABLE players (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    room_id TEXT REFERENCES rooms(id) ON DELETE CASCADE,
    is_connected BOOLEAN DEFAULT FALSE,
    is_voted BOOLEAN DEFAULT FALSE,
    votes INTEGER DEFAULT 0,
    role TEXT DEFAULT 'normal',
    joined_at TIMESTAMP DEFAULT NOW()
  );

  CREATE TABLE signaling (
    id SERIAL PRIMARY KEY,
    room_id TEXT NOT NULL,
    from_peer TEXT NOT NULL,
    to_peer TEXT NOT NULL,
    type TEXT NOT NULL, -- 'offer', 'answer', 'ice-candidate'
    data JSONB NOT NULL,
    created_at TIMESTAMP DEFAULT NOW()
  );

  -- Real-time subscriptions
  ALTER TABLE rooms ENABLE ROW LEVEL SECURITY;
  ALTER TABLE players ENABLE ROW LEVEL SECURITY;
  ALTER TABLE signaling ENABLE ROW LEVEL SECURITY;
  */

  // إنشاء غرفة جديدة
  Future<String?> createRoom({
    required String name,
    required String creatorId,
    required int maxPlayers,
    required int totalRounds,
    required int roundDuration,
  }) async {
    try {
      final roomId = DateTime.now().millisecondsSinceEpoch.toString();

      final response = await _client.from('rooms').insert({
        'id': roomId,
        'name': name,
        'creator_id': creatorId,
        'max_players': maxPlayers,
        'total_rounds': totalRounds,
        'round_duration': roundDuration,
      });

      log('تم إنشاء الغرفة: $roomId');
      return roomId;
    } catch (e) {
      log('خطأ في إنشاء الغرفة: $e');
      return null;
    }
  }

  // الحصول على الغرف المتاحة
  Future<List<GameRoom>> getAvailableRooms() async {
    try {
      final response = await _client
          .from('rooms')
          .select('*, players(*)')
          .eq('state', 'waiting')
          .order('created_at', ascending: false);

      final List<GameRoom> rooms = [];

      for (final roomData in response) {
        final players = (roomData['players'] as List? ?? [])
            .map((p) => Player(
          id: p['id'],
          name: p['name'],
          isConnected: p['is_connected'] ?? false,
          isVoted: p['is_voted'] ?? false,
          votes: p['votes'] ?? 0,
          role: p['role'] == 'spy' ? PlayerRole.spy : PlayerRole.normal,
        ))
            .toList();

        rooms.add(GameRoom(
          id: roomData['id'],
          name: roomData['name'],
          creatorId: roomData['creator_id'],
          maxPlayers: roomData['max_players'],
          totalRounds: roomData['total_rounds'],
          roundDuration: roomData['round_duration'],
          players: players,
          state: _parseGameState(roomData['state']),
          currentRound: roomData['current_round'] ?? 0,
          currentWord: roomData['current_word'],
          spyId: roomData['spy_id'],
        ));
      }

      return rooms;
    } catch (e) {
      log('خطأ في جلب الغرف: $e');
      return [];
    }
  }

  // الانضمام لغرفة
  Future<bool> joinRoom(String roomId, String playerId, String playerName) async {
    try {
      // التحقق من عدد اللاعبين
      final roomResponse = await _client
          .from('rooms')
          .select('max_players, players(*)')
          .eq('id', roomId)
          .single();

      final currentPlayers = (roomResponse['players'] as List? ?? []).length;
      if (currentPlayers >= roomResponse['max_players']) {
        return false;
      }

      // إضافة اللاعب
      await _client.from('players').insert({
        'id': playerId,
        'name': playerName,
        'room_id': roomId,
        'is_connected': true,
      });

      log('انضم اللاعب $playerName للغرفة $roomId');
      return true;
    } catch (e) {
      log('خطأ في الانضمام للغرفة: $e');
      return false;
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

  // تحديث التصويت
  Future<void> updateVote(String playerId, String targetId) async {
    try {
      // تحديث حالة التصويت للاعب
      await _client.from('players').update({
        'is_voted': true,
      }).eq('id', playerId);

      // زيادة عدد الأصوات للهدف
      final currentVotes = await _client
          .from('players')
          .select('votes')
          .eq('id', targetId)
          .single();

      await _client.from('players').update({
        'votes': (currentVotes['votes'] ?? 0) + 1,
      }).eq('id', targetId);

      log('تم تسجيل صوت من $playerId لـ $targetId');
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
        .map((List<Map<String, dynamic>> data) => data.last);
  }

  // الاستماع لتحديثات الغرفة
  Stream<Map<String, dynamic>> listenToRoom(String roomId) {
    return _client
        .from('rooms')
        .stream(primaryKey: ['id'])
        .eq('id', roomId)
        .map((List<Map<String, dynamic>> data) => data.first);
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
      await _client.from('players').delete().eq('id', playerId);
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

  GameState _parseGameState(String state) {
    switch (state) {
      case 'waiting':
        return GameState.waiting;
      case 'playing':
        return GameState.playing;
      case 'voting':
        return GameState.voting;
      case 'finished':
        return GameState.finished;
      default:
        return GameState.waiting;
    }
  }
}