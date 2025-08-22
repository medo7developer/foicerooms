// lib/main.dart - تعديلات الدمج

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'package:voice_rooms_app/providers/user_providers/auth_provider.dart';
import 'package:voice_rooms_app/screens/login_screen.dart';
import 'package:voice_rooms_app/screens/profile_setup_screen.dart';
import 'package:voice_rooms_app/services/experience_service.dart';
import 'services/supabase_service.dart';
import 'services/webrtc_services/webrtc_service.dart';
import 'services/realtime_manager.dart'; // إضافة جديدة
import 'providers/game_provider.dart';
import 'screens/home_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // تهيئة Supabase
  await Supabase.initialize(
    url: 'https://fikaujglqyffcszfjklh.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZpa2F1amdscXlmZmNzemZqa2xoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTUyODQzMDAsImV4cCI6MjA3MDg2MDMwMH0.dSKM0Wv4worp2d6gUs1sopArZcFV4BtAmGRXz_lZkMc',
    debug: true, // إضافة debug mode
  );

  runApp(const VoiceRoomsApp());
}

// تعديل VoiceRoomsApp:
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
            // إضافة نظام التوجيه الجديد
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
    if (authProvider.isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (!authProvider.isAuthenticated) {
      return const LoginScreen();
    }

    if (!authProvider.isProfileComplete) {
      return const ProfileSetupScreen();
    }

    return const HomeScreen();
  }
}


