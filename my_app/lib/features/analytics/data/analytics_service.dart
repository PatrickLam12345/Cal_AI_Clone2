// lib/features/analytics/data/analytics_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/timezone_service.dart';

class DailyNutrition {
  final DateTime date;
  final double calories;
  final double protein;
  final double carbs;
  final double fat;
  final int mealCount;

  DailyNutrition({
    required this.date,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.mealCount,
  });

  factory DailyNutrition.fromEntries(DateTime date, List<Map<String, dynamic>> entries) {
    double calories = 0;
    double protein = 0;
    double carbs = 0;
    double fat = 0;

    for (final entry in entries) {
      calories += (entry['kcal'] as num?)?.toDouble() ?? 0;
      protein += (entry['protein_g'] as num?)?.toDouble() ?? 0;
      carbs += (entry['carb_g'] as num?)?.toDouble() ?? 0;
      fat += (entry['fat_g'] as num?)?.toDouble() ?? 0;
    }

    return DailyNutrition(
      date: date,
      calories: calories,
      protein: protein,
      carbs: carbs,
      fat: fat,
      mealCount: entries.length,
    );
  }

  double get totalMacroGrams => protein + carbs + fat;

  double get proteinPercentage => totalMacroGrams > 0 ? (protein / totalMacroGrams) * 100 : 0;
  double get carbsPercentage => totalMacroGrams > 0 ? (carbs / totalMacroGrams) * 100 : 0;
  double get fatPercentage => totalMacroGrams > 0 ? (fat / totalMacroGrams) * 100 : 0;

  // Calorie distribution by macros
  double get proteinCalories => protein * 4;
  double get carbsCalories => carbs * 4;
  double get fatCalories => fat * 9;
  double get totalMacroCalories => proteinCalories + carbsCalories + fatCalories;

  double get proteinCaloriesPercentage => totalMacroCalories > 0 ? (proteinCalories / totalMacroCalories) * 100 : 0;
  double get carbsCaloriesPercentage => totalMacroCalories > 0 ? (carbsCalories / totalMacroCalories) * 100 : 0;
  double get fatCaloriesPercentage => totalMacroCalories > 0 ? (fatCalories / totalMacroCalories) * 100 : 0;
}

class WeeklyNutrition {
  final DateTime weekStart;
  final List<DailyNutrition> days;

  WeeklyNutrition({
    required this.weekStart,
    required this.days,
  });

  double get avgCalories => days.isEmpty ? 0 : days.map((d) => d.calories).reduce((a, b) => a + b) / days.length;
  double get avgProtein => days.isEmpty ? 0 : days.map((d) => d.protein).reduce((a, b) => a + b) / days.length;
  double get avgCarbs => days.isEmpty ? 0 : days.map((d) => d.carbs).reduce((a, b) => a + b) / days.length;
  double get avgFat => days.isEmpty ? 0 : days.map((d) => d.fat).reduce((a, b) => a + b) / days.length;
  
  double get totalCalories => days.map((d) => d.calories).fold(0, (a, b) => a + b);
  double get totalProtein => days.map((d) => d.protein).fold(0, (a, b) => a + b);
  double get totalCarbs => days.map((d) => d.carbs).fold(0, (a, b) => a + b);
  double get totalFat => days.map((d) => d.fat).fold(0, (a, b) => a + b);
}

class MacroTargets {
  final double calories;
  final double protein;
  final double carbs;
  final double fat;

  MacroTargets({
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
  });

  factory MacroTargets.fromUserProfile(Map<String, dynamic> data) {
    return MacroTargets(
      calories: (data['calories_override'] as num?)?.toDouble() ?? 2000,
      protein: (data['protein_g_override'] as num?)?.toDouble() ?? 150,
      carbs: (data['carb_g_override'] as num?)?.toDouble() ?? 200,
      fat: (data['fat_g_override'] as num?)?.toDouble() ?? 70,
    );
  }
}

class AnalyticsService {
  AnalyticsService._();
  static final instance = AnalyticsService._();

  final _firestore = FirebaseFirestore.instance;
  
  // OPTIMIZATION 3: Memory cache for recent data
  final Map<String, List<DailyNutrition>> _nutritionCache = {};
  final Map<String, DateTime> _cacheTimestamps = {};
  static const Duration _cacheExpiry = Duration(minutes: 5);

  String _formatDateKey(DateTime date) {
    return TimezoneService.instance.getDateKey(date);
  }

