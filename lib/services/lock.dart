import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import 'settings.dart';

/// App lock using the phone's own biometrics / PIN / pattern.
class LockController extends ChangeNotifier with WidgetsBindingObserver {
  final Settings settings;
  final _auth = LocalAuthentication();
  bool locked;
  bool _busy = false;
  int _suspended = 0;

  LockController(this.settings) : locked = settings.lockEnabled {
    WidgetsBinding.instance.addObserver(this);
  }

  Future<bool> deviceSupported() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  Future<bool> unlock() async {
    if (_busy) return false;
    _busy = true;
    try {
      final ok = await _auth.authenticate(
        localizedReason: 'Unlock Silent Wallet',
        persistAcrossBackgrounding: true,
      );
      if (ok) {
        locked = false;
        notifyListeners();
      }
      return ok;
    } catch (_) {
      return false;
    } finally {
      _busy = false;
    }
  }

  /// Run [action] (e.g. camera / file picker) without re-locking when the
  /// app is sent to the background by that system screen.
  Future<T> suspendLock<T>(Future<T> Function() action) async {
    _suspended++;
    try {
      return await action();
    } finally {
      Future.delayed(const Duration(milliseconds: 800), () => _suspended--);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!settings.lockEnabled) return;
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      if (_suspended == 0 && !locked) {
        locked = true;
        notifyListeners();
      }
    }
  }

  void lockNow() {
    if (settings.lockEnabled) {
      locked = true;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
