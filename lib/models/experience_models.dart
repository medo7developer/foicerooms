// ملف: lib/models/experience_models.dart
import 'package:flutter/material.dart';

enum BadgeType {
  masterSpy,        // ماستر جاسوس
  spyHunter,        // صائد الجواسيس
  survivalist,      // خبير البقاء
  sharpDetective,   // محقق بارع
}

enum RewardType {
  xp,              // خبرة
  badge,           // شارة
  title,           // لقب
}

class PlayerStats {
  final String playerId;
  final String playerName;  // إضافة حقل الاسم
  final String? playerEmail;    // إضافة حقل الإيميل
  final String? playerPhotoUrl; // إضافة حقل الصورة
  final int totalGames;
  final int wins;
  final int losses;
  final int spyWins;           // انتصارات كجاسوس
  final int detectiveWins;     // انتصارات ككاشف
  final int timesWasSpy;       // مرات كونه جاسوساً
  final int timesDetectedSpy;  // مرات اكتشاف الجاسوس
  final int totalXP;
  final int level;
  final Map<BadgeType, int> badges;
  final List<String> titles;
  final DateTime lastUpdated;

  PlayerStats({
    required this.playerId,
    this.playerName = 'لاعب مجهول',  // قيمة افتراضية
    this.playerEmail,           // إضافة للكونستركتر
    this.playerPhotoUrl,        // إضافة للكونستركتر
    this.totalGames = 0,
    this.wins = 0,
    this.losses = 0,
    this.spyWins = 0,
    this.detectiveWins = 0,
    this.timesWasSpy = 0,
    this.timesDetectedSpy = 0,
    this.totalXP = 0,
    this.level = 1,
    this.badges = const {},
    this.titles = const [],
    required this.lastUpdated,
  });

  // حساب مستوى اللاعب من الخبرة
  int get calculatedLevel => (totalXP / 1000).floor() + 1;

  // معدل الانتصار
  double get winRate => totalGames > 0 ? (wins / totalGames) * 100 : 0;

  // معدل نجاح التجسس
  double get spySuccessRate => timesWasSpy > 0 ? (spyWins / timesWasSpy) * 100 : 0;

  // معدل كشف الجواسيس
  double get detectiveSuccessRate => totalGames - timesWasSpy > 0
      ? (detectiveWins / (totalGames - timesWasSpy)) * 100 : 0;

  PlayerStats copyWith({
    String? playerId,
    String? playerName,  // إضافة للـ copyWith
    String? playerEmail,        // إضافة
    String? playerPhotoUrl,     // إضافة
    int? totalGames,
    int? wins,
    int? losses,
    int? spyWins,
    int? detectiveWins,
    int? timesWasSpy,
    int? timesDetectedSpy,
    int? totalXP,
    int? level,
    Map<BadgeType, int>? badges,
    List<String>? titles,
    DateTime? lastUpdated,
  }) {
    return PlayerStats(
      playerId: playerId ?? this.playerId,
      playerName: playerName ?? this.playerName,  // إضافة هنا
      totalGames: totalGames ?? this.totalGames,
      wins: wins ?? this.wins,
      losses: losses ?? this.losses,
      spyWins: spyWins ?? this.spyWins,
      detectiveWins: detectiveWins ?? this.detectiveWins,
      timesWasSpy: timesWasSpy ?? this.timesWasSpy,
      timesDetectedSpy: timesDetectedSpy ?? this.timesDetectedSpy,
      totalXP: totalXP ?? this.totalXP,
      level: level ?? this.level,
      badges: badges ?? this.badges,
      titles: titles ?? this.titles,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }

  Map<String, dynamic> toJson() => {
    'player_id': playerId,
    'player_name': playerName,  // إضافة للـ JSON
    'player_email': playerEmail,       // إضافة
    'player_photo_url': playerPhotoUrl, // إضافة
    'total_games': totalGames,
    'wins': wins,
    'losses': losses,
    'spy_wins': spyWins,
    'detective_wins': detectiveWins,
    'times_was_spy': timesWasSpy,
    'times_detected_spy': timesDetectedSpy,
    'total_xp': totalXP,
    'level': level,
    'badges': badges.map((k, v) => MapEntry(k.name, v)),
    'titles': titles,
    'last_updated': lastUpdated.toIso8601String(),
  };

  // دالة خاصة للJSON مع بيانات المستخدم
  Map<String, dynamic> toJsonWithUserData(String? email, String? photoUrl) => {
    'player_id': playerId,
    'player_name': playerName,
    'player_email': email,
    'player_photo_url': photoUrl,
    'total_games': totalGames,
    'wins': wins,
    'losses': losses,
    'spy_wins': spyWins,
    'detective_wins': detectiveWins,
    'times_was_spy': timesWasSpy,
    'times_detected_spy': timesDetectedSpy,
    'total_xp': totalXP,
    'level': level,
    'badges': badges.map((k, v) => MapEntry(k.name, v)),
    'titles': titles,
    'last_updated': lastUpdated.toIso8601String(),
  };

  factory PlayerStats.fromJson(Map<String, dynamic> json) {
    return PlayerStats(
      playerId: json['player_id'] ?? '',
      playerName: json['player_name'] ?? 'لاعب مجهول',  // إضافة من JSON
      playerEmail: json['player_email'],           // إضافة
      playerPhotoUrl: json['player_photo_url'],    // إضافة
      totalGames: json['total_games'] ?? 0,
      wins: json['wins'] ?? 0,
      losses: json['losses'] ?? 0,
      spyWins: json['spy_wins'] ?? 0,
      detectiveWins: json['detective_wins'] ?? 0,
      timesWasSpy: json['times_was_spy'] ?? 0,
      timesDetectedSpy: json['times_detected_spy'] ?? 0,
      totalXP: json['total_xp'] ?? 0,
      level: json['level'] ?? 1,
      badges: (json['badges'] as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(
          BadgeType.values.firstWhere((e) => e.name == k),
          v as int
      )),
      titles: List<String>.from(json['titles'] ?? []),
      lastUpdated: DateTime.parse(json['last_updated']),
    );
  }

  // دالة خاصة للتحويل مع بيانات المستخدم
  factory PlayerStats.fromJsonWithUserData(
      Map<String, dynamic> json,
      String? email,
      String? photoUrl,
      ) {
    return PlayerStats(
      playerId: json['player_id'] ?? '',
      playerName: json['player_name'] ?? 'لاعب مجهول',
      playerEmail: email ?? json['player_email'],
      playerPhotoUrl: photoUrl ?? json['player_photo_url'],
      totalGames: json['total_games'] ?? 0,
      wins: json['wins'] ?? 0,
      losses: json['losses'] ?? 0,
      spyWins: json['spy_wins'] ?? 0,
      detectiveWins: json['detective_wins'] ?? 0,
      timesWasSpy: json['times_was_spy'] ?? 0,
      timesDetectedSpy: json['times_detected_spy'] ?? 0,
      totalXP: json['total_xp'] ?? 0,
      level: json['level'] ?? 1,
      badges: (json['badges'] as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(
          BadgeType.values.firstWhere((e) => e.name == k),
          v as int
      )),
      titles: List<String>.from(json['titles'] ?? []),
      lastUpdated: DateTime.parse(json['last_updated']),
    );
  }

}

class GameReward {
  final RewardType type;
  final int xpAmount;
  final BadgeType? badgeType;
  final String? title;
  final String description;
  final bool isNew; // هل هذه أول مرة يحصل فيها على هذه المكافأة

