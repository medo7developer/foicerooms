import 'package:flutter/material.dart';

class UserModel {
  final String id;
  final String email;
  final String displayName;
  final String? photoURL;
  final String? customAvatarPath;
  final DateTime createdAt;
  final DateTime lastLoginAt;
  final bool isProfileComplete;

  UserModel({
    required this.id,
    required this.email,
    required this.displayName,
    this.photoURL,
    this.customAvatarPath,
    required this.createdAt,
    required this.lastLoginAt,
    this.isProfileComplete = false,
  });

  // الحصول على الصورة المناسبة (Google أو مخصصة)
  String? get profileImageUrl => customAvatarPath ?? photoURL;

  UserModel copyWith({
    String? id,
    String? email,
    String? displayName,
    String? photoURL,
    String? customAvatarPath,
    DateTime? createdAt,
    DateTime? lastLoginAt,
    bool? isProfileComplete,
  }) {
    return UserModel(
      id: id ?? this.id,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      photoURL: photoURL ?? this.photoURL,
      customAvatarPath: customAvatarPath ?? this.customAvatarPath,
      createdAt: createdAt ?? this.createdAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
      isProfileComplete: isProfileComplete ?? this.isProfileComplete,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'display_name': displayName,
    'photo_url': photoURL,
    'custom_avatar_path': customAvatarPath,
    'created_at': createdAt.toIso8601String(),
    'last_login_at': lastLoginAt.toIso8601String(),
    'is_profile_complete': isProfileComplete,
  };

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] ?? '',
      email: json['email'] ?? '',
      displayName: json['display_name'] ?? '',
      photoURL: json['photo_url'],
      customAvatarPath: json['custom_avatar_path'],
      createdAt: DateTime.parse(json['created_at']),
      lastLoginAt: DateTime.parse(json['last_login_at']),
      isProfileComplete: json['is_profile_complete'] ?? false,
    );
  }
}

// أفاتارات افتراضية متاحة
class AvatarAssets {
  static const List<String> defaultAvatars = [
    'assets/avatars/avatar1.png',
    'assets/avatars/avatar2.png',
    'assets/avatars/avatar3.png',
    'assets/avatars/avatar4.png',
    'assets/avatars/avatar5.png',
    'assets/avatars/avatar6.png',
    'assets/avatars/avatar7.png',
    'assets/avatars/avatar8.png',
  ];

  static String getAvatarByIndex(int index) {
    return defaultAvatars[index % defaultAvatars.length];
  }
}