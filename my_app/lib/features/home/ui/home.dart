import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../analytics/data/analytics_service.dart';
import '../../services/timezone_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  void initState() {
    super.initState();
    _performDailyCleanup();
  }

  Future<void> _performDailyCleanup() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      // Clean up old entries when home page loads (start of new day)
      await AnalyticsService.instance.cleanupOldFoodLogEntries(uid);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(
        body: Center(child: Text('Not signed in')),
      );
    }

    final docRef = FirebaseFirestore.instance.collection('users').doc(uid);

    return Scaffold(
      appBar: AppBar(title: const Text('Pati')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: docRef.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snap.hasData || !snap.data!.exists) {
            return const Center(
              child: Text('Please complete your profile to see targets.'),
            );
          }

          final data = snap.data!.data()!;
          final plan = _computePlanFromProfile(data);
          final units = (data['units'] as String?)?.toLowerCase() ?? 'metric';

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildProgressSection(plan, uid),
                const SizedBox(height: 24),
                _buildRecentMealsSection(uid, units),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildRecentMealsSection(String uid, String units) {
    final todayKey = TimezoneService.instance.getTodayKey();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Today\'s Meals',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Text(TimezoneService.instance.formatDate(DateTime.now()),
                style: const TextStyle(color: Colors.grey)),
          ],
        ),
        const SizedBox(height: 12),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('food_log_entries')
              .where('uid', isEqualTo: uid)
              .where('date', isEqualTo: todayKey)
              .orderBy('created_at', descending: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                ),
              );
            }

            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return Card(
                child: SizedBox(
                  width: double.infinity, // forces same width as parent
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.restaurant,
                            size: 48, color: Colors.grey[400]),
                        const SizedBox(height: 8),
                        const Text('No meals logged today'),
                        const SizedBox(height: 4),
                        Text(
                          'Scan a meal or search the food database!',
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[600]),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            final meals = snapshot.data!.docs;
            double totalCalories = 0;
            double totalProtein = 0;
            double totalCarbs = 0;
            double totalFat = 0;

            for (final meal in meals) {
              final data = meal.data();
              totalCalories += (data['kcal'] as num?)?.toDouble() ?? 0;
              totalProtein += (data['protein_g'] as num?)?.toDouble() ?? 0;
              totalCarbs += (data['carb_g'] as num?)?.toDouble() ?? 0;
              totalFat += (data['fat_g'] as num?)?.toDouble() ?? 0;
            }

            return Column(
              children: [
                // Daily totals card
                Card(
                  color: Colors.blue[50],
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Today\'s Total',
                                style: TextStyle(fontWeight: FontWeight.w600)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                children: [
                                  Text('${totalCalories.toStringAsFixed(0)}',
                                      style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.orange)),
                                  const Text('kcal',
                                      style: TextStyle(fontSize: 12)),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Column(
                                children: [
                                  Text('${totalProtein.toStringAsFixed(0)}g',
                                      style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.blue)),
                                  const Text('protein',
                                      style: TextStyle(fontSize: 10)),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Column(
                                children: [
                                  Text('${totalCarbs.toStringAsFixed(0)}g',
                                      style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.green)),
                                  const Text('carbs',
                                      style: TextStyle(fontSize: 10)),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Column(
                                children: [
                                  Text('${totalFat.toStringAsFixed(0)}g',
                                      style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.red)),
                                  const Text('fat',
                                      style: TextStyle(fontSize: 10)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // Individual meals
                ...meals
                    .map((meal) => _buildMealCard(meal.data(), units))
                    .toList(),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildMealCard(Map<String, dynamic> mealData, String units) {
    final name = mealData['name'] as String? ?? 'Meal';
    final calories = (mealData['kcal'] as num?)?.toDouble() ?? 0;
    final protein = (mealData['protein_g'] as num?)?.toDouble() ?? 0;
    final carbs = (mealData['carb_g'] as num?)?.toDouble() ?? 0;
    final fat = (mealData['fat_g'] as num?)?.toDouble() ?? 0;
    final createdAt = mealData['created_at'] as Timestamp?;
    final source = mealData['source'] as String? ?? 'manual';
    final imageUrl = mealData['image_url'] as String?;

    String timeText = 'Unknown time';
    if (createdAt != null) {
      timeText =
          TimezoneService.instance.formatTime(createdAt.toDate(), units: units);
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Meal image or icon
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: Colors.grey[200],
              ),
              child: imageUrl != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Icon(
                            source == 'scan' ? Icons.camera_alt : Icons.search,
                            color: Colors.grey[400],
                            size: 24,
                          );
                        },
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                value: loadingProgress.expectedTotalBytes !=
                                        null
                                    ? loadingProgress.cumulativeBytesLoaded /
                                        loadingProgress.expectedTotalBytes!
                                    : null,
                              ),
                            ),
                          );
                        },
                      ),
                    )
                  : Icon(
                      source == 'scan' ? Icons.camera_alt : Icons.search,
                      size: 24,
                      color: source == 'scan' ? Colors.green : Colors.blue,
                    ),
            ),
            const SizedBox(width: 12),

            // Meal details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Text(
                        timeText,
                        style:
                            const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        '${calories.toStringAsFixed(0)} kcal',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, color: Colors.orange),
                      ),
                      const SizedBox(width: 12),
                      Text('P: ${protein.toStringAsFixed(0)}g',
                          style: const TextStyle(fontSize: 11)),
                      const SizedBox(width: 6),
                      Text('C: ${carbs.toStringAsFixed(0)}g',
                          style: const TextStyle(fontSize: 11)),
                      const SizedBox(width: 6),
                      Text('F: ${fat.toStringAsFixed(0)}g',
                          style: const TextStyle(fontSize: 11)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressSection(_MacroPlan plan, String uid) {
    final todayKey = TimezoneService.instance.getTodayKey();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Today\'s Progress',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Text(TimezoneService.instance.formatDate(DateTime.now()),
                style: const TextStyle(color: Colors.grey)),
          ],
        ),
        const SizedBox(height: 16),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('food_log_entries')
              .where('uid', isEqualTo: uid)
              .where('date', isEqualTo: todayKey)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                ),
              );
            }

            // Calculate consumed totals
            double consumedCalories = 0;
            double consumedProtein = 0;
            double consumedCarbs = 0;
            double consumedFat = 0;

            if (snapshot.hasData) {
              for (final doc in snapshot.data!.docs) {
                final data = doc.data();
                consumedCalories += (data['kcal'] as num?)?.toDouble() ?? 0;
                consumedProtein += (data['protein_g'] as num?)?.toDouble() ?? 0;
                consumedCarbs += (data['carb_g'] as num?)?.toDouble() ?? 0;
                consumedFat += (data['fat_g'] as num?)?.toDouble() ?? 0;
              }
            }

            return Card(
              color: Colors.blue[50],
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildProgressItem(
                      'Calories',
                      consumedCalories,
                      plan.calories.toDouble(),
                      'kcal',
                      Colors.orange,
                    ),
                    const SizedBox(height: 16),
                    _buildProgressItem(
                      'Protein',
                      consumedProtein,
                      plan.proteinG.toDouble(),
                      'g',
                      Colors.blue,
                    ),
                    const SizedBox(height: 16),
                    _buildProgressItem(
                      'Carbs',
                      consumedCarbs,
                      plan.carbsG.toDouble(),
                      'g',
                      Colors.green,
                    ),
                    const SizedBox(height: 16),
                    _buildProgressItem(
                      'Fat',
                      consumedFat,
                      plan.fatG.toDouble(),
                      'g',
                      Colors.red,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildProgressItem(
      String label, double consumed, double target, String unit, Color color) {
    final percentage = target > 0 ? (consumed / target).clamp(0.0, 1.0) : 0.0;
    final remaining = (target - consumed).clamp(0.0, double.infinity);
    final isOverTarget = consumed > target;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            RichText(
              text: TextSpan(
                style: const TextStyle(color: Colors.black),
                children: [
                  TextSpan(
                    text: '${consumed.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isOverTarget ? Colors.red : color,
                    ),
                  ),
                  TextSpan(text: ' / ${target.toStringAsFixed(0)} $unit'),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: percentage,
          backgroundColor: Colors.grey[300],
          valueColor: AlwaysStoppedAnimation<Color>(
            isOverTarget ? Colors.red : color,
          ),
          minHeight: 8,
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${(percentage * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                fontSize: 12,
                color: isOverTarget ? Colors.red : Colors.grey[600],
              ),
            ),
            Text(
              isOverTarget
                  ? '+${(consumed - target).toStringAsFixed(0)} $unit over'
                  : '${remaining.toStringAsFixed(0)} $unit remaining',
              style: TextStyle(
                fontSize: 12,
                color: isOverTarget ? Colors.red : Colors.grey[600],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MacroPlan {
  final int calories;
  final int proteinG;
  final int carbsG;
  final int fatG;
  final int age;
  final double heightCm;
  final double weightKg;
  final String activityLabel;

  _MacroPlan({
    required this.calories,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.age,
    required this.heightCm,
    required this.weightKg,
    required this.activityLabel,
  });
}

_MacroPlan _computePlanFromProfile(Map<String, dynamic> data) {
  final String sex = (data['sex'] as String? ?? 'male').toLowerCase();
  final int age = (data['age'] as num?)?.toInt() ?? 25;
  final double heightCm = (data['height_cm'] as num?)?.toDouble() ?? 175;
  final double weightKg = (data['weight_kg'] as num?)?.toDouble() ?? 70;
  final String activity =
      (data['activity'] as String? ?? 'moderate').toLowerCase();
  final String goal = (data['goal'] as String? ?? 'maintain').toLowerCase();
  final double rateKgPerWeek =
      (data['rate_kg_per_week'] as num?)?.toDouble() ?? 0.0;
  final double? proteinOverrideGPerKg =
      (data['protein_g_per_kg'] as num?)?.toDouble();
  final double? fatPercentOverride = (data['fat_percent'] as num?)?.toDouble();
  // New explicit goal fields (preferred if present)
  final double? caloriesOverride =
      (data['calories_override'] as num?)?.toDouble();
  final double? proteinGOverride =
      (data['protein_g_override'] as num?)?.toDouble();
  final double? carbGOverride = (data['carb_g_override'] as num?)?.toDouble();
  final double? fatGOverride = (data['fat_g_override'] as num?)?.toDouble();

  if (caloriesOverride != null &&
      proteinGOverride != null &&
      carbGOverride != null &&
      fatGOverride != null) {
    return _MacroPlan(
      calories: caloriesOverride.round(),
      proteinG: proteinGOverride.round(),
      carbsG: carbGOverride.round(),
      fatG: fatGOverride.round(),
      age: age,
      heightCm: heightCm,
      weightKg: weightKg,
      activityLabel: {
            'sedentary': 'Sedentary',
            'light': 'Lightly active',
            'moderate': 'Moderately active',
            'active': 'Active',
            'veryactive': 'Very active',
          }[activity.replaceAll(' ', '')] ??
          'Moderately active',
    );
  }

  // Mifflin-St Jeor BMR
  double base = 10 * weightKg + 6.25 * heightCm - 5 * age;
  double sexAdj = 0;
  if (sex == 'male') sexAdj = 5;
  if (sex == 'female') sexAdj = -161;
  if (sex == 'other') sexAdj = (-161 + 5) / 2; // gender-neutral midpoint
  final double bmr = base + sexAdj;

  // Activity factor
  final Map<String, double> activityFactor = {
    'sedentary': 1.2,
    'light': 1.375,
    'moderate': 1.55,
    'active': 1.725,
    'veryactive': 1.9,
    'very_active': 1.9,
    'very active': 1.9,
  };
  final double af = activityFactor[activity.replaceAll(' ', '')] ?? 1.55;
  final double tdee = bmr * af;

  // Calorie delta from chosen weekly rate (approx 7700 kcal per kg)
  final double dailyDelta = rateKgPerWeek * (7700 / 7);
  double targetCalories = tdee + dailyDelta;

  // No artificial limits on calculated calories

  // Protein (g/kg): allow override; otherwise adjust by goal
  double proteinPerKg = proteinOverrideGPerKg ??
      (() {
        if (goal == 'lose') return 2.2;
        if (goal == 'gain') return 1.6;
        return 1.8;
      })();
  final double proteinG = (proteinPerKg * weightKg);

  // Fat: % of calories (default 25%), min ~0.5 g/kg
  final double fatPercent = (fatPercentOverride ?? 25).clamp(15, 40);
  double fatCalories = targetCalories * (fatPercent / 100.0);
  double fatG = fatCalories / 9.0;
  final double minFatG = weightKg * 0.5;
  if (fatG < minFatG) {
    fatG = minFatG;
    fatCalories = fatG * 9.0;
  }

  // Carbs: remainder of calories
  final double remainingCalories =
      targetCalories - (proteinG * 4) - fatCalories;
  final double carbsG = remainingCalories > 0 ? (remainingCalories / 4.0) : 0;

  // Rounded values
  final int kcalRounded = targetCalories.round();
  final int proteinRounded = proteinG.round();
  final int fatRounded = fatG.round();
  final int carbsRounded = carbsG.round();

  // Human-friendly activity label
  final Map<String, String> activityLabel = {
    'sedentary': 'Sedentary',
    'light': 'Lightly active',
    'moderate': 'Moderately active',
    'active': 'Active',
    'veryactive': 'Very active',
  };

  return _MacroPlan(
    calories: kcalRounded,
    proteinG: proteinRounded,
    carbsG: carbsRounded,
    fatG: fatRounded,
    age: age,
    heightCm: heightCm,
    weightKg: weightKg,
    activityLabel:
        activityLabel[activity.replaceAll(' ', '')] ?? 'Moderately active',
  );
}
