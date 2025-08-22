import 'dart:developer';
import 'dart:io';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/user_model.dart';

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;

  UserModel? _currentUser;
  UserModel? get currentUser => _currentUser;

  // --- تهيئة الخدمة ---
  Future<void> initialize() async {
    log('جاري تهيئة خدمة المصادقة...');
    await GoogleSignIn.instance.initialize(
      clientId: null, // Android بيستخدم auto
      serverClientId:
      "780961481011-0iam080l7tss375rhkpu2kv2v8i5e0fd.apps.googleusercontent.com", // Web Client ID
    );
    log('تم تهيئة GoogleSignIn.');
    await checkAuthStatus();
  }

  // --- تسجيل الدخول بـ Google ---
  Future<AuthResult> signInWithGoogle() async {
    try {
      log('بدء تسجيل الدخول بـ Google');

      final GoogleSignInAccount? googleUser =
      await GoogleSignIn.instance.authenticate();
      if (googleUser == null) {
        return AuthResult(success: false, message: 'تم إلغاء تسجيل الدخول');
      }

      // هنا بتطلب serverAuthCode عشان تستخدمه مع Supabase
      final GoogleSignInServerAuthorization? serverAuth =
      await googleUser.authorizationClient.authorizeServer(['email', 'profile']);

      if (serverAuth == null) {
        return AuthResult(
            success: false, message: 'فشل الحصول على Server Auth Code');
      }

      // تسجّل في Supabase باستخدام idToken (أو serverAuthCode)
      final AuthResponse response = await _supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: serverAuth.serverAuthCode,
      );

      if (response.user == null) {
        return AuthResult(
            success: false, message: 'فشل تسجيل الدخول في Supabase');
      }

      final user = await _createOrUpdateUser(response.user!);
      _currentUser = user;
      await _saveUserLocally(user);

      log('تم تسجيل الدخول بنجاح: ${user.displayName}');
      return AuthResult(success: true, user: user);
    } catch (e) {
      log('خطأ في تسجيل الدخول بـ Google: $e');
      return AuthResult(success: false, message: 'خطأ: $e');
    }
  }

  // --- تسجيل الخروج ---
  Future<void> signOut() async {
    try {
      await _supabase.auth.signOut();
      await GoogleSignIn.instance.disconnect();
      _currentUser = null;
      await _clearUserLocally();
      log('تم تسجيل الخروج');
    } catch (e) {
      log('خطأ في تسجيل الخروج: $e');
    }
  }

  // --- التحقق من حالة المصادقة ---
  Future<bool> checkAuthStatus() async {
    try {
      final session = _supabase.auth.currentSession;
      if (session?.user != null) {
        _currentUser = await _getUserFromDatabase(session!.user.id);
        if (_currentUser == null) {
          _currentUser = await _createOrUpdateUser(session.user);
        }
        return true;
      }
      final savedUser = await _loadUserLocally();
      if (savedUser != null) {
        _currentUser = savedUser;
        return true;
      }
      return false;
    } catch (e) {
      log('خطأ في فحص حالة المصادقة: $e');
      return false;
    }
  }

  // إنشاء أو تحديث المستخدم في قاعدة البيانات
  Future<UserModel> _createOrUpdateUser(User supabaseUser) async {
    try {
      final userData = {
        'id': supabaseUser.id,
        'email': supabaseUser.email ?? '',
        'display_name': supabaseUser.userMetadata?['full_name'] ??
            supabaseUser.userMetadata?['name'] ??
            'مستخدم',
        'photo_url': supabaseUser.userMetadata?['avatar_url'],
        'last_login_at': DateTime.now().toIso8601String(),
      };
      final existingUser = await _supabase
          .from('users')
          .select()
          .eq('id', supabaseUser.id)
          .maybeSingle();
      if (existingUser == null) {
        userData['created_at'] = DateTime.now().toIso8601String();
        userData['is_profile_complete'] = false;
        await _supabase.from('users').insert(userData);
        log('تم إنشاء مستخدم جديد: ${userData['display_name']}');
      } else {
        await _supabase.from('users')
            .update(userData)
            .eq('id', supabaseUser.id);
        log('تم تحديث بيانات المستخدم: ${userData['display_name']}');
      }
      final updatedUser = await _supabase
          .from('users')
          .select()
          .eq('id', supabaseUser.id)
          .single();
      return UserModel.fromJson(updatedUser);
    } catch (e) {
      log('خطأ في إنشاء/تحديث المستخدم: $e');
      return UserModel(
        id: supabaseUser.id,
        email: supabaseUser.email ?? '',
        displayName: supabaseUser.userMetadata?['full_name'] ?? 'مستخدم',
        photoURL: supabaseUser.userMetadata?['avatar_url'],
        createdAt: DateTime.now(),
        lastLoginAt: DateTime.now(),
      );
    }
  }

  // جلب المستخدم من قاعدة البيانات
  Future<UserModel?> _getUserFromDatabase(String userId) async {
    try {
      final userData = await _supabase
          .from('users')
          .select()
          .eq('id', userId)
          .maybeSingle();
      if (userData != null) {
        return UserModel.fromJson(userData);
      }
      return null;
    } catch (e) {
      log('خطأ في جلب المستخدم: $e');
      return null;
    }
  }

  // تحديث ملف المستخدم الشخصي
  Future<bool> updateUserProfile({
    String? displayName,
    String? customAvatarPath,
    File? avatarFile,
  }) async {
    try {
      if (_currentUser == null) return false;
      String? uploadedAvatarPath;
      if (avatarFile != null) {
        final fileName = '${_currentUser!.id}_avatar_${DateTime.now().millisecondsSinceEpoch}';
        final response = await _supabase.storage
            .from('user-avatars')
            .upload('$fileName.jpg', avatarFile);
        if (response.isNotEmpty) {
          uploadedAvatarPath = response;
        }
      }
      final updateData = <String, dynamic>{};
      if (displayName != null) updateData['display_name'] = displayName;
      if (uploadedAvatarPath != null) updateData['custom_avatar_path'] = uploadedAvatarPath;
      if (customAvatarPath != null) updateData['custom_avatar_path'] = customAvatarPath;
      updateData['is_profile_complete'] = true;
      if (updateData.isNotEmpty) {
        await _supabase.from('users')
            .update(updateData)
            .eq('id', _currentUser!.id);
        _currentUser = _currentUser!.copyWith(
          displayName: displayName ?? _currentUser!.displayName,
          customAvatarPath: uploadedAvatarPath ?? customAvatarPath ?? _currentUser!.customAvatarPath,
          isProfileComplete: true,
        );
        await _saveUserLocally(_currentUser!);
        log('تم تحديث ملف المستخدم الشخصي');
        return true;
      }
      return false;
    } catch (e) {
      log('خطأ في تحديث ملف المستخدم: $e');
      return false;
    }
  }

  // حفظ المستخدم محلياً
  Future<void> _saveUserLocally(UserModel user) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userJson = user.toJson();
      final entries = userJson.entries.map((e) => '${e.key}:${e.value}').join('|');
      await prefs.setString('current_user', entries);
    } catch (e) {
      log('خطأ في حفظ المستخدم محلياً: $e');
    }
  }

  // تحميل المستخدم محلياً
  Future<UserModel?> _loadUserLocally() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userString = prefs.getString('current_user');
      if (userString == null) return null;
      final userMap = <String, dynamic>{};
      for (final entry in userString.split('|')) {
        final parts = entry.split(':');
        if (parts.length == 2) {
          userMap[parts[0]] = parts[1];
        }
      }
      if (userMap.isNotEmpty) {
        return UserModel.fromJson(userMap);
      }
    } catch (e) {
      log('خطأ في تحميل المستخدم محلياً: $e');
    }
    return null;
  }

  // مسح المستخدم محلياً
  Future<void> _clearUserLocally() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('current_user');
    } catch (e) {
      log('خطأ في مسح المستخدم محلياً: $e');
    }
  }

  // تحديث إحصائيات المستخدم مع الاسم والإيميل
  Future<void> syncUserWithExperienceService() async {
    if (_currentUser == null) return;
    try {
      // هنا نحدث الخدمات الأخرى لتستخدم بيانات المستخدم الجديدة
    } catch (e) {
      log('خطأ في مزامنة المستخدم مع الخدمات: $e');
    }
  }
}

// نتيجة عملية المصادقة
class AuthResult {
  final bool success;
  final String? message;
  final UserModel? user;
  AuthResult({
    required this.success,
    this.message,
    this.user,
  });
}