import 'dart:developer';
import 'package:flutter/material.dart';
import '../models/game_room_model.dart';
import '../models/player_model.dart';
import '../services/supabase_service.dart';

class GameRoomProvider extends ChangeNotifier {
  GameRoom? _currentRoom;
  List<GameRoom> _availableRooms = [];
  SupabaseService? _supabaseService;

  // متغيرات التتبع
  int _lastPlayersCount = 0;

  // Getters
  GameRoom? get currentRoom => _currentRoom;
  List<GameRoom> get availableRooms => _availableRooms;
  int get connectedPlayersCount {
    return _currentRoom?.players.where((p) => p.isConnected).length ?? 0;
  }

  bool get hasEnoughPlayers {
    return connectedPlayersCount >= 3; // الحد الأدنى 3 لاعبين
  }

  // Setters
  set currentRoom(GameRoom? room) {
    _currentRoom = room;
    notifyListeners();
  }

  // إعداد الخدمات
  void setSupabaseService(SupabaseService service) {
    _supabaseService = service;
  }

  // وظائف الغرف
  bool joinRoom(String roomId, String playerId, String playerName) {
    try {
      // البحث عن الغرفة بأمان
      GameRoom? targetRoom;
      // البحث في قائمة الغرف المتاحة
      for (final room in _availableRooms) {
        if (room.id == roomId) {
          targetRoom = room;
          break;
        }
      }

      // إذا لم توجد في المتاحة، تحقق من الغرفة الحالية
      if (targetRoom == null && _currentRoom?.id == roomId) {
        targetRoom = _currentRoom;
      }

      if (targetRoom == null) {
        debugPrint('⚠️ الغرفة غير موجودة في البيانات المحلية: $roomId');
        // بدلاً من الفشل، حاول إنشاء غرفة مؤقتة
        targetRoom = GameRoom(
          id: roomId,
          name: 'غرفة تحت التحميل...',
          creatorId: 'unknown',
          maxPlayers: 8,
          totalRounds: 3,
          roundDuration: 300,
          players: [],
        );
      }

      // التحقق من امتلاء الغرفة (تخطي هذا التحقق إذا كانت البيانات مؤقتة)
      if (targetRoom.name != 'غرفة تحت التحميل...' &&
          targetRoom.players.length >= targetRoom.maxPlayers) {
        debugPrint('⚠️ الغرفة ممتلئة محلياً');
        return false;
      }

      // التحقق من وجود اللاعب مسبقاً
      final existingPlayerIndex = targetRoom.players.indexWhere((p) => p.id == playerId);
      Player newPlayer;

      if (existingPlayerIndex != -1) {
        // تحديث بيانات اللاعب الموجود
        newPlayer = targetRoom.players[existingPlayerIndex].copyWith(
          isConnected: true,
          name: playerName,
        );
        targetRoom.players[existingPlayerIndex] = newPlayer;
        debugPrint('✅ تم تحديث بيانات اللاعب الموجود: $playerName');
      } else {
        // إضافة لاعب جديد
        newPlayer = Player(
          id: playerId,
          name: playerName,
          isConnected: true,
        );
        targetRoom.players = [...targetRoom.players, newPlayer];
        debugPrint('✅ تم إضافة لاعب جديد: $playerName');
      }

      // تحديث البيانات المحلية
      _currentRoom = targetRoom;
      _lastPlayersCount = targetRoom.players.length;

      // إزالة الغرفة من القائمة المتاحة إذا كانت موجودة
      _availableRooms.removeWhere((room) => room.id == roomId);

      // إشعار فوري بالتحديث
      notifyListeners();

      // إشعار إضافي بعد تأخير قصير للتأكد
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_currentRoom?.id == roomId) {
          notifyListeners();
        }
      });

      debugPrint('✅ تم الانضمام بنجاح محلياً - عدد اللاعبين: ${targetRoom.players.length}');
      return true;
    } catch (e) {
      debugPrint('❌ خطأ في الانضمام للغرفة محلياً: $e');
      return false;
    }
  }

  void updateRoomFromServer(GameRoom serverRoom, String playerId) {
    try {
      debugPrint('🔄 تحديث الغرفة من الخادم: ${serverRoom.id}');

      // تحديث بيانات الغرفة الحالية
      _currentRoom = serverRoom;

      // تحديث متغيرات التتبع
      _lastPlayersCount = serverRoom.players.length;

      // إشعار متعدد للتأكد من التحديث
      notifyListeners();

      Future.delayed(const Duration(milliseconds: 50), () {
        notifyListeners();
      });

      Future.delayed(const Duration(milliseconds: 200), () {
        notifyListeners();
      });

      debugPrint('✅ تم تحديث الغرفة من الخادم بنجاح');
    } catch (e) {
      debugPrint('❌ خطأ في تحديث الغرفة من الخادم: $e');
    }
  }

  GameRoom createRoom({
    required String name,
    required String creatorId,
    required String creatorName,
    required int maxPlayers,
    required int totalRounds,
    required int roundDuration,
    String? roomId,
  }) {
    try {
      final room = GameRoom(
        id: roomId ?? DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        creatorId: creatorId,
        maxPlayers: maxPlayers,
        totalRounds: totalRounds,
        roundDuration: roundDuration,
      );

      // إضافة المنشئ كأول لاعب
      final creator = Player(
        id: creatorId,
        name: creatorName,
        isConnected: true,
      );
      room.players = [creator];

      // تحديث البيانات المحلية
      _availableRooms.add(room);
      _currentRoom = room;
      _lastPlayersCount = 1;

      // إشعار فوري
      notifyListeners();

      // إشعار إضافي للتأكد
      Future.delayed(const Duration(milliseconds: 100), () {
        notifyListeners();
      });

      debugPrint('✅ تم إنشاء الغرفة محلياً: ${room.name}');
      return room;
    } catch (e) {
      debugPrint('❌ خطأ في إنشاء الغرفة محلياً: $e');
      throw e;
    }
  }

  void rejoinRoom(GameRoom room, String playerId) {
    try {
      _currentRoom = room;
      _lastPlayersCount = room.players.length;

      // إشعار فوري
      notifyListeners();

      debugPrint('تم إعادة الانضمام للغرفة: ${room.name} - الحالة: ${room.state}');
    } catch (e) {
      debugPrint('خطأ في إعادة الانضمام للغرفة: $e');
    }
  }

  void updateConnectionStatus(String playerId, bool isConnected) {
    if (_currentRoom == null) return;

    try {
      final playerIndex = _currentRoom!.players.indexWhere((p) => p.id == playerId);
      if (playerIndex != -1) {
        _currentRoom!.players[playerIndex] = _currentRoom!.players[playerIndex].copyWith(
            isConnected: isConnected
        );
        debugPrint('تحديث حالة الاتصال للاعب $playerId: $isConnected');
        notifyListeners();
      }
    } catch (e) {
      debugPrint('خطأ في تحديث حالة الاتصال: $e');
    }
  }

  void updateRoomFromRealtime(GameRoom updatedRoom, String playerId) {
    if (_currentRoom == null) return;

    // تحديث بيانات الغرفة
    _currentRoom = updatedRoom;

    // تحديث متغيرات التتبع
    _lastPlayersCount = updatedRoom.players.length;

    notifyListeners();
  }

  void leaveRoom() {
    try {
      if (_currentRoom != null) {
        // إذا كان مالك الغرفة، إزالة الغرفة من القائمة
        if (_availableRooms.any((room) => room.id == _currentRoom!.id)) {
          _availableRooms.removeWhere((room) => room.id == _currentRoom!.id);
        }
      }

      _currentRoom = null;
      notifyListeners();

      debugPrint('تم مغادرة الغرفة');
    } catch (e) {
      debugPrint('خطأ في مغادرة الغرفة: $e');
    }
  }

  void updateAvailableRooms(List<GameRoom> rooms) {
    _availableRooms = rooms;
    notifyListeners();
  }

  // وظائف التحقق من التغييرات
  bool hasPlayersCountChanged() {
    return _lastPlayersCount != (_currentRoom?.players.length ?? 0);
  }

  // وظائف التحقق والتحقق من الصحة
  bool validateAndFixGameState(Player? currentPlayer) {
    try {
      if (_currentRoom == null) {
        debugPrint('⚠️ لا توجد غرفة حالية');
        return false;
      }

      if (currentPlayer == null) {
        debugPrint('⚠️ لا يوجد لاعب حالي');
        return false;
      }

      // التحقق من وجود اللاعب في قائمة اللاعبين
      final playerExists = _currentRoom!.players.any((p) => p.id == currentPlayer.id);
      if (!playerExists) {
        debugPrint('⚠️ اللاعب الحالي غير موجود في قائمة اللاعبين، جاري الإصلاح...');
        // إضافة اللاعب للقائمة
        _currentRoom!.players.add(currentPlayer);
        notifyListeners();
        debugPrint('✅ تم إصلاح بيانات اللاعب');
      }

      return true;
    } catch (e) {
      debugPrint('❌ خطأ في التحقق من البيانات: $e');
      return false;
    }
  }

  // إعادة تعيين الكل
  void resetAll() {
    _currentRoom = null;
    _availableRooms.clear();
    _lastPlayersCount = 0;
    notifyListeners();
    debugPrint('تم إعادة تعيين جميع بيانات الغرفة');
  }

  // تنظيف الموارد
  @override
  void dispose() {
    _currentRoom = null;
    _availableRooms.clear();
    super.dispose();
  }
}