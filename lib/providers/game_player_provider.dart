import 'dart:developer';
import 'package:flutter/material.dart';
import '../models/game_room_model.dart';
import '../models/player_model.dart';
import '../services/supabase_service.dart';
import 'game_state.dart'; // استخدام الـ Enum من الملف المنفصل

class GamePlayerProvider extends ChangeNotifier {
  Player? _currentPlayer;
  SupabaseService? _supabaseService;

  // Getters
  Player? get currentPlayer => _currentPlayer;

  bool get isCurrentPlayerSpy => _currentPlayer?.role == PlayerRole.spy; // استخدام الـ Enum من الملف المنفصل

  bool get isCurrentPlayerCreator {
    return _currentPlayer != null; // سيتم التحقق من الغرفة في GameProvider
  }

  bool get isCurrentPlayerEliminated {
    if (_currentPlayer == null) return false;
    // سيتم التحقق من الغرفة في GameProvider
    return false;
  }

  // Setters
  set currentPlayer(Player? player) {
    _currentPlayer = player;
    notifyListeners();
  }

  // إعداد الخدمات
  void setSupabaseService(SupabaseService service) {
    _supabaseService = service;
  }

  // وظائف اللاعب
  void updatePlayerFromServer(GameRoom serverRoom, String playerId) {
    try {
      // العثور على اللاعب الحالي في البيانات المحدثة
      Player? updatedPlayer;
      for (final player in serverRoom.players) {
        if (player.id == playerId) {
          updatedPlayer = player;
          break;
        }
      }

      if (updatedPlayer != null) {
        _currentPlayer = updatedPlayer;
        debugPrint('✅ تم العثور على اللاعب في البيانات المحدثة: ${updatedPlayer.name}');
      } else {
        debugPrint('⚠️ لم يتم العثور على اللاعب في البيانات المحدثة');
        // إنشاء بيانات مؤقتة للاعب
        _currentPlayer = Player(
          id: playerId,
          name: _currentPlayer?.name ?? 'لاعب',
          isConnected: true,
        );
      }

      notifyListeners();
    } catch (e) {
      debugPrint('❌ خطأ في تحديث اللاعب من الخادم: $e');
    }
  }

  void rejoinRoom(GameRoom room, String playerId) {
    try {
      // البحث عن اللاعب الحالي بأمان
      Player? currentPlayer;
      for (final player in room.players) {
        if (player.id == playerId) {
          currentPlayer = player;
          break;
        }
      }

      _currentPlayer = currentPlayer;
      notifyListeners();
    } catch (e) {
      debugPrint('خطأ في إعادة الانضمام للغرفة: $e');
    }
  }

  void updateConnectionStatus(String playerId, bool isConnected) {
    if (_currentPlayer == null) return;

    try {
      if (_currentPlayer!.id == playerId) {
        _currentPlayer = _currentPlayer!.copyWith(isConnected: isConnected);
        debugPrint('تم تحديث حالة الاتصال للاعب الحالي: $isConnected');
        notifyListeners();
      }
    } catch (e) {
      debugPrint('خطأ في تحديث حالة الاتصال للاعب الحالي: $e');
    }
  }

  void updatePlayerFromRealtime(GameRoom updatedRoom, String playerId) {
    // العثور على اللاعب الحالي
    Player? updatedPlayer;
    for (final player in updatedRoom.players) {
      if (player.id == playerId) {
        updatedPlayer = player;
        break;
      }
    }

    if (updatedPlayer == null) {
      log('⚠️ اللاعب $playerId تم إقصاؤه من الغرفة');
      _currentPlayer = Player(
        id: playerId,
        name: _currentPlayer?.name ?? 'لاعب محذوف',
        isConnected: false,
        isVoted: true,
        votes: 0,
        role: _currentPlayer?.role ?? PlayerRole.normal, // استخدام الـ Enum من الملف المنفصل
      );
    } else {
      _currentPlayer = updatedPlayer;
    }

    notifyListeners();
  }

  void leaveRoom() {
    _currentPlayer = null;
    notifyListeners();
  }

  // إعادة تعيين الكل
  void resetAll() {
    _currentPlayer = null;
    notifyListeners();
    debugPrint('تم إعادة تعيين بيانات اللاعب');
  }

  // تنظيف الموارد
  @override
  void dispose() {
    _currentPlayer = null;
    super.dispose();
  }
}