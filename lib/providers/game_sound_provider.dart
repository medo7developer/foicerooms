import 'package:flutter/material.dart';

class GameSoundProvider extends ChangeNotifier {
  bool _isSoundEnabled = true;
  double _volumeLevel = 1.0;

  // Getters
  bool get isSoundEnabled => _isSoundEnabled;
  double get volumeLevel => _volumeLevel;

  // وظائف الصوت
  void toggleSound() {
    _isSoundEnabled = !_isSoundEnabled;
    notifyListeners();
  }

  void setVolume(double volume) {
    _volumeLevel = volume.clamp(0.0, 1.0);
    notifyListeners();
  }

  void playSound(String soundName) {
    if (!_isSoundEnabled) return;
    // هنا سيتم تنفيذ تشغيل الصوت
    debugPrint('تشغيل صوت: $soundName بمستوى صوت: $_volumeLevel');
  }

  void playBackgroundMusic() {
    if (!_isSoundEnabled) return;
    // هنا سيتم تنفيذ تشغيل الموسيقى الخلفية
    debugPrint('تشغيل الموسيقى الخلفية بمستوى صوت: $_volumeLevel');
  }

  void stopBackgroundMusic() {
    // هنا سيتم تنفيذ إيقاف الموسيقى الخلفية
    debugPrint('إيقاف الموسيقى الخلفية');
  }

  void stopAllSounds() {
    // هنا سيتم تنفيذ إيقاف جميع الأصوات
    debugPrint('إيقاف جميع الأصوات');
  }

  // تنظيف الموارد
  @override
  void dispose() {
    stopAllSounds();
    super.dispose();
  }
}