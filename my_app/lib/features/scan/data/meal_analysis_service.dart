// lib/features/scan/data/meal_analysis_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

import '../../services/api_base.dart';
import '../../services/scan_api.dart';
import '../../services/usda_api.dart';

class IngredientNutrition {
  final String name;
  final String portionDesc;
  final double portionGrams;
  final double calories;
  final double protein;
  final double carbs;
  final double fat;
  final double fiber;
  final double sugar;
  final double sodium;
  final String? usdaName; // actual USDA database name

  IngredientNutrition({
    required this.name,
    required this.portionDesc,
    required this.portionGrams,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.fiber,
    required this.sugar,
    required this.sodium,
    this.usdaName,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'portion_desc': portionDesc,
    'portion_grams': portionGrams,
    'calories': calories,
    'protein': protein,
    'carbs': carbs,
    'fat': fat,
    'fiber': fiber,
    'sugar': sugar,
    'sodium': sodium,
    'usda_name': usdaName,
  };
}

class MealAnalysis {
  final List<IngredientNutrition> ingredients;
  final double totalCalories;
  final double totalProtein;
  final double totalCarbs;
  final double totalFat;
  final double totalFiber;
  final double totalSugar;
  final double totalSodium;

  MealAnalysis({required this.ingredients})
      : totalCalories = ingredients.fold(0, (sum, i) => sum + i.calories),
        totalProtein = ingredients.fold(0, (sum, i) => sum + i.protein),
        totalCarbs = ingredients.fold(0, (sum, i) => sum + i.carbs),
        totalFat = ingredients.fold(0, (sum, i) => sum + i.fat),
        totalFiber = ingredients.fold(0, (sum, i) => sum + i.fiber),
        totalSugar = ingredients.fold(0, (sum, i) => sum + i.sugar),
        totalSodium = ingredients.fold(0, (sum, i) => sum + i.sodium);

  Map<String, dynamic> toJson() => {
    'ingredients': ingredients.map((i) => i.toJson()).toList(),
    'total_calories': totalCalories,
    'total_protein': totalProtein,
    'total_carbs': totalCarbs,
    'total_fat': totalFat,
    'total_fiber': totalFiber,
    'total_sugar': totalSugar,
    'total_sodium': totalSodium,
  };
}

class MealAnalysisService {
  MealAnalysisService._();
  static final instance = MealAnalysisService._();

  final _scanApi = const ScanApi();
  final _usdaApi = const UsdaApi();

  Future<MealAnalysis> analyzeMeal(File photo) async {
    try {
      // Add overall timeout for the entire analysis
      return await Future.any([
        _performAnalysis(photo),
        Future.delayed(const Duration(seconds: 15), () => throw Exception('Analysis timed out after 15 seconds')),
      ]);
    } catch (e) {
      throw Exception('Meal analysis failed: $e');
    }
  }

  Future<MealAnalysis> _performAnalysis(File photo) async {
    // 1. Detect ingredients from photo
    final detectedItems = await _scanApi.analyzePhoto(photo);
    if (detectedItems.isEmpty) {
      throw Exception('No ingredients detected in the photo');
    }

    // 2. Get nutritional data for each ingredient (with timeout per ingredient)
    final ingredients = <IngredientNutrition>[];
    
    for (final item in detectedItems) {
      final name = item['name'] as String? ?? 'Unknown';
      final portionDesc = item['portion_desc'] as String? ?? '';
      final portionGrams = (item['portion_grams'] as num?)?.toDouble() ?? 0.0;

      try {
        // Add timeout for each ingredient lookup
        final ingredient = await Future.any([
          _lookupIngredientNutrition(name, portionDesc, portionGrams),
          Future.delayed(const Duration(seconds: 5), () => _createEstimatedNutrition(name, portionDesc, portionGrams)),
        ]);
        ingredients.add(ingredient);
      } catch (e) {
        // If USDA lookup fails, use estimated nutrition
        ingredients.add(_createEstimatedNutrition(name, portionDesc, portionGrams));
      }
    }

    return MealAnalysis(ingredients: ingredients);
  }

