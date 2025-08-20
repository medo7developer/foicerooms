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

// إضافة هذه الدالة في نهاية الكلاس:
  bool get isConnected => _roomChannel != null;

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
          log('تحديث في الغرفة: ${payload.eventType} - ${payload
              .newRecord?['state']}');
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
          log('تحديث في اللاعبين: ${payload.eventType} - ${payload
              .newRecord?['name'] ?? payload.oldRecord?['name']}');
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

// تحديث دالة _startPeriodicRefresh:
  void _startPeriodicRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (timer) { // عودة إلى 3 ثواني
      if (_currentRoomId != null) {
        _refreshRoomData();
      }
    });
  }

// إضافة دالة للتحقق من تغيير الحالة:
  void _handleStateChange(GameState oldState, GameState newState) {
    if (oldState == GameState.playing && newState == GameState.voting) {
      log('انتقال من اللعب إلى التصويت - تحديث فوري');
      // تحديث فوري متعدد للتأكد
      _refreshRoomData();
      Future.delayed(const Duration(milliseconds: 200), () => _refreshRoomData());
      Future.delayed(const Duration(milliseconds: 500), () => _refreshRoomData());
    }
  }

  void _handleRoomUpdate(PostgresChangePayload payload) {
    try {
      log('🔄 معالجة تحديث الغرفة: ${payload.eventType}');

      // في حالة التحديث، تحقق من تغيير الحالة
      if (payload.eventType == PostgresChangeEvent.update) {
        final oldState = payload.oldRecord?['state'];
        final newState = payload.newRecord?['state'];

        if (oldState != newState) {
          log('🔄 تغيرت حالة الغرفة من $oldState إلى $newState');

          // معالجة خاصة للانتقالات المهمة
          if (oldState == 'voting' && (newState == 'continue_voting' || newState == 'playing' || newState == 'finished')) {
            log('⚡ انتقال مهم من التصويت - تحديث فوري متعدد');
            _refreshRoomData();
            Future.delayed(const Duration(milliseconds: 200), () => _refreshRoomData());
            Future.delayed(const Duration(milliseconds: 500), () => _refreshRoomData());
            Future.delayed(const Duration(milliseconds: 1000), () => _refreshRoomData());
            return;
          }

          if (oldState == 'continue_voting' && (newState == 'playing' || newState == 'finished')) {
            log('⚡ انتقال من تصويت الإكمال - تحديث فوري');
            _refreshRoomData();
            Future.delayed(const Duration(milliseconds: 300), () => _refreshRoomData());
            return;
          }
        }
      }

      // تحديث عادي للبيانات
      _refreshRoomData();

      // تحديث إضافي بعد تأخير قصير
      Future.delayed(const Duration(milliseconds: 300), () {
        _refreshRoomData();
      });
    } catch (e) {
      log('❌ خطأ في معالجة تحديث الغرفة: $e');
    }
  }
// تحديث دالة _handlePlayersUpdate:
  void _handlePlayersUpdate(PostgresChangePayload payload) {
    try {
      final eventType = payload.eventType;
      log('معالجة تحديث اللاعبين: $eventType');

      // تحديث فوري للبيانات
      _refreshRoomData();

      // تحديث إضافي بعد تأخير قصير
      Future.delayed(const Duration(milliseconds: 200), () {
        _refreshRoomData();
      });
    } catch (e) {
      log('خطأ في معالجة تحديث اللاعبين: $e');
    }
  }

// في دالة _refreshRoomData، استبدال المحاولة الكاملة:
  Future<void> _refreshRoomData() async {
    if (_currentRoomId == null || _gameProvider == null) return;

    try {
      final response = await _client
          .from('rooms')
          .select('*, players(*)')
          .eq('id', _currentRoomId!)
          .order('id', referencedTable: 'players') // تم التعديل هنا
          .maybeSingle();

      if (response == null) {
        log('الغرفة $_currentRoomId لم تعد موجودة');
        return;
      }

      // تحويل البيانات وتحديث GameProvider
      final updatedRoom = _convertToGameRoom(response);
      if (updatedRoom != null && _currentPlayerId != null) {
        log('تحديث بيانات الغرفة: ${updatedRoom
            .state} - عدد اللاعبين: ${updatedRoom.players.length}');
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
      case 'continue_voting':
        return GameState.continueVoting;
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

  void checkConnection() {
    if (!isConnected && _currentRoomId != null && _currentPlayerId != null) {
      log('إعادة الاتصال بالغرفة $_currentRoomId');
      subscribeToRoom(_currentRoomId!, _currentPlayerId!);
    }
  }
}