  GameReward({
    required this.type,
    this.xpAmount = 0,
    this.badgeType,
    this.title,
    required this.description,
    this.isNew = false,
  });
}

class LeaderboardEntry {
  final String playerId;
  final String playerName;
  final int totalXP;
  final int level;
  final int wins;
  final double winRate;
  final Map<BadgeType, int> badges;
  final int rank;

  LeaderboardEntry({
    required this.playerId,
    required this.playerName,
    required this.totalXP,
    required this.level,
    required this.wins,
    required this.winRate,
    required this.badges,
    required this.rank,
  });
}

// مساعدات لأسماء الشارات والألقاب
class BadgeUtils {
  static String getBadgeName(BadgeType type) {
    switch (type) {
      case BadgeType.masterSpy:
        return 'ماستر الجواسيس';
      case BadgeType.spyHunter:
        return 'صائد الجواسيس';
      case BadgeType.survivalist:
        return 'خبير البقاء';
      case BadgeType.sharpDetective:
        return 'محقق بارع';
    }
  }

  static String getBadgeDescription(BadgeType type) {
    switch (type) {
      case BadgeType.masterSpy:
        return 'فوز 10 مرات كجاسوس';
      case BadgeType.spyHunter:
        return 'اكتشاف 15 جاسوساً';
      case BadgeType.survivalist:
        return 'البقاء حتى النهاية 20 مرة';
      case BadgeType.sharpDetective:
        return 'معدل كشف جواسيس أعلى من 80%';
    }
  }

  static IconData getBadgeIcon(BadgeType type) {
    switch (type) {
      case BadgeType.masterSpy:
        return Icons.psychology;
      case BadgeType.spyHunter:
        return Icons.search;
      case BadgeType.survivalist:
        return Icons.shield;
      case BadgeType.sharpDetective:
        return Icons.visibility;
    }
  }

  static Color getBadgeColor(BadgeType type) {
    switch (type) {
      case BadgeType.masterSpy:
        return Colors.purple;
      case BadgeType.spyHunter:
        return Colors.orange;
      case BadgeType.survivalist:
        return Colors.green;
      case BadgeType.sharpDetective:
        return Colors.blue;
    }
  }
}

// ثوابت نظام المكافآت
class RewardConstants {
  // نقاط الخبرة
  static const int xpForWin = 100;
  static const int xpForLoss = 30;
  static const int xpForSpyWin = 150;
  static const int xpForDetectivWin = 120;
  static const int xpForSurviving = 50;

  // متطلبات الشارات
  static const int spyWinsForMaster = 10;
  static const int detectionsForHunter = 15;
  static const int survivalsForSurvivalist = 20;
  static const double detectiveRateForSharp = 80.0;

  // مستويات الخبرة
  static const int xpPerLevel = 1000;

  // ألقاب خاصة
  static const List<String> availableTitles = [
    'المحقق البارع',
    'الجاسوس المتخفي',
    'صائد الأسرار',
    'سيد التخفي',
    'كاشف الألغاز',
  ];
}