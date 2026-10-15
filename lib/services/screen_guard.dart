import 'package:flutter/services.dart';

/// Turns Android's "secure window" on or off. Secure (the default) blocks
/// screenshots and screen recording and hides the app in the recent-apps list.
class ScreenGuard {
  static const _channel = MethodChannel(
    'com.offlineexpensemgr.silentwallet/window',
  );

  static Future<void> setSecure(bool secure) async {
    try {
      await _channel.invokeMethod<void>('setSecure', secure);
    } catch (_) {
      // No native side (tests, other platforms): nothing to do.
    }
  }
}
