// lib/features/scan/ui/meal_analysis_page.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../data/meal_analysis_service.dart';
import '../data/simple_meal_analysis_service.dart';
import '../../analytics/data/analytics_service.dart';
import '../../services/image_service.dart';

class MealAnalysisPage extends StatefulWidget {
  final File photo;
  const MealAnalysisPage({super.key, required this.photo});

  @override
  State<MealAnalysisPage> createState() => _MealAnalysisPageState();
}

class _MealAnalysisPageState extends State<MealAnalysisPage> {
  late File _photo;
  bool _loading = false;
  String? _error;
  MealAnalysis? _mealAnalysis;

  @override
  void initState() {
    super.initState();
    _photo = widget.photo;
    _analyzeMeal();
  }

  Future<void> _analyzeMeal() async {
    setState(() {
      _loading = true;
      _error = null;
      _mealAnalysis = null;
    });

    try {
      print('Starting meal analysis...');
      // Use simple service for now to test basic functionality
      final analysis = await SimpleMealAnalysisService.instance.analyzeMeal(_photo);
      print('Meal analysis completed successfully');
      
      if (!mounted) return;
      
      setState(() {
        _mealAnalysis = analysis;
        _loading = false;
      });
    } catch (e) {
      print('Meal analysis failed: $e');
      if (!mounted) return;
      
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Meal Analysis'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _analyzeMeal,
            tooltip: 'Re-analyze',
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Analyzing meal...'),
                  SizedBox(height: 8),
                  Text('This may take a few seconds', style: TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                        const SizedBox(height: 16),
                        Text('Analysis Failed', style: theme.textTheme.headlineSmall),
                        const SizedBox(height: 8),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _analyzeMeal,
                          child: const Text('Try Again'),
                        ),
                      ],
                    ),
                  ),
                )
              : _mealAnalysis != null
                  ? _buildMealAnalysis(theme)
                  : const Center(child: Text('No analysis available')),
      floatingActionButton: _mealAnalysis != null 
          ? FloatingActionButton.extended(
              onPressed: _saveMealToFoodLog,
              icon: const Icon(Icons.save),
              label: const Text('Save Meal'),
              backgroundColor: Colors.green,
            )
          : null,
    );
  }

  Future<void> _saveMealToFoodLog() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _mealAnalysis == null) return;

    try {
      // Show loading state
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 16),
              Text('Saving meal and uploading image...'),
            ],
          ),
          duration: Duration(seconds: 5),
        ),
      );

      // Upload image first
      String? imageUrl;
      try {
        imageUrl = await ImageService.instance.uploadMealImage(_photo);
      } catch (e) {
        print('Image upload failed: $e');
        // Continue without image if upload fails
      }

      // Add image URL to meal data
      final mealData = _mealAnalysis!.toJson();
      if (imageUrl != null) {
        mealData['image_url'] = imageUrl;
      }

      await AnalyticsService.instance.saveMealToFoodLog(mealData, user.uid);
      
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(imageUrl != null 
              ? 'Meal and image saved successfully!' 
              : 'Meal saved successfully! (Image upload failed)'),
          backgroundColor: Colors.green,
        ),
      );
      
      // Navigate back to home
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save meal: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildMealAnalysis(ThemeData theme) {
    final analysis = _mealAnalysis!;
    
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Photo
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.file(_photo),
        ),
        const SizedBox(height: 16),

        // Total Nutrition Summary
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Total Nutrition', style: theme.textTheme.titleLarge),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _NutritionTile(
                        label: 'Calories',
                        value: analysis.totalCalories,
                        unit: 'kcal',
                        color: Colors.orange,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _NutritionTile(
                        label: 'Protein',
                        value: analysis.totalProtein,
                        unit: 'g',
                        color: Colors.blue,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _NutritionTile(
                        label: 'Carbs',
                        value: analysis.totalCarbs,
                        unit: 'g',
                        color: Colors.green,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _NutritionTile(
                        label: 'Fat',
                        value: analysis.totalFat,
                        unit: 'g',
                        color: Colors.red,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Ingredients Breakdown
        Text('Ingredients', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        ...analysis.ingredients.map((ingredient) => _buildIngredientCard(ingredient, theme)),
      ],
    );
  }

  Widget _buildIngredientCard(IngredientNutrition ingredient, ThemeData theme) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        title: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ingredient.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    ingredient.portionDesc,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '${ingredient.calories.toStringAsFixed(0)} kcal',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.orange,
              ),
            ),
          ],
        ),
        subtitle: Text('${ingredient.portionGrams.toStringAsFixed(0)}g'),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              children: [
                const Divider(),
                const SizedBox(height: 8),
                                 Row(
                   children: [
                     Expanded(
                       child: _MicroNutritionTile(
                         label: 'Protein',
                         value: ingredient.protein,
                         unit: 'g',
                         color: Colors.blue,
                       ),
                     ),
                     Expanded(
                       child: _MicroNutritionTile(
                         label: 'Carbs',
                         value: ingredient.carbs,
                         unit: 'g',
                         color: Colors.green,
                       ),
                     ),
                     Expanded(
                       child: _MicroNutritionTile(
                         label: 'Fat',
                         value: ingredient.fat,
                         unit: 'g',
                         color: Colors.red,
                       ),
                     ),
                   ],
                 ),
                 const SizedBox(height: 8),
                 Row(
                   children: [
                     Expanded(
                       child: _MicroNutritionTile(
                         label: 'Fiber',
                         value: ingredient.fiber,
                         unit: 'g',
                         color: Colors.brown,
                       ),
                     ),
                     Expanded(
                       child: _MicroNutritionTile(
                         label: 'Sugar',
                         value: ingredient.sugar,
                         unit: 'g',
                         color: Colors.pink,
                       ),
                     ),
                     Expanded(
                       child: _MicroNutritionTile(
                         label: 'Sodium',
                         value: ingredient.sodium,
                         unit: 'mg',
                         color: Colors.purple,
                       ),
                     ),
                   ],
                 ),
                if (ingredient.usdaName != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.green[200]!),
                    ),
                    child: Text(
                      'USDA: ${ingredient.usdaName}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.green[700],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NutritionTile extends StatelessWidget {
  final String label;
  final double value;
  final String unit;
  final Color color;

  const _NutritionTile({
    required this.label,
    required this.value,
    required this.unit,
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
            '${value.toStringAsFixed(0)} $unit',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _MicroNutritionTile extends StatelessWidget {
  final String label;
  final double value;
  final String unit;
  final Color color;

  const _MicroNutritionTile({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${value.toStringAsFixed(1)} $unit',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
