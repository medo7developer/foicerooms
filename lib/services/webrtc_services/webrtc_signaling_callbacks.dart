import 'package:flutter_webrtc/flutter_webrtc.dart';

class WebRTCSignalingCallbacks {
  Function(String, RTCIceCandidate)? onIceCandidateGenerated;
  Function(String, RTCSessionDescription)? onOfferCreated;
  Function(String, RTCSessionDescription)? onAnswerCreated;

  // تعيين callbacks للإشارات
  void setCallbacks({
    Function(String, RTCIceCandidate)? onIceCandidate,
    Function(String, RTCSessionDescription)? onOffer,
    Function(String, RTCSessionDescription)? onAnswer,
  }) {
    onIceCandidateGenerated = onIceCandidate;
    onOfferCreated = onOffer;
    onAnswerCreated = onAnswer;
  }

  // مسح جميع الـ callbacks
  void clearCallbacks() {
    onIceCandidateGenerated = null;
    onOfferCreated = null;
    onAnswerCreated = null;
  }

  // التحقق من وجود callbacks
  bool get hasIceCandidateCallback => onIceCandidateGenerated != null;
  bool get hasOfferCallback => onOfferCreated != null;
  bool get hasAnswerCallback => onAnswerCreated != null;
  bool get hasAllCallbacks => hasIceCandidateCallback && hasOfferCallback && hasAnswerCallback;
}