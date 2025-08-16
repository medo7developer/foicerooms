import 'package:flutter/material.dart';
import '../providers/game_provider.dart';
import '../services/supabase_service.dart';

class HomeScreenState {
  final TextEditingController nameController = TextEditingController();

  List<GameRoom> availableRooms = [];
  List<GameRoom> myRooms = [];
  bool isLoading = false;
  String? playerId;
  String? savedPlayerName;
  UserStatus? currentUserStatus;

  void dispose() {
    nameController.dispose();
  }
}