  Future<IngredientNutrition> _lookupIngredientNutrition(String name, String portionDesc, double portionGrams) async {
    try {
      // Search USDA database for this ingredient
      final usdaResults = await _usdaApi.search(name, page: 1);
      if (usdaResults.foods.isNotEmpty) {
        // Get the first (most relevant) result
        final usdaFood = usdaResults.foods.first;
        final usdaId = usdaFood['fdcId'] as int?;
        
        if (usdaId != null) {
          // Get detailed nutrition data
          final detail = await _usdaApi.detail(usdaId);
          final nutrients = await _usdaApi.normalize(detail);
          
          // Extract nutrition values
          final nutrition = _extractNutritionFromNutrients(nutrients, portionGrams);
          
          return IngredientNutrition(
            name: name,
            portionDesc: portionDesc,
            portionGrams: portionGrams,
            calories: nutrition['calories'] ?? 0,
            protein: nutrition['protein'] ?? 0,
            carbs: nutrition['carbs'] ?? 0,
            fat: nutrition['fat'] ?? 0,
            fiber: nutrition['fiber'] ?? 0,
            sugar: nutrition['sugar'] ?? 0,
            sodium: nutrition['sodium'] ?? 0,
            usdaName: usdaFood['name'] as String?,
          );
        }
      }
      
      // Fallback with estimated nutrition
      return _createEstimatedNutrition(name, portionDesc, portionGrams);
    } catch (e) {
      // If USDA lookup fails, use estimated nutrition
      return _createEstimatedNutrition(name, portionDesc, portionGrams);
    }
  }

  Map<String, double> _extractNutritionFromNutrients(List<Map<String, dynamic>> nutrients, double portionGrams) {
    final result = <String, double>{};
    
    for (final nutrient in nutrients) {
      final name = (nutrient['name'] as String? ?? '').toLowerCase();
      final value = (nutrient['value'] as num?)?.toDouble() ?? 0.0;
      final unit = (nutrient['unit'] as String? ?? '').toLowerCase();
      
      // Convert to per-portion values (assuming nutrients are per 100g)
      final portionValue = (value * portionGrams) / 100.0;
      
      if (name.contains('energy') || name.contains('calories')) {
        result['calories'] = portionValue;
      } else if (name.contains('protein')) {
        result['protein'] = portionValue;
      } else if (name.contains('carbohydrate') || name.contains('carb')) {
        result['carbs'] = portionValue;
      } else if (name.contains('lipid') || name.contains('fat')) {
        result['fat'] = portionValue;
      } else if (name.contains('fiber')) {
        result['fiber'] = portionValue;
      } else if (name.contains('sugar')) {
        result['sugar'] = portionValue;
      } else if (name.contains('sodium')) {
        result['sodium'] = portionValue;
      }
    }
    
    return result;
  }

  IngredientNutrition _createEstimatedNutrition(String name, String portionDesc, double portionGrams) {
    // Simple estimation based on common food types
    final nameLower = name.toLowerCase();
    double calories = 0, protein = 0, carbs = 0, fat = 0, fiber = 0, sugar = 0, sodium = 0;
    
    if (nameLower.contains('chicken') || nameLower.contains('meat') || nameLower.contains('beef')) {
      calories = portionGrams * 1.65; // ~165 kcal per 100g
      protein = portionGrams * 0.31; // ~31g protein per 100g
      fat = portionGrams * 0.037; // ~3.7g fat per 100g
    } else if (nameLower.contains('rice') || nameLower.contains('pasta') || nameLower.contains('bread')) {
      calories = portionGrams * 1.3; // ~130 kcal per 100g
      carbs = portionGrams * 0.28; // ~28g carbs per 100g
      protein = portionGrams * 0.025; // ~2.5g protein per 100g
    } else if (nameLower.contains('vegetable') || nameLower.contains('broccoli') || nameLower.contains('carrot')) {
      calories = portionGrams * 0.25; // ~25 kcal per 100g
      carbs = portionGrams * 0.05; // ~5g carbs per 100g
      fiber = portionGrams * 0.025; // ~2.5g fiber per 100g
    } else if (nameLower.contains('oil') || nameLower.contains('butter')) {
      calories = portionGrams * 9.0; // ~900 kcal per 100g
      fat = portionGrams * 1.0; // ~100g fat per 100g
    } else {
      // Generic fallback
      calories = portionGrams * 1.0; // ~100 kcal per 100g
      carbs = portionGrams * 0.15; // ~15g carbs per 100g
      protein = portionGrams * 0.05; // ~5g protein per 100g
      fat = portionGrams * 0.05; // ~5g fat per 100g
    }
    
    return IngredientNutrition(
      name: name,
      portionDesc: portionDesc,
      portionGrams: portionGrams,
      calories: calories,
      protein: protein,
      carbs: carbs,
      fat: fat,
      fiber: fiber,
      sugar: sugar,
      sodium: sodium,
    );
  }
}
