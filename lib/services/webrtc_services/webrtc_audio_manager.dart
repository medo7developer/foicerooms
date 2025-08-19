import 'dart:developer';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

class WebRTCAudioManager {
  final Map<String, RTCPeerConnection> peers;
  final Map<String, MediaStream> remoteStreams;
  final MediaStream? Function() getLocalStream;
  final Function(MediaStream?) setLocalStream;

  WebRTCAudioManager({
    required this.peers,
    required this.remoteStreams,
    required this.getLocalStream,
    required this.setLocalStream,
  });

  // طلب الصلاحيات
  Future<bool> requestPermissions() async {
    try {
      final status = await Permission.microphone.request();
      return status == PermissionStatus.granted;
    } catch (e) {
      log('خطأ في طلب الصلاحيات: $e');
      return false;
    }
  }

  // تهيئة الصوت المحلي
  Future<void> initializeLocalAudio() async {
    try {
      if (!await requestPermissions()) {
        throw Exception('صلاحيات الميكروفون غير متاحة');
      }

      final Map<String, dynamic> mediaConstraints = {
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': false,
      };

      final stream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      setLocalStream(stream);
      log('تم تهيئة الصوت المحلي بنجاح');
    } catch (e) {
      log('خطأ في تهيئة الصوت المحلي: $e');
      rethrow;
    }
  }

  // تبديل حالة الميكروفون
  Future<void> toggleMicrophone() async {
    final localStream = getLocalStream();
    if (localStream != null) {
      final audioTracks = localStream.getAudioTracks();
      if (audioTracks.isNotEmpty) {
        final track = audioTracks.first;
        track.enabled = !track.enabled;
        log('الميكروفون ${track.enabled ? 'مفعل' : 'مكتوم'}');

        // إشعار جميع الـ peers بحالة المسار الجديدة
        for (final entry in peers.entries) {
          final pc = entry.value;
          final List senders = await pc.getSenders();
          for (final sender in senders) {
            if (sender.track?.kind == 'audio') {
              // إعادة إرسال المسار المحدث
              sender.replaceTrack(track);
              log('تم تحديث مسار الصوت للـ peer ${entry.key}');
            }
          }
        }
      }
    }
  }

  // التحقق من حالة الميكروفون
  bool get isMicrophoneEnabled {
    final localStream = getLocalStream();
    if (localStream != null) {
      final audioTracks = localStream.getAudioTracks();
      if (audioTracks.isNotEmpty) {
        return audioTracks.first.enabled;
      }
    }
    return false;
  }

  // فحص المسارات الصوتية
  void checkAudioTracks() {
    final localStream = getLocalStream();
    if (localStream != null) {
      final tracks = localStream.getAudioTracks();
      log('المسارات الصوتية المحلية: ${tracks.length}');
      for (int i = 0; i < tracks.length; i++) {
        final track = tracks[i];
        log('المسار $i: enabled=${track.enabled}, kind=${track.kind}, id=${track.id}');
      }
    }

    for (final entry in remoteStreams.entries) {
      final tracks = entry.value.getAudioTracks();
      log('المسارات البعيدة من ${entry.key}: ${tracks.length}');
    }
  }

  // ضمان تشغيل الصوت
  Future<void> ensureAudioPlayback() async {
    log('🔊 ضمان تشغيل الصوت في جميع الاتصالات...');

    // تفعيل الصوت المحلي
    final localStream = getLocalStream();
    if (localStream != null) {
      final localTracks = localStream.getAudioTracks();
      for (final track in localTracks) {
        if (!track.enabled) {
          track.enabled = true;
          log('✓ تم تفعيل المسار المحلي: ${track.id}');
        }
      }
    }

    // تفعيل جميع المسارات البعيدة
    for (final entry in remoteStreams.entries) {
      final peerId = entry.key;
      final stream = entry.value;
      final audioTracks = stream.getAudioTracks();

      for (final track in audioTracks) {
        if (!track.enabled) {
          track.enabled = true;
          log('✓ تم تفعيل مسار بعيد من $peerId');
        }
      }
    }

    // إحصائيات نهائية
    final totalRemoteTracks = remoteStreams.values
        .map((s) => s.getAudioTracks().length)
        .fold(0, (sum, count) => sum + count);

    log('📊 إجمالي المسارات البعيدة المفعلة: $totalRemoteTracks');
  }

