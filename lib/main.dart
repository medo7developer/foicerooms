import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'services/supabase_service.dart';
import 'services/webrtc_service.dart';
import 'providers/game_provider.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // تهيئة Supabase
  await Supabase.initialize(
    url: 'YOUR_SUPABASE_URL', // ضع رابط Supabase الخاص بك هنا
    anonKey: 'YOUR_SUPABASE_ANON_KEY', // ضع مفتاح Supabase هنا
  );

  runApp(const VoiceRoomsApp());
}

class VoiceRoomsApp extends StatelessWidget {
  const VoiceRoomsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => GameProvider()),
        Provider(create: (_) => SupabaseService()),
        Provider(create: (_) => WebRTCService()),
      ],
      child: MaterialApp(
        title: 'غرف صوتية تفاعلية',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primarySwatch: Colors.purple,
          fontFamily: 'Arial',
          textTheme: const TextTheme(
            bodyLarge: TextStyle(fontSize: 16),
            bodyMedium: TextStyle(fontSize: 14),
            titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),
        home: const HomeScreen(),
      ),
    );
  }
}