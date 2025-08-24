// lib/main.dart - نسخة محدثة مع حل مشكلة حالة الملف الشخصي

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'package:voice_rooms_app/providers/user_providers/auth_provider.dart';
import 'package:voice_rooms_app/screens/login_screen.dart';
import 'package:voice_rooms_app/screens/profile_setup_screen.dart';
import 'package:voice_rooms_app/services/experience_service.dart';
import 'services/supabase_service.dart';
import 'services/webrtc_services/webrtc_service.dart';
import 'services/realtime_manager.dart';
import 'providers/game_provider.dart';
import 'screens/home_screen.dart';
import 'dart:developer';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // تهيئة Supabase
    await Supabase.initialize(
      url: 'https://fikaujglqyffcszfjklh.supabase.co',
      anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZpa2F1amdscXlmZmNzemZqa2xoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTUyODQzMDAsImV4cCI6MjA3MDg2MDMwMH0.dSKM0Wv4worp2d6gUs1sopArZcFV4BtAmGRXz_lZkMc',
      debug: true,
    );

    log('تم تهيئة Supabase بنجاح');
  } catch (e) {
    log('خطأ في تهيئة Supabase: $e');
  }

  runApp(const VoiceRoomsApp());
}

class VoiceRoomsApp extends StatelessWidget {
  const VoiceRoomsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // إضافة AuthProvider في المقدمة
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => GameProvider()),
        Provider(create: (_) => SupabaseService()),
        Provider(create: (_) => ExperienceService()),
        Provider(create: (_) => WebRTCService()),
        Provider(create: (_) => RealtimeManager()),
      ],
      child: Consumer<AuthProvider>(
        builder: (context, authProvider, child) {
          return MaterialApp(
            title: 'غرف صوتية تفاعلية',
            debugShowCheckedModeBanner: false,
            navigatorKey: navigatorKey,
            theme: ThemeData(
              primarySwatch: Colors.purple,
              fontFamily: 'Arial',
              textTheme: const TextTheme(
                bodyLarge: TextStyle(fontSize: 16),
                bodyMedium: TextStyle(fontSize: 14),
                titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              elevatedButtonTheme: ElevatedButtonThemeData(
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              cardTheme: CardTheme(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
            ),
            routes: {
              '/': (context) => _getInitialScreen(authProvider),
              '/login': (context) => const LoginScreen(),
              '/profile-setup': (context) => const ProfileSetupScreen(),
              '/home': (context) => const HomeScreen(),
            },
            initialRoute: '/',
          );
        },
      ),
    );
  }

  // تحديد الشاشة الأولية بناءً على حالة المصادقة
  Widget _getInitialScreen(AuthProvider authProvider) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        log('StreamBuilder - isLoading: ${authProvider.isLoading}, isAuthenticated: ${authProvider.isAuthenticated}, isProfileComplete: ${authProvider.isProfileComplete}');

        // عرض شاشة التحميل عند التهيئة
        if (authProvider.isLoading) {
          log('عرض شاشة التحميل');
          return _buildLoadingScreen();
        }

        // إذا لم يكن مسجل دخول
        if (!authProvider.isAuthenticated) {
          log('المستخدم غير مسجل - عرض شاشة تسجيل الدخول');
          return const LoginScreen();
        }

        // إذا كان مسجل دخول ولكن الملف الشخصي غير مكتمل
        if (!authProvider.isProfileComplete) {
          log('المستخدم مسجل لكن الملف الشخصي غير مكتمل - عرض شاشة إعداد الملف الشخصي');
          return const ProfileSetupScreen();
        }

        // إذا كان كل شيء مكتمل
        log('كل شيء مكتمل - عرض الصفحة الرئيسية');
        return const HomeScreen();
      },
    );
  }

  Widget _buildLoadingScreen() {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF667eea), Color(0xFF764ba2), Color(0xFFf093fb)],
          ),
        ),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 20),
              Text(
                'جاري التحقق من حالة تسجيل الدخول...',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }
}