  // تحديث اتصالات الصوت
  Future<void> refreshAudioConnections() async {
    log('إعادة تنشيط اتصالات الصوت...');

    for (final entry in peers.entries) {
      final peerId = entry.key;
      final pc = entry.value;

      try {
        // التحقق من وجود مسارات صوتية
        final List senders = await pc.getSenders();
        bool hasAudioSender = false;

        for (final sender in senders) {
          if (sender.track?.kind == 'audio') {
            hasAudioSender = true;
            log('مسار صوتي موجود للـ peer $peerId');
            break;
          }
        }

        // إضافة مسار صوتي إذا لم يكن موجوداً
        final localStream = getLocalStream();
        if (!hasAudioSender && localStream != null) {
          final audioTracks = localStream.getAudioTracks();
          if (audioTracks.isNotEmpty) {
            await pc.addTrack(audioTracks.first, localStream);
            log('تم إضافة مسار صوتي جديد للـ peer $peerId');
          }
        }

      } catch (e) {
        log('خطأ في تنشيط الصوت للـ peer $peerId: $e');
      }
    }
  }

  // تفعيل الصوت البعيد
  void enableRemoteAudio() {
    log('تفعيل جميع المسارات الصوتية البعيدة...');

    for (final entry in remoteStreams.entries) {
      final peerId = entry.key;
      final stream = entry.value;
      final audioTracks = stream.getAudioTracks();

      log('معالجة الصوت البعيد لـ $peerId - عدد المسارات: ${audioTracks.length}');

      for (final track in audioTracks) {
        track.enabled = true;
        log('✓ تم تفعيل مسار صوتي بعيد: ${track.id} من $peerId');
      }
    }
  }

  // إضافة المسارات المحلية للاتصال
  Future<void> addLocalTracksToConnection(RTCPeerConnection pc, String peerId) async {
    final localStream = getLocalStream();
    if (localStream == null) {
      log('⚠️ لا يوجد مجرى محلي - إعادة التهيئة');
      await initializeLocalAudio();
    }

    final stream = getLocalStream();
    if (stream != null) {
      final audioTracks = stream.getAudioTracks();
      log('🎤 إضافة ${audioTracks.length} مسارات صوتية محلية لـ $peerId');

      for (final track in audioTracks) {
        // التأكد من تفعيل المسار
        track.enabled = true;

        try {
          await pc.addTrack(track, stream);
          log('✅ تم إضافة مسار صوتي محلي: ${track.id}');
        } catch (e) {
          log('❌ فشل في إضافة مسار صوتي: $e');
        }
      }
    }
  }

  // التحقق من المسارات المحلية
  Future<void> verifyLocalTracks(RTCPeerConnection pc, String peerId) async {
    final senders = await pc.getSenders();
    bool hasAudioSender = false;

    for (final sender in senders) {
      if (sender.track?.kind == 'audio') {
        hasAudioSender = true;
        break;
      }
    }

    if (!hasAudioSender) {
      log('⚠️ لا يوجد مرسل صوتي لـ $peerId - إضافة مسار');
      await addLocalTracksToConnection(pc, peerId);
    }
  }

  // إعادة تشغيل جميع المسارات الصوتية
  Future<void> restartAllAudio() async {
    log('🔄 إعادة تشغيل جميع المسارات الصوتية...');

    // إعادة تشغيل الصوت المحلي
    final localStream = getLocalStream();
    if (localStream != null) {
      final localTracks = localStream.getAudioTracks();
      for (final track in localTracks) {
        // إعادة تعيين الإعدادات
        track.enabled = false;
        await Future.delayed(const Duration(milliseconds: 100));
        track.enabled = true;
        log('🔄 تم إعادة تشغيل مسار محلي: ${track.id}');
      }
    }

    // إعادة تشغيل الصوت البعيد
    for (final entry in remoteStreams.entries) {
      final peerId = entry.key;
      final audioTracks = entry.value.getAudioTracks();

      for (final track in audioTracks) {
        track.enabled = false;
        await Future.delayed(const Duration(milliseconds: 100));
        track.enabled = true;
        log('🔄 تم إعادة تشغيل مسار بعيد من $peerId: ${track.id}');
      }
    }

    log('✅ تم إعادة تشغيل جميع المسارات الصوتية');
  }

  // تحديث المسارات الصوتية
  Future<void> refreshAudioTracks(String peerId) async {
    // تحديث المسارات المحلية
    final localStream = getLocalStream();
    if (localStream != null) {
      final localTracks = localStream.getAudioTracks();
      for (final track in localTracks) {
        track.enabled = true;
      }
    }

    // تحديث المسارات البعيدة
    final remoteStream = remoteStreams[peerId];
    if (remoteStream != null) {
      final remoteTracks = remoteStream.getAudioTracks();
      for (final track in remoteTracks) {
        track.enabled = true;
      }
    }
  }

  // ضمان تفعيل الصوت البعيد
  void ensureRemoteAudioEnabled(String peerId) {
    final stream = remoteStreams[peerId];
    if (stream != null) {
      final audioTracks = stream.getAudioTracks();
      for (final track in audioTracks) {
        if (!track.enabled) {
          track.enabled = true;
          log('🔊 تم تفعيل الصوت البعيد لـ $peerId');
        }
      }
    }
  }
}