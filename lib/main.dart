// lib/main.dart - تعديلات الدمج

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
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
        ChangeNotifierProvider(create: (_) => GameProvider()),
        Provider(create: (_) => SupabaseService()),
        Provider(create: (_) => WebRTCService()),
        Provider(create: (_) => RealtimeManager()),
      ],
      child: MaterialApp(
        title: 'غرف صوتية تفاعلية',
        debugShowCheckedModeBanner: false,
        // إضافة navigatorKey للوصول للـ context من خارج Widget
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
        home: const HomeScreen(),
      ),
    );
  }
}
