import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'enhanced_analytics.dart';

class AnalyticsPage extends StatelessWidget {
  const AnalyticsPage({super.key});

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
      appBar: AppBar(
        title: const Text('Analytics'),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: docRef.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snap.hasData || !snap.data!.exists) {
            return const Center(
              child: Text('Please complete your profile to see analytics.'),
            );
          }

          final data = snap.data!.data()!;
          final analytics = _AnalyticsData.fromProfile(data);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildWeightProgressSection(analytics, context),
              const SizedBox(height: 16),
              _buildBMISection(analytics, context),
              const SizedBox(height: 24),
              const Divider(thickness: 2),
              const SizedBox(height: 8),
              Text('Nutrition Analytics', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 16),
              Container(
                height: 400, // Compressed height for the macro analytics
                child: const EnhancedAnalyticsPage(),
              ),
            ],
          );
        },
      ),
    );
  }

    Widget _buildWeightProgressSection(_AnalyticsData analytics, BuildContext context) {
    final theme = Theme.of(context);
    final isImperial = analytics.units == 'imperial';
    final weightUnit = isImperial ? 'lbs' : 'kg';
    final currentWeight = isImperial ? analytics.currentWeightKg * 2.2046226218 : analytics.currentWeightKg;
    final targetWeight = isImperial ? analytics.targetWeightKg * 2.2046226218 : analytics.targetWeightKg;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Weight Progress', style: theme.textTheme.titleLarge),
                TextButton.icon(
                  onPressed: () => _showWeightAdjustDialog(context, analytics),
                  icon: const Icon(Icons.edit, size: 16),
                  label: const Text('Adjust'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Current and Target Weight Labels
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Current', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                    Text('${currentWeight.toStringAsFixed(1)} $weightUnit', 
                         style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Target', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                    Text('${targetWeight.toStringAsFixed(1)} $weightUnit', 
                         style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
            
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _showWeightAdjustDialog(BuildContext context, _AnalyticsData analytics) {
    final isImperial = analytics.units == 'imperial';
    final weightUnit = isImperial ? 'lbs' : 'kg';
    
    // Convert to display units
    final currentWeight = isImperial ? analytics.currentWeightKg * 2.2046226218 : analytics.currentWeightKg;
    final targetWeight = isImperial ? analytics.targetWeightKg * 2.2046226218 : analytics.targetWeightKg;
    
    final currentController = TextEditingController(text: currentWeight.toStringAsFixed(1));
    final targetController = TextEditingController(text: targetWeight.toStringAsFixed(1));
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Adjust Weight'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: currentController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Current Weight ($weightUnit)',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: targetController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Target Weight ($weightUnit)',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => _updateWeights(
              context,
              currentController.text,
              targetController.text,
              isImperial,
            ),
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  Future<void> _updateWeights(
    BuildContext context,
    String currentText,
    String targetText,
    bool isImperial,
  ) async {
    try {
      final currentInput = double.parse(currentText);
      final targetInput = double.parse(targetText);
      
      if (currentInput <= 0 || targetInput <= 0) {
        throw Exception('Weight must be greater than 0');
      }
      
      // Convert to kg if imperial
      final currentWeightKg = isImperial ? currentInput / 2.2046226218 : currentInput;
      final targetWeightKg = isImperial ? targetInput / 2.2046226218 : targetInput;
      
      // Auto-sync goal based on current vs target weight relationship
      String goal;
      final diff = targetWeightKg - currentWeightKg;
      if (diff.abs() < 1e-6) {
        goal = 'maintain';
      } else if (diff > 0) {
        goal = 'gain';
      } else {
        goal = 'lose';
      }
      
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      
      // Update in Firestore (including auto-synced goal)
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'weight_kg': currentWeightKg,
        'target_weight_kg': targetWeightKg,
        'goal': goal, // Auto-synced goal based on weight relationship
      });
      
      Navigator.of(context).pop();
      
      // Show success message with auto-synced goal
      final goalText = goal == 'maintain' ? 'Maintain weight' : 
                      goal == 'gain' ? 'Gain weight' : 'Lose weight';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Weight updated successfully!\nGoal set to: $goalText'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      // Show error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildBMISection(_AnalyticsData analytics, BuildContext context) {
    final theme = Theme.of(context);
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('BMI Analysis', style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Current BMI', style: TextStyle(fontSize: 14, color: Colors.grey[600])),
                      const SizedBox(height: 4),
                      Text(
                        analytics.currentBMI.toStringAsFixed(1),
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: analytics.bmiColor,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Category', style: TextStyle(fontSize: 14, color: Colors.grey[600])),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: analytics.bmiColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: analytics.bmiColor),
                        ),
                        child: Text(
                          analytics.bmiCategory,
                          style: TextStyle(
                            color: analytics.bmiColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildBMIScale(analytics, context),
          ],
        ),
      ),
    );
  }

  Widget _buildBMIScale(_AnalyticsData analytics, BuildContext context) {
    final bmiRanges = [
      {'min': 0, 'max': 18.5, 'label': 'Underweight', 'color': Colors.blue},
      {'min': 18.5, 'max': 25, 'label': 'Healthy', 'color': Colors.green},
      {'min': 25, 'max': 30, 'label': 'Overweight', 'color': Colors.orange},
      {'min': 30, 'max': 40, 'label': 'Obese', 'color': Colors.red},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('BMI Scale', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final scaleWidth = constraints.maxWidth;
            final bmiPosition = _getBMIPosition(analytics.currentBMI, scaleWidth);
            
            return Container(
              height: 24,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: const LinearGradient(
                  colors: [Colors.blue, Colors.green, Colors.orange, Colors.red],
                  stops: [0.0, 0.25, 0.5, 1.0],
                ),
              ),
              child: Stack(
                children: [
                  // BMI range labels - positioned using the same calculation as the indicator
                  Positioned(
                    left: (_getBMIPosition(18.5, scaleWidth) - 10).clamp(0.0, scaleWidth - 20),
                    top: 2,
                    child: Text('18.5', style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                  Positioned(
                    left: (_getBMIPosition(25.0, scaleWidth) - 8).clamp(0.0, scaleWidth - 16),
                    top: 2,
                    child: Text('25', style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                  Positioned(
                    left: (_getBMIPosition(30.0, scaleWidth) - 8).clamp(0.0, scaleWidth - 16),
                    top: 2,
                    child: Text('30', style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                  // Current BMI indicator
                  Positioned(
                    left: (bmiPosition - 6).clamp(0.0, scaleWidth - 12), // Ensure indicator stays within bounds
                    top: 0,
                    child: Container(
                      width: 12,
                      height: 24,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.black, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: bmiRanges.map((range) {
            return Expanded(
              child: Column(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: range['color'] as Color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    range['label'] as String,
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  double _getBMIPosition(double bmi, double scaleWidth) {
    // Convert BMI to position on scale (0-100% of width)
    double percentage = 0.0;
    
    // Clamp BMI to reasonable range for visualization
    final clampedBMI = bmi.clamp(10.0, 45.0);
    
    // Calculate position as percentage (0.0 to 1.0)
    if (clampedBMI < 18.5) {
      // Underweight range: 0% to 25% of scale
      percentage = (clampedBMI / 18.5) * 0.25;
    } else if (clampedBMI < 25) {
      // Healthy range: 25% to 50% of scale
      percentage = 0.25 + ((clampedBMI - 18.5) / 6.5) * 0.25;
    } else if (clampedBMI < 30) {
      // Overweight range: 50% to 75% of scale
      percentage = 0.5 + ((clampedBMI - 25) / 5.0) * 0.25;
    } else {
      // Obese range: 75% to 100% of scale
      percentage = 0.75 + ((clampedBMI - 30) / 15.0) * 0.25; // Extended range for obese
    }
    
    // Convert percentage to pixel position
    return percentage * scaleWidth;
  }
}

class _AnalyticsData {
  final double currentWeightKg;
  final double targetWeightKg;
  final double heightCm;
  final int age;
  final String goal;
  final String activityLabel;
  final String units;
  final double currentBMI;
  final double targetBMI;
  final double weightDifferenceKg;
  final String weightDifferenceText;
  final double weightProgress;
  final Color bmiColor;
  final String bmiCategory;
  final double minWeight;
  final double maxWeight;

  _AnalyticsData({
    required this.currentWeightKg,
    required this.targetWeightKg,
    required this.heightCm,
    required this.age,
    required this.goal,
    required this.activityLabel,
    required this.units,
    required this.currentBMI,
    required this.targetBMI,
    required this.weightDifferenceKg,
    required this.weightDifferenceText,
    required this.weightProgress,
    required this.bmiColor,
    required this.bmiCategory,
    required this.minWeight,
    required this.maxWeight,
  });

  factory _AnalyticsData.fromProfile(Map<String, dynamic> data) {
    final double currentWeightKg = (data['weight_kg'] as num?)?.toDouble() ?? 70;
    final double heightCm = (data['height_cm'] as num?)?.toDouble() ?? 175;
    final int age = (data['age'] as num?)?.toInt() ?? 25;
    final String units = (data['units'] as String?)?.toLowerCase() ?? 'metric';
    final String goal = (data['goal'] as String? ?? 'maintain').toLowerCase();
    final String activity = (data['activity'] as String? ?? 'moderate').toLowerCase();
    
    // Prefer explicit target from Firestore; fall back to computed per goal
    double targetWeightKg = (data['target_weight_kg'] as num?)?.toDouble() ?? 0.0;
    if (targetWeightKg <= 0) {
      targetWeightKg = currentWeightKg;
      if (goal == 'lose') {
        targetWeightKg = currentWeightKg * 0.9; // default: lose 10%
      } else if (goal == 'gain') {
        targetWeightKg = currentWeightKg * 1.1; // default: gain 10%
      }
    }

    // Calculate BMI
    final double currentBMI = currentWeightKg / ((heightCm / 100) * (heightCm / 100));
    final double targetBMI = targetWeightKg / ((heightCm / 100) * (heightCm / 100));

    // Weight difference
    final double weightDifferenceKg = targetWeightKg - currentWeightKg;
    final String weightDifferenceText = weightDifferenceKg >= 0
        ? '${weightDifferenceKg.toStringAsFixed(1)} kg to gain'
        : '${weightDifferenceKg.abs().toStringAsFixed(1)} kg to lose';

    // Progress calculations
    final double weightProgress = goal == 'maintain'
        ? 1.0
        : (goal == 'lose'
            ? (currentWeightKg - targetWeightKg) / (currentWeightKg * 0.1)
            : (targetWeightKg - currentWeightKg) / (currentWeightKg * 0.1));

    // BMI category and color
    String bmiCategory;
    Color bmiColor;
    if (currentBMI < 18.5) {
      bmiCategory = 'Underweight';
      bmiColor = Colors.blue;
    } else if (currentBMI < 25) {
      bmiCategory = 'Healthy';
      bmiColor = Colors.green;
    } else if (currentBMI < 30) {
      bmiCategory = 'Overweight';
      bmiColor = Colors.orange;
    } else {
      bmiCategory = 'Obese';
      bmiColor = Colors.red;
    }

    // Weight range for progress bar
    final double minWeight = 40.0;
    final double maxWeight = 150.0;

    // Activity label
    final String activityLabel = {
      'sedentary': 'Sedentary',
      'light': 'Lightly active',
      'moderate': 'Moderately active',
      'active': 'Active',
      'veryactive': 'Very active',
    }[activity.replaceAll(' ', '')] ?? 'Moderately active';

    return _AnalyticsData(
      currentWeightKg: currentWeightKg,
      targetWeightKg: targetWeightKg,
      heightCm: heightCm,
      age: age,
      goal: goal,
      activityLabel: activityLabel,
      units: units,
      currentBMI: currentBMI,
      targetBMI: targetBMI,
      weightDifferenceKg: weightDifferenceKg,
      weightDifferenceText: weightDifferenceText,
      weightProgress: weightProgress.clamp(0.0, 1.0),
      bmiColor: bmiColor,
      bmiCategory: bmiCategory,
      minWeight: minWeight,
      maxWeight: maxWeight,
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: color,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${substring(1)}";
  }
}
