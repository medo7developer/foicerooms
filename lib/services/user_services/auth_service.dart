import 'dart:developer';
import 'dart:io';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/user_model.dart';

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // تكوين Google Sign-In بشكل صحيح لـ Supabase
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      'email',
      'profile',
    ],
    // Client ID للويب من Google Cloud Console (ليس Firebase)
    // سيتم الحصول عليه من Google Cloud Console
    serverClientId: "780961481011-0iam080l7tss375rhkpu2kv2v8i5e0fd.apps.googleusercontent.com", // سيتم تعيينه لاحقاً
  );

  UserModel? _currentUser;
  UserModel? get currentUser => _currentUser;

  // تهيئة Google Sign-In
  Future<void> _initializeGoogleSignIn() async {
    try {
      log('تهيئة Google Sign-In');
      // التأكد من عدم وجود جلسة سابقة
      await _googleSignIn.signOut();
      log('تم تهيئة Google Sign-In بنجاح');
    } catch (e) {
      log('خطأ في تهيئة Google Sign-In: $e');
    }
  }

  // تسجيل الدخول بـ Google
  Future<AuthResult> signInWithGoogle() async {
    try {
      log('بدء تسجيل الدخول بـ Google');

      // تهيئة Google Sign-In أولاً
      await _initializeGoogleSignIn();

      // محاولة تسجيل الدخول
      GoogleSignInAccount? googleUser;

      try {
        googleUser = await _googleSignIn.signIn();
      } catch (e) {
        log('خطأ في تسجيل الدخول بـ Google: $e');

        // محاولة أخرى مع إعادة تهيئة
        try {
          await _googleSignIn.disconnect();
          await Future.delayed(const Duration(milliseconds: 500));
          googleUser = await _googleSignIn.signIn();
        } catch (e2) {
          log('فشل في المحاولة الثانية: $e2');
          return AuthResult(
              success: false,
              message: 'فشل في الاتصال بخدمة Google. تأكد من الاتصال بالإنترنت وحاول مرة أخرى.'
          );
        }
      }

      if (googleUser == null) {
        return AuthResult(success: false, message: 'تم إلغاء تسجيل الدخول');
      }

      log('تم تسجيل الدخول بـ Google: ${googleUser.email}');

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      if (googleAuth.idToken == null) {
        return AuthResult(success: false, message: 'فشل في الحصول على رمز المصادقة');
      }

      log('تم الحصول على رمز المصادقة');

      // تسجيل الدخول بـ Supabase
      final AuthResponse response = await _supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: googleAuth.idToken!,
        accessToken: googleAuth.accessToken,
      );

      if (response.user == null) {
        return AuthResult(success: false, message: 'فشل تسجيل الدخول مع Supabase');
      }

      log('تم تسجيل الدخول مع Supabase');

      // إنشاء أو تحديث بيانات المستخدم
      final user = await _createOrUpdateUser(response.user!);
      _currentUser = user;

      // حفظ بيانات المستخدم محلياً
      await _saveUserLocally(user);

      log('تم تسجيل الدخول بنجاح: ${user.displayName}');
      return AuthResult(success: true, user: user);
    } catch (e) {
      log('خطأ في تسجيل الدخول بـ Google: $e');
      return AuthResult(
          success: false,
          message: 'خطأ في تسجيل الدخول. تأكد من تكوين التطبيق بشكل صحيح.'
      );
    }
  }

  // تسجيل الخروج
  Future<void> signOut() async {
    try {
      await _supabase.auth.signOut();
      await _googleSignIn.signOut();
      _currentUser = null;
      await _clearUserLocally();
      log('تم تسجيل الخروج');
    } catch (e) {
      log('خطأ في تسجيل الخروج: $e');
    }
  }

  // التحقق من حالة تسجيل الدخول
  Future<bool> checkAuthStatus() async {
    try {
      // أولاً محاولة تحميل من التخزين المحلي
      final savedUser = await _loadUserLocally();
      if (savedUser != null) {
        _currentUser = savedUser;
        log('تم تحميل المستخدم من التخزين المحلي: ${savedUser.displayName}');

        // التحقق من جلسة Supabase في الخلفية
        final session = _supabase.auth.currentSession;
        if (session?.user != null) {
          // تحديث البيانات من قاعدة البيانات
          final updatedUser = await _getUserFromDatabase(session!.user.id);
          if (updatedUser != null) {
            _currentUser = updatedUser;
            await _saveUserLocally(updatedUser);
          }
        }

        return true;
      }

      // إذا لم يكن هناك مستخدم محفوظ، تحقق من جلسة Supabase
      final session = _supabase.auth.currentSession;
      if (session?.user != null) {
        _currentUser = await _getUserFromDatabase(session!.user.id);
        if (_currentUser == null) {
          // إنشاء المستخدم إذا لم يكن موجوداً
          _currentUser = await _createOrUpdateUser(session.user);
        }

        // حفظ المستخدم محلياً
        await _saveUserLocally(_currentUser!);
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

      // البحث عن المستخدم الموجود
      final existingUser = await _supabase
          .from('users')
          .select()
          .eq('id', supabaseUser.id)
          .maybeSingle();

      if (existingUser == null) {
        // إنشاء مستخدم جديد
        userData['created_at'] = DateTime.now().toIso8601String();
        userData['is_profile_complete'] = false;

        await _supabase.from('users').insert(userData);
        log('تم إنشاء مستخدم جديد: ${userData['display_name']}');
      } else {
        // تحديث المستخدم الموجود - احتفاظ بحالة الملف الشخصي
        userData['is_profile_complete'] = existingUser['is_profile_complete'] ?? false;
        userData['custom_avatar_path'] = existingUser['custom_avatar_path'];
        userData['created_at'] = existingUser['created_at'];

        await _supabase.from('users')
            .update(userData)
            .eq('id', supabaseUser.id);
        log('تم تحديث بيانات المستخدم: ${userData['display_name']}');
      }

      // جلب البيانات المحدثة
      final updatedUser = await _supabase
          .from('users')
          .select()
          .eq('id', supabaseUser.id)
          .single();

      return UserModel.fromJson(updatedUser);
    } catch (e) {
      log('خطأ في إنشاء/تحديث المستخدم: $e');
      // إرجاع مستخدم افتراضي
      return UserModel(
        id: supabaseUser.id,
        email: supabaseUser.email ?? '',
        displayName: supabaseUser.userMetadata?['full_name'] ?? 'مستخدم',
        photoURL: supabaseUser.userMetadata?['avatar_url'],
        createdAt: DateTime.now(),
        lastLoginAt: DateTime.now(),
        isProfileComplete: false, // التأكد من أنه false للمستخدمين الجدد
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

      // رفع الصورة إذا تم تحديدها
      if (avatarFile != null) {
        final fileName = '${_currentUser!.id}_avatar_${DateTime.now().millisecondsSinceEpoch}';
        final response = await _supabase.storage
            .from('user-avatars')
            .upload('$fileName.jpg', avatarFile);

        if (response.isNotEmpty) {
          uploadedAvatarPath = response;
        }
      }

      // تحديث البيانات
      final updateData = <String, dynamic>{};
      if (displayName != null) updateData['display_name'] = displayName;
      if (uploadedAvatarPath != null) updateData['custom_avatar_path'] = uploadedAvatarPath;
      if (customAvatarPath != null) updateData['custom_avatar_path'] = customAvatarPath;

      // هذا هو الأهم - تحديد أن الملف الشخصي مكتمل
      updateData['is_profile_complete'] = true;

      if (updateData.isNotEmpty) {
        await _supabase.from('users')
            .update(updateData)
            .eq('id', _currentUser!.id);

        // تحديث الكائن المحلي
        _currentUser = _currentUser!.copyWith(
          displayName: displayName ?? _currentUser!.displayName,
          customAvatarPath: uploadedAvatarPath ?? customAvatarPath ?? _currentUser!.customAvatarPath,
          isProfileComplete: true, // التأكد من تحديث هذا
        );

        // حفظ البيانات المحدثة محلياً
        await _saveUserLocally(_currentUser!);
        log('تم تحديث ملف المستخدم الشخصي - الملف مكتمل: ${_currentUser!.isProfileComplete}');
        return true;
      }

      return false;
    } catch (e) {
      log('خطأ في تحديث ملف المستخدم: $e');
      return false;
    }
  }

  // حفظ المستخدم محلياً - طريقة محسنة
  Future<void> _saveUserLocally(UserModel user) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // حفظ كل قيمة بشكل منفصل لضمان الدقة
      await prefs.setString('user_id', user.id);
      await prefs.setString('user_email', user.email);
      await prefs.setString('user_display_name', user.displayName);
      await prefs.setString('user_photo_url', user.photoURL ?? '');
      await prefs.setString('user_custom_avatar_path', user.customAvatarPath ?? '');
      await prefs.setString('user_created_at', user.createdAt.toIso8601String());
      await prefs.setString('user_last_login_at', user.lastLoginAt.toIso8601String());
      await prefs.setBool('user_is_profile_complete', user.isProfileComplete);

      log('تم حفظ المستخدم محلياً - الملف مكتمل: ${user.isProfileComplete}');
    } catch (e) {
      log('خطأ في حفظ المستخدم محلياً: $e');
    }
  }

  // تحميل المستخدم محلياً - طريقة محسنة
  Future<UserModel?> _loadUserLocally() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final userId = prefs.getString('user_id');
      if (userId == null) return null;

      final email = prefs.getString('user_email') ?? '';
      final displayName = prefs.getString('user_display_name') ?? '';
      final photoURL = prefs.getString('user_photo_url');
      final customAvatarPath = prefs.getString('user_custom_avatar_path');
      final createdAtStr = prefs.getString('user_created_at');
      final lastLoginAtStr = prefs.getString('user_last_login_at');
      final isProfileComplete = prefs.getBool('user_is_profile_complete') ?? false;

      if (createdAtStr == null || lastLoginAtStr == null) return null;

      final user = UserModel(
        id: userId,
        email: email,
        displayName: displayName,
        photoURL: photoURL?.isEmpty == true ? null : photoURL,
        customAvatarPath: customAvatarPath?.isEmpty == true ? null : customAvatarPath,
        createdAt: DateTime.parse(createdAtStr),
        lastLoginAt: DateTime.parse(lastLoginAtStr),
        isProfileComplete: isProfileComplete,
      );

      log('تم تحميل المستخدم محلياً - الملف مكتمل: ${user.isProfileComplete}');
      return user;
    } catch (e) {
      log('خطأ في تحميل المستخدم محلياً: $e');
      return null;
    }
  }

  // مسح المستخدم محلياً
  Future<void> _clearUserLocally() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // حذف جميع المفاتيح المتعلقة بالمستخدم
      await prefs.remove('user_id');
      await prefs.remove('user_email');
      await prefs.remove('user_display_name');
      await prefs.remove('user_photo_url');
      await prefs.remove('user_custom_avatar_path');
      await prefs.remove('user_created_at');
      await prefs.remove('user_last_login_at');
      await prefs.remove('user_is_profile_complete');

      log('تم مسح بيانات المستخدم محلياً');
    } catch (e) {
      log('خطأ في مسح المستخدم محلياً: $e');
    }
  }

  // تحديث إحصائيات المستخدم مع الاسم والإيميل
  Future<void> syncUserWithExperienceService() async {
    if (_currentUser == null) return;

    try {
      // هنا نحدث الخدمات الأخرى لتستخدم بيانات المستخدم الجديدة
      // سيتم استدعاء هذا من ExperienceService
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