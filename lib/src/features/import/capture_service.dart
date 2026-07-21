import 'dart:io';

import 'package:flutter/services.dart';

/// Bridge to the native NotificationListenerService (Android only). It queues
/// bank/wallet transaction notifications on-device; this reads/clears that
/// queue and manages the "notification access" permission.
class CaptureService {
  static const _ch = MethodChannel('tally/capture');

  bool get supported => Platform.isAndroid;

  /// Whether the user has granted notification access to Tally.
  Future<bool> isEnabled() async {
    if (!supported) return false;
    return await _ch.invokeMethod<bool>('isEnabled') ?? false;
  }

  /// Opens the system "notification access" settings screen.
  Future<void> openSettings() async {
    if (supported) await _ch.invokeMethod<void>('openSettings');
  }

  /// Raw texts of captured, not-yet-processed transaction notifications.
  Future<List<String>> getPending() async {
    if (!supported) return const [];
    final list = await _ch.invokeMethod<List<dynamic>>('getPending');
    return list?.cast<String>() ?? const [];
  }

  Future<void> remove(String text) async {
    if (supported) await _ch.invokeMethod<void>('removePending', {'text': text});
  }

  Future<void> clear() async {
    if (supported) await _ch.invokeMethod<void>('clearPending');
  }
}
