// lib/features/services/api_base.dart
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';

/// 🔧 Change these for your environment
const String _lanIp = '192.168.0.123';

// Your dev machine's LAN IP
const int _port = 3000;
const String _prodUrl = 'https://api.myapp.com'; // Your live API endpoint

/// Get the correct API base URL depending on environment
Future<String> apiBaseUrl() async {
  // Release mode → always production
  if (kReleaseMode) {
    return _prodUrl;
  }

  // Web always hits localhost:port in dev
  if (kIsWeb) {
    return 'http://localhost:$_port';
  }

  // Platform-specific handling
  if (Platform.isAndroid) {
    final emu = await _isEmulator();
    return emu ? 'http://10.0.2.2:$_port' : 'http://$_lanIp:$_port';
  }

  if (Platform.isIOS) {
    final emu = await _isEmulator();
    return emu ? 'http://localhost:$_port' : 'http://$_lanIp:$_port';
  }

  // macOS / Windows / Linux in dev
  return 'http://localhost:$_port';
}

/// Check if running on emulator/simulator
Future<bool> _isEmulator() async {
  final info = DeviceInfoPlugin();
  try {
    if (Platform.isAndroid) {
      final a = await info.androidInfo;
      return !(a.isPhysicalDevice ?? true);
    }
    if (Platform.isIOS) {
      final i = await info.iosInfo;
      return !(i.isPhysicalDevice ?? true);
    }
    return false;
  } catch (_) {
    return false; // Default to "not emulator" if detection fails
  }
}
