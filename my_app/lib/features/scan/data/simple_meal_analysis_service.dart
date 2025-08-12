// lib/features/scan/data/simple_meal_analysis_service.dart
import 'dart:io';
import 'meal_analysis_service.dart';
import '../../services/scan_api.dart';

class SimpleMealAnalysisService {
  SimpleMealAnalysisService._();
  static final instance = SimpleMealAnalysisService._();

  Future<MealAnalysis> analyzeMeal(File photo) async {
    try {
      // Use the existing scan API to detect ingredients
      final scanApi = const ScanApi();
      final detectedItems = await scanApi.analyzePhoto(photo);
      
      if (detectedItems.isEmpty) {
        throw Exception('No ingredients detected in the photo');
      }

      // Convert to IngredientNutrition with estimated values
      final ingredients = detectedItems.map((item) {
        final name = item['name'] as String? ?? 'Unknown';
        final portionDesc = item['portion_desc'] as String? ?? '';
        final portionGrams = (item['portion_grams'] as num?)?.toDouble() ?? 0.0;

        return _createEstimatedNutrition(name, portionDesc, portionGrams);
      }).toList();

      return MealAnalysis(ingredients: ingredients);
    } catch (e) {
      throw Exception('Simple meal analysis failed: $e');
    }
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
