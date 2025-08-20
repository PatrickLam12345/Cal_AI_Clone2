import 'package:flutter/material.dart';

class IngredientBreakdownSheet extends StatelessWidget {
  final Map<String, dynamic> mealData;

  const IngredientBreakdownSheet({
    super.key,
    required this.mealData,
  });

  @override
  Widget build(BuildContext context) {
    final ingredients = (mealData['ingredients'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final mealName = mealData['name'] as String? ?? 'Meal';
    final imageUrl = mealData['image_url'] as String?;
    
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Expanded(
                child: Text(
                  'Ingredient Breakdown',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 8),
          
          // Meal info card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  // Image or icon
                  Container(
                    width: 50,
                    height: 50,
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
                                  Icons.restaurant,
                                  color: Colors.grey[400],
                                  size: 20,
                                );
                              },
                            ),
                          )
                        : Icon(
                            Icons.restaurant,
                            color: Colors.grey[400],
                            size: 20,
                          ),
                  ),
                  const SizedBox(width: 12),
                  
                  // Meal summary
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          mealName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              '${(mealData['kcal'] as num?)?.toStringAsFixed(0) ?? '0'} kcal',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.orange,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'P: ${(mealData['protein_g'] as num?)?.toStringAsFixed(0) ?? '0'}g',
                              style: const TextStyle(fontSize: 11),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'C: ${(mealData['carb_g'] as num?)?.toStringAsFixed(0) ?? '0'}g',
                              style: const TextStyle(fontSize: 11),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'F: ${(mealData['fat_g'] as num?)?.toStringAsFixed(0) ?? '0'}g',
                              style: const TextStyle(fontSize: 11),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          
          // Ingredients list
          if (ingredients.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: Text(
                    'No ingredient breakdown available for this meal.',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ),
            )
          else ...[
            Text(
              'Ingredients (${ingredients.length})',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: ingredients.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final ingredient = ingredients[index];
                  return _buildIngredientCard(ingredient);
                },
              ),
            ),
          ],
          
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildIngredientCard(Map<String, dynamic> ingredient) {
    final name = ingredient['name'] as String? ?? 'Unknown';
    final portionDesc = ingredient['portion_desc'] as String? ?? '';
    final calories = (ingredient['calories'] as num?)?.toDouble() ?? 0;
    final protein = (ingredient['protein'] as num?)?.toDouble() ?? 0;
    final carbs = (ingredient['carbs'] as num?)?.toDouble() ?? 0;
    final fat = (ingredient['fat'] as num?)?.toDouble() ?? 0;
    final usdaName = ingredient['usda_name'] as String?;
    
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Ingredient name and portion
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      if (portionDesc.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          portionDesc,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                      if (usdaName != null && usdaName != name) ...[
                        const SizedBox(height: 2),
                        Text(
                          'USDA: $usdaName',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey[500],
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Text(
                  '${calories.toStringAsFixed(0)} kcal',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.orange,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            
            // Macronutrients
            Row(
              children: [
                Expanded(
                  child: _buildNutrientInfo('Protein', protein, Colors.blue),
                ),
                Expanded(
                  child: _buildNutrientInfo('Carbs', carbs, Colors.green),
                ),
                Expanded(
                  child: _buildNutrientInfo('Fat', fat, Colors.red),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNutrientInfo(String label, double value, Color color) {
    return Column(
      children: [
        Text(
          '${value.toStringAsFixed(1)}g',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: color,
            fontSize: 13,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }
}

// Helper function to show the ingredient breakdown
void showIngredientBreakdown(BuildContext context, Map<String, dynamic> mealData) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      child: IngredientBreakdownSheet(mealData: mealData),
    ),
  );
}
