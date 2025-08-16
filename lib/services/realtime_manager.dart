// lib/services/realtime_manager.dart - إصلاحات شاملة

import 'dart:async';
import 'dart:developer';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/game_provider.dart';

class RealtimeManager {
  static final RealtimeManager _instance = RealtimeManager._internal();
  factory RealtimeManager() => _instance;
  RealtimeManager._internal();

  final SupabaseClient _client = Supabase.instance.client;
  RealtimeChannel? _roomChannel;

  GameProvider? _gameProvider;
  String? _currentRoomId;
  String? _currentPlayerId;
  Timer? _refreshTimer;

  // تسجيل GameProvider للتحديثات
  void registerGameProvider(GameProvider gameProvider) {
    _gameProvider = gameProvider;
    log('تم تسجيل GameProvider مع RealtimeManager');
  }

  // بدء الاستماع لغرفة معينة مع تحسينات
  Future<void> subscribeToRoom(String roomId, String playerId) async {
    try {
      await unsubscribeAll();

      _currentRoomId = roomId;
      _currentPlayerId = playerId;

      log('بدء الاستماع للغرفة: $roomId للاعب: $playerId');

      // إنشاء قناة واحدة لجميع التحديثات
      _roomChannel = _client.channel('room_realtime_$roomId');

      // الاستماع لتحديثات الغرفة
      _roomChannel!.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'rooms',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'id',
          value: roomId,
        ),
        callback: (payload) {
          log('تحديث في الغرفة: ${payload.eventType} - ${payload.newRecord?['state']}');
          _handleRoomUpdate(payload);
        },
      );