  Future<List<DailyNutrition>> getDailyNutrition({
    required String uid,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final todayKey = _formatDateKey(DateTime.now());
    final startDateKey = _formatDateKey(startDate);
    final endDateKey = _formatDateKey(endDate);

    final dailyNutrition = <DailyNutrition>[];

    // OPTIMIZATION 1: Single batch query for all summaries in date range
    final summariesQuery = await _firestore
        .collection('daily_nutrition_summaries')
        .where('uid', isEqualTo: uid)
        .where('date', isGreaterThanOrEqualTo: startDateKey)
        .where('date', isLessThanOrEqualTo: endDateKey)
        .get();

    // Create a map for fast lookup
    final summariesMap = <String, Map<String, dynamic>>{};
    for (final doc in summariesQuery.docs) {
      final data = doc.data();
      final date = data['date'] as String;
      summariesMap[date] = data;
    }

    // OPTIMIZATION 2: Single query for today's entries (if in range)
    Map<String, dynamic>? todayEntries;
    if (startDateKey.compareTo(todayKey) <= 0 && todayKey.compareTo(endDateKey) <= 0) {
      final todayQuery = await _firestore
          .collection('food_log_entries')
          .where('uid', isEqualTo: uid)
          .where('date', isEqualTo: todayKey)
          .get();

      if (todayQuery.docs.isNotEmpty) {
        final entries = todayQuery.docs.map((doc) => doc.data()).toList();
        todayEntries = {
          'entries': entries,
          'nutrition': DailyNutrition.fromEntries(DateTime.now(), entries)
        };
      }
    }

    // Build the results
    for (var date = startDate; date.isBefore(endDate.add(const Duration(days: 1))); date = date.add(const Duration(days: 1))) {
      final dateKey = _formatDateKey(date);
      
      if (dateKey == todayKey && todayEntries != null) {
        // Use today's detailed entries
        dailyNutrition.add(todayEntries['nutrition'] as DailyNutrition);
      } else if (summariesMap.containsKey(dateKey)) {
        // Use cached summary data
        final summary = summariesMap[dateKey]!;
        dailyNutrition.add(DailyNutrition(
          date: date,
          calories: (summary['total_calories'] as num?)?.toDouble() ?? 0,
          protein: (summary['total_protein_g'] as num?)?.toDouble() ?? 0,
          carbs: (summary['total_carb_g'] as num?)?.toDouble() ?? 0,
          fat: (summary['total_fat_g'] as num?)?.toDouble() ?? 0,
          mealCount: (summary['meal_count'] as num?)?.toInt() ?? 0,
        ));
      } else {
        // No data for this date
        dailyNutrition.add(DailyNutrition.fromEntries(date, []));
      }
    }

    return dailyNutrition;
  }

  Future<List<WeeklyNutrition>> getWeeklyNutrition({
    required String uid,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final dailyData = await getDailyNutrition(
      uid: uid,
      startDate: startDate,
      endDate: endDate,
    );

    final weeklyData = <WeeklyNutrition>[];
    var currentWeekStart = _getWeekStart(startDate);
    
    while (currentWeekStart.isBefore(endDate)) {
      final weekEnd = currentWeekStart.add(const Duration(days: 6));
      final weekDays = dailyData.where((day) =>
        !day.date.isBefore(currentWeekStart) && !day.date.isAfter(weekEnd)
      ).toList();
      
      weeklyData.add(WeeklyNutrition(
        weekStart: currentWeekStart,
        days: weekDays,
      ));
      
      currentWeekStart = currentWeekStart.add(const Duration(days: 7));
    }

    return weeklyData;
  }

  Future<MacroTargets> getUserMacroTargets(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    if (!doc.exists) {
      return MacroTargets(calories: 2000, protein: 150, carbs: 200, fat: 70);
    }
    return MacroTargets.fromUserProfile(doc.data()!);
  }

  Future<DailyNutrition> getTodayNutrition(String uid) async {
    final today = DateTime.now();
    final todayData = await getDailyNutrition(
      uid: uid,
      startDate: today,
      endDate: today,
    );
    return todayData.isNotEmpty ? todayData.first : DailyNutrition.fromEntries(today, []);
  }

  Future<List<DailyNutrition>> getLast7Days(String uid) async {
    final today = DateTime.now();
    final sevenDaysAgo = today.subtract(const Duration(days: 6));
    return getDailyNutrition(
      uid: uid,
      startDate: sevenDaysAgo,
      endDate: today,
    );
  }

  Future<List<DailyNutrition>> getLast30Days(String uid) async {
    final cacheKey = '${uid}_last30days';
    
    // Check cache first
    if (_nutritionCache.containsKey(cacheKey) && _cacheTimestamps.containsKey(cacheKey)) {
      final cacheAge = DateTime.now().difference(_cacheTimestamps[cacheKey]!);
      if (cacheAge < _cacheExpiry) {
        return _nutritionCache[cacheKey]!;
      }
    }
    
    // Cache miss or expired - fetch fresh data
    final today = DateTime.now();
    final thirtyDaysAgo = today.subtract(const Duration(days: 29));
    final result = await getDailyNutrition(
      uid: uid,
      startDate: thirtyDaysAgo,
      endDate: today,
    );
    
    // Update cache
    _nutritionCache[cacheKey] = result;
    _cacheTimestamps[cacheKey] = DateTime.now();
    
    return result;
  }

  DateTime _getWeekStart(DateTime date) {
    final daysFromMonday = date.weekday - 1;
    return DateTime(date.year, date.month, date.day).subtract(Duration(days: daysFromMonday));
  }

  // OPTIMIZATION 4: Cache management
  void clearCache() {
    _nutritionCache.clear();
    _cacheTimestamps.clear();
  }

  void clearUserCache(String uid) {
    final keysToRemove = _nutritionCache.keys.where((key) => key.startsWith(uid)).toList();
    for (final key in keysToRemove) {
      _nutritionCache.remove(key);
      _cacheTimestamps.remove(key);
    }
  }

  // Helper method to save analyzed meal to food log
  Future<void> saveMealToFoodLog(Map<String, dynamic> mealAnalysis, String uid) async {
    final now = DateTime.now();
    final todayKey = _formatDateKey(now);
    
    // Clean up old entries before adding new one
    await _cleanupOldEntries(uid, todayKey);

    // Determine the source and name based on the meal data
    String source = 'scan';
    String name = 'Scanned Meal';
    
    // Check if this is from manual food database search
    final ingredients = mealAnalysis['ingredients'] as List?;
    if (ingredients != null && ingredients.length == 1) {
      final ingredient = ingredients[0] as Map<String, dynamic>?;
      if (ingredient?['usda_name'] != null) {
        source = 'manual';
        name = ingredient!['name'] as String? ?? 'Manual Entry';
      }
    }

    final entryData = {
      'uid': uid,
      'date': todayKey,
      'name': name,
      'kcal': mealAnalysis['total_calories'] ?? 0,
      'protein_g': mealAnalysis['total_protein'] ?? 0,
      'carb_g': mealAnalysis['total_carbs'] ?? 0,
      'fat_g': mealAnalysis['total_fat'] ?? 0,
      'ingredients': mealAnalysis['ingredients'] ?? [],
      'created_at': now,
      'source': source,
    };

    // Add image URL if present
    if (mealAnalysis['image_url'] != null) {
      entryData['image_url'] = mealAnalysis['image_url'];
    }

    await _firestore.collection('food_log_entries').add(entryData);
    
    // OPTIMIZATION 5: Invalidate cache when new data is added
    clearUserCache(uid);
  }

  // Aggregate yesterday's data into daily summaries, then clean up old entries
  Future<void> _cleanupOldEntries(String uid, String todayKey) async {
    try {
      // First, aggregate any previous days that aren't summarized yet
      await _aggregatePreviousDays(uid, todayKey);
      
      // Then delete old detailed entries (keep only today)
      final oldEntriesQuery = await _firestore
          .collection('food_log_entries')
          .where('uid', isEqualTo: uid)
          .where('date', isLessThan: todayKey)
          .get();

      if (oldEntriesQuery.docs.isNotEmpty) {
        final batch = _firestore.batch();
        for (final doc in oldEntriesQuery.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
        print('Cleaned up ${oldEntriesQuery.docs.length} old food log entries');
      }
    } catch (e) {
      print('Error cleaning up old entries: $e');
      // Don't throw error - cleanup failure shouldn't block new entries
    }
  }

  // Aggregate previous days into daily summaries before deletion
  Future<void> _aggregatePreviousDays(String uid, String todayKey) async {
    try {
      // Get all entries older than today
      final oldEntriesQuery = await _firestore
          .collection('food_log_entries')
          .where('uid', isEqualTo: uid)
          .where('date', isLessThan: todayKey)
          .get();

      if (oldEntriesQuery.docs.isEmpty) return;

      // Group entries by date
      final entriesByDate = <String, List<Map<String, dynamic>>>{};
      for (final doc in oldEntriesQuery.docs) {
        final data = doc.data();
        final date = data['date'] as String;
        entriesByDate.putIfAbsent(date, () => []).add(data);
      }

      // Create daily summaries for each date
      final batch = _firestore.batch();
      for (final entry in entriesByDate.entries) {
        final dateKey = entry.key;
        final entries = entry.value;

        // Check if summary already exists
        final existingSummary = await _firestore
            .collection('daily_nutrition_summaries')
            .where('uid', isEqualTo: uid)
            .where('date', isEqualTo: dateKey)
            .limit(1)
            .get();

        if (existingSummary.docs.isNotEmpty) continue; // Skip if already summarized

        // Calculate daily totals
        double totalCalories = 0;
        double totalProtein = 0;
        double totalCarbs = 0;
        double totalFat = 0;
        int mealCount = entries.length;

        for (final entry in entries) {
          totalCalories += (entry['kcal'] as num?)?.toDouble() ?? 0;
          totalProtein += (entry['protein_g'] as num?)?.toDouble() ?? 0;
          totalCarbs += (entry['carb_g'] as num?)?.toDouble() ?? 0;
          totalFat += (entry['fat_g'] as num?)?.toDouble() ?? 0;
        }

        // Create summary document
        final summaryRef = _firestore.collection('daily_nutrition_summaries').doc();
        batch.set(summaryRef, {
          'uid': uid,
          'date': dateKey,
          'total_calories': totalCalories,
          'total_protein_g': totalProtein,
          'total_carb_g': totalCarbs,
          'total_fat_g': totalFat,
          'meal_count': mealCount,
          'created_at': DateTime.now(),
        });
      }

      if (entriesByDate.isNotEmpty) {
        await batch.commit();
        print('Created ${entriesByDate.length} daily nutrition summaries');
      }
    } catch (e) {
      print('Error aggregating previous days: $e');
      // Don't throw error - this shouldn't block cleanup
    }
  }

  // Public method to manually trigger cleanup (can be called on app start)
  Future<void> cleanupOldFoodLogEntries(String uid) async {
    final todayKey = _formatDateKey(DateTime.now());
    await _cleanupOldEntries(uid, todayKey);
  }

  // Method to manually aggregate a specific day (useful for testing or backfilling)
  Future<void> aggregateDay(String uid, String dateKey) async {
    try {
      // Check if summary already exists
      final existingSummary = await _firestore
          .collection('daily_nutrition_summaries')
          .where('uid', isEqualTo: uid)
          .where('date', isEqualTo: dateKey)
          .limit(1)
          .get();

      if (existingSummary.docs.isNotEmpty) {
        print('Summary for $dateKey already exists');
        return;
      }

      // Get entries for this specific date
      final entriesQuery = await _firestore
          .collection('food_log_entries')
          .where('uid', isEqualTo: uid)
          .where('date', isEqualTo: dateKey)
          .get();

      if (entriesQuery.docs.isEmpty) {
        print('No entries found for $dateKey');
        return;
      }

      // Calculate daily totals
      double totalCalories = 0;
      double totalProtein = 0;
      double totalCarbs = 0;
      double totalFat = 0;
      int mealCount = entriesQuery.docs.length;

      for (final doc in entriesQuery.docs) {
        final entry = doc.data();
        totalCalories += (entry['kcal'] as num?)?.toDouble() ?? 0;
        totalProtein += (entry['protein_g'] as num?)?.toDouble() ?? 0;
        totalCarbs += (entry['carb_g'] as num?)?.toDouble() ?? 0;
        totalFat += (entry['fat_g'] as num?)?.toDouble() ?? 0;
      }

      // Create summary document
      await _firestore.collection('daily_nutrition_summaries').add({
        'uid': uid,
        'date': dateKey,
        'total_calories': totalCalories,
        'total_protein_g': totalProtein,
        'total_carb_g': totalCarbs,
        'total_fat_g': totalFat,
        'meal_count': mealCount,
        'created_at': DateTime.now(),
      });

      print('Created summary for $dateKey: ${totalCalories.toStringAsFixed(0)} kcal');
    } catch (e) {
      print('Error aggregating day $dateKey: $e');
    }
  }
}
