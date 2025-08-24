import 'dart:io';
import 'package:flutter/material.dart';
import 'dart:developer';

import '../../models/user_model.dart';
import '../../services/user_services/auth_service.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();

  UserModel? _currentUser;
  bool _isLoading = false;
  bool _isAuthenticated = false;
  String? _errorMessage;

  // Getters
  UserModel? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _isAuthenticated;
  String? get errorMessage => _errorMessage;

  // معلومات اللاعب للاستخدام في التطبيق
  String get playerId => _currentUser?.id ?? '';
  String get playerName => _currentUser?.displayName ?? 'لاعب مجهول';
  String get playerEmail => _currentUser?.email ?? '';
  String? get playerImageUrl => _currentUser?.profileImageUrl;

  AuthProvider() {
    _checkInitialAuthState();
  }

  // فحص حالة المصادقة الأولية
  Future<void> _checkInitialAuthState() async {
    _setLoading(true);
    try {
      log('بدء فحص حالة المصادقة الأولية');

      final isAuth = await _authService.checkAuthStatus();
      _currentUser = _authService.currentUser;
      _isAuthenticated = isAuth;
      _errorMessage = null;

      log('نتيجة فحص المصادقة: isAuth=$isAuth, user=${_currentUser?.displayName}, profileComplete=${_currentUser?.isProfileComplete}');

    } catch (e) {
      log('خطأ في فحص حالة المصادقة: $e');
      _errorMessage = 'خطأ في فحص حالة المصادقة';
    } finally {
      _setLoading(false);
    }
  }

  // تسجيل الدخول بـ Google
  Future<bool> signInWithGoogle() async {
    _setLoading(true);
    _clearError();

    try {
      log('بدء تسجيل الدخول بـ Google');

      final result = await _authService.signInWithGoogle();

      if (result.success && result.user != null) {
        _currentUser = result.user;
        _isAuthenticated = true;

        log('نجح تسجيل الدخول: ${_currentUser?.displayName}, profileComplete=${_currentUser?.isProfileComplete}');

        _setLoading(false);
        notifyListeners();
        return true;
      } else {
        _errorMessage = result.message ?? 'فشل تسجيل الدخول';
        log('فشل تسجيل الدخول: ${_errorMessage}');
        _setLoading(false);
        return false;
      }
    } catch (e) {
      _errorMessage = 'خطأ في تسجيل الدخول: $e';
      log('خطأ في تسجيل الدخول: $e');
      _setLoading(false);
      return false;
    }
  }

  // تسجيل الخروج
  Future<void> signOut() async {
    _setLoading(true);
    try {
      log('بدء تسجيل الخروج');

      await _authService.signOut();
      _currentUser = null;
      _isAuthenticated = false;
      _clearError();

      log('تم تسجيل الخروج بنجاح');
    } catch (e) {
      log('خطأ في تسجيل الخروج: $e');
      _errorMessage = 'خطأ في تسجيل الخروج';
    } finally {
      _setLoading(false);
    }
  }

  // تحديث ملف المستخدم الشخصي
  Future<bool> updateUserProfile({
    String? displayName,
    String? customAvatarPath,
    File? avatarFile,
  }) async {
    _setLoading(true);
    try {
      log('بدء تحديث الملف الشخصي: displayName=$displayName, avatar=$customAvatarPath');

      final success = await _authService.updateUserProfile(
        displayName: displayName,
        customAvatarPath: customAvatarPath,
        avatarFile: avatarFile,
      );

      if (success) {
        _currentUser = _authService.currentUser;
        _clearError();

        log('تم تحديث الملف الشخصي بنجاح: profileComplete=${_currentUser?.isProfileComplete}');

        _setLoading(false);
        return true;
      } else {
        _errorMessage = 'فشل في تحديث الملف الشخصي';
        log('فشل في تحديث الملف الشخصي');
        _setLoading(false);
        return false;
      }
    } catch (e) {
      _errorMessage = 'خطأ في تحديث الملف الشخصي: $e';
      log('خطأ في تحديث الملف الشخصي: $e');
      _setLoading(false);
      return false;
    }
  }

  // التحقق من اكتمال الملف الشخصي
  bool get isProfileComplete {
    final result = _currentUser?.isProfileComplete ?? false;
    log('التحقق من اكتمال الملف الشخصي: $result');
    return result;
  }

  // مساعدات داخلية
  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  // إعادة تحميل بيانات المستخدم
  Future<void> refreshUser() async {
    if (_currentUser != null) {
      log('إعادة تحميل بيانات المستخدم');
      await _checkInitialAuthState();
    }
  }

  // طريقة لإجبار تحديث حالة الملف الشخصي (للاختبار)
  void forceProfileComplete() {
    log('إجبار تحديث حالة الملف الشخصي إلى مكتمل');
    if (_currentUser != null) {
      _currentUser = _currentUser!.copyWith(isProfileComplete: true);
      notifyListeners();
    }
  }
}