      // الاستماع لتحديثات اللاعبين
      _roomChannel!.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'players',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'room_id',
          value: roomId,
        ),
        callback: (payload) {
          log('تحديث في اللاعبين: ${payload.eventType} - ${payload.newRecord?['name'] ?? payload.oldRecord?['name']}');
          _handlePlayersUpdate(payload);
        },
      );

      // تفعيل القناة
      final status = await _roomChannel!.subscribe();
      log('حالة الاشتراك: $status');

      // تحديث فوري أول مرة
      await _refreshRoomData();

      // تشغيل مؤقت للتحديث الدوري كخطة احتياطية
      _startPeriodicRefresh();

    } catch (e) {
      log('خطأ في الاستماع للغرفة: $e');
    }
  }

  // تشغيل التحديث الدوري
  void _startPeriodicRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (_currentRoomId != null) {
        _refreshRoomData();
      }
    });
  }

  // معالجة تحديث الغرفة
  void _handleRoomUpdate(PostgresChangePayload payload) {
    try {
      log('معالجة تحديث الغرفة: ${payload.eventType}');

      // تحديث فوري للبيانات
      Future.delayed(const Duration(milliseconds: 500), () {
        _refreshRoomData();
      });

    } catch (e) {
      log('خطأ في معالجة تحديث الغرفة: $e');
    }
  }

  // معالجة تحديث اللاعبين
  void _handlePlayersUpdate(PostgresChangePayload payload) {
    try {
      final eventType = payload.eventType;
      log('معالجة تحديث اللاعبين: $eventType');

      switch (eventType) {
        case PostgresChangeEvent.insert:
          final newPlayer = payload.newRecord;
          if (newPlayer != null) {
            log('انضمام لاعب جديد: ${newPlayer['name']}');
          }
          break;
        case PostgresChangeEvent.update:
          final updatedPlayer = payload.newRecord;
          if (updatedPlayer != null) {
            log('تحديث لاعب: ${updatedPlayer['name']} - متصل: ${updatedPlayer['is_connected']}');
          }
          break;
        case PostgresChangeEvent.delete:
          final deletedPlayer = payload.oldRecord;
          if (deletedPlayer != null) {
            log('مغادرة لاعب: ${deletedPlayer['name']}');
          }
          break;
        case PostgresChangeEvent.all:
          // TODO: Handle this case.
          throw UnimplementedError();
      }

      // تحديث فوري للبيانات
      Future.delayed(const Duration(milliseconds: 200), () {
        _refreshRoomData();
      });

    } catch (e) {
      log('خطأ في معالجة تحديث اللاعبين: $e');
    }
  }

  // إعادة تحميل بيانات الغرفة من الخادم
  Future<void> _refreshRoomData() async {
    if (_currentRoomId == null || _gameProvider == null) return;

    try {
      final response = await _client
          .from('rooms')
          .select('*, players(*)')
          .eq('id', _currentRoomId!)
          .order('created_at', referencedTable: 'players')
          .maybeSingle();

      if (response == null) {
        log('الغرفة $_currentRoomId لم تعد موجودة');
        return;
      }

      // تحويل البيانات وتحديث GameProvider
      final updatedRoom = _convertToGameRoom(response);
      if (updatedRoom != null && _currentPlayerId != null) {
        log('تحديث بيانات الغرفة: ${updatedRoom.state} - عدد اللاعبين: ${updatedRoom.players.length}');
        _gameProvider!.updateRoomFromRealtime(updatedRoom, _currentPlayerId!);
      }
    } catch (e) {
      log('خطأ في إعادة تحميل بيانات الغرفة: $e');
    }
  }

  // تحويل بيانات قاعدة البيانات إلى GameRoom مع معالجة محسنة
  GameRoom? _convertToGameRoom(Map<String, dynamic> data) {
    try {
      final playersData = data['players'] as List? ?? [];
      final players = playersData
          .map((p) {
        try {
          return Player(
            id: p['id'] ?? '',
            name: p['name'] ?? 'لاعب',
            isConnected: p['is_connected'] ?? false,
            isVoted: p['is_voted'] ?? false,
            votes: p['votes'] ?? 0,
            role: (p['role'] == 'spy') ? PlayerRole.spy : PlayerRole.normal,
          );
        } catch (e) {
          log('خطأ في تحويل بيانات لاعب: $e');
          return null;
        }
      })
          .where((p) => p != null)
          .cast<Player>()
          .toList();

      DateTime? roundStartTime;
      if (data['round_start_time'] != null) {
        try {
          roundStartTime = DateTime.parse(data['round_start_time']);
        } catch (e) {
          log('خطأ في تحويل وقت بدء الجولة: $e');
        }
      }

      return GameRoom(
        id: data['id'] ?? '',
        name: data['name'] ?? 'غرفة',
        creatorId: data['creator_id'] ?? '',
        maxPlayers: data['max_players'] ?? 4,
        totalRounds: data['total_rounds'] ?? 3,
        roundDuration: data['round_duration'] ?? 300,
        players: players,
        state: _parseGameState(data['state']),
        currentRound: data['current_round'] ?? 0,
        currentWord: data['current_word'],
        spyId: data['spy_id'],
        roundStartTime: roundStartTime,
      );
    } catch (e) {
      log('خطأ في تحويل بيانات الغرفة: $e');
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
      case 'finished':
        return GameState.finished;
      default:
        log('حالة غير معروفة: $state');
        return GameState.waiting;
    }
  }

  // إلغاء جميع الاشتراكات
  Future<void> unsubscribeAll() async {
    try {
      _refreshTimer?.cancel();
      _refreshTimer = null;

      if (_roomChannel != null) {
        await _roomChannel!.unsubscribe();
        _roomChannel = null;
      }

      _currentRoomId = null;
      _currentPlayerId = null;

      log('تم إلغاء جميع اشتراكات Realtime');
    } catch (e) {
      log('خطأ في إلغاء الاشتراكات: $e');
    }
  }

  // تنظيف الموارد
  void dispose() {
    _refreshTimer?.cancel();
    unsubscribeAll();
    _gameProvider = null;
  }

  // دالة للتحديث اليدوي
  Future<void> forceRefresh() async {
    log('تحديث يدوي للبيانات');
    await _refreshRoomData();
  }
}