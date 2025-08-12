// lib/features/services/timezone_service.dart
import 'package:intl/intl.dart';

class TimezoneService {
  TimezoneService._();
  static final instance = TimezoneService._();

  /// Get today's date key in user's local timezone
  /// This ensures "today" is consistent across the app
  String getTodayKey() {
    final now = DateTime.now(); // User's local time
    return DateFormat('yyyy-MM-dd').format(now);
  }

  /// Get a date key for any DateTime in user's local timezone
  String getDateKey(DateTime date) {
    return DateFormat('yyyy-MM-dd').format(date);
  }

  /// Get user's timezone offset in minutes from UTC
  int getTimezoneOffsetMinutes() {
    return DateTime.now().timeZoneOffset.inMinutes;
  }

  /// Get user's timezone offset as a readable string (e.g., "UTC-5")
  String getTimezoneOffsetString() {
    final offsetMinutes = getTimezoneOffsetMinutes();
    final offsetHours = offsetMinutes / 60;
    final sign = offsetHours >= 0 ? '+' : '';
    return 'UTC$sign${offsetHours.toStringAsFixed(offsetHours % 1 == 0 ? 0 : 1)}';
  }

  /// Check if two DateTime objects are on the same day in user's timezone
  bool isSameDay(DateTime date1, DateTime date2) {
    return getDateKey(date1) == getDateKey(date2);
  }

  /// Get start of day (00:00:00) for a given date in user's timezone
  DateTime getStartOfDay(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  /// Get end of day (23:59:59.999) for a given date in user's timezone
  DateTime getEndOfDay(DateTime date) {
    return DateTime(date.year, date.month, date.day, 23, 59, 59, 999);
  }

  /// Format time for display
  /// - Metric users: 24-hour format (e.g., "14:30")
  /// - Imperial users: 12-hour format (e.g., "2:30 PM")
  String formatTime(DateTime dateTime, {String? units}) {
    if (units?.toLowerCase() == 'imperial') {
      return DateFormat('h:mm a').format(dateTime);
    } else {
      return DateFormat('HH:mm').format(dateTime);
    }
  }

  /// Format date for display (e.g., "Aug 10")
  String formatDate(DateTime dateTime) {
    return DateFormat('MMM d').format(dateTime);
  }

  /// Format full date for display (e.g., "Monday, Aug 10")
  String formatFullDate(DateTime dateTime) {
    return DateFormat('EEEE, MMM d').format(dateTime);
  }
}
