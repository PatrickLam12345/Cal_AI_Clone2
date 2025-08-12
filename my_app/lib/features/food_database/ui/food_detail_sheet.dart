import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/usda_api.dart';
import '../../analytics/data/analytics_service.dart';

class FoodDetailSheet extends StatefulWidget {
  final int fdcId;
  const FoodDetailSheet({super.key, required this.fdcId});

  @override
  State<FoodDetailSheet> createState() => _FoodDetailSheetState();
}

class _FoodDetailSheetState extends State<FoodDetailSheet> {
  final _api = UsdaApi();

  Map<String, dynamic>? _detail;
  List<Map<String, dynamic>> _nutrients = [];
  bool _loading = true;
  String? _error;

  // Gram-based scaling
  double _grams = 100.0;       // user-selected grams
  double _baseGrams = 100.0;   // per-amount basis (serving grams or 100 g)
  String _baseLabel = '100 g';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final d = await _api.detail(widget.fdcId);
      final ns = await _api.normalize(d);

      final inferred = _inferBaseFromDetail(d);
      if (!mounted) return;
      setState(() {
        _detail = d;
        _nutrients = ns;
        _baseGrams = inferred.baseGrams;
        _grams = inferred.baseGrams;
        _baseLabel = inferred.baseLabel;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---- nutrient helpers ----
  double _getVal(String name) {
    final m = _nutrients.firstWhere(
      (n) => (n['name'] as String?) == name,
      orElse: () => const {'value': 0.0},
    );
    final v = m['value'];
    return (v is num) ? v.toDouble() : 0.0;
  }

  String _getUnit(String name) {
    final m = _nutrients.firstWhere(
      (n) => (n['name'] as String?) == name,
      orElse: () => const {'unit': ''},
    );
    final u = m['unit'];
    return (u is String) ? u : '';
  }

  // If Energy missing, compute kcal per base using Atwater (4/9/4/7)
  // and Protein fallback from Nitrogen×6.25.
  ({double kcal, bool computed}) _energyKcalPerBase() {
    final direct = _getVal('Energy'); // expected kcal from normalize
    if (direct > 0) return (kcal: direct, computed: false);

    double protein = _getVal('Protein');
    if (protein <= 0) {
      final nitrogen = _getVal('Nitrogen');
      if (nitrogen > 0) protein = nitrogen * 6.25;
    }
    final fat   = _getVal('Total lipid (fat)');
    final carbs = _getVal('Carbohydrate, by difference');
    final alcohol = _getVal('Alcohol, ethyl'); // may not exist; fine if 0

    final haveAny = (protein > 0) || (fat > 0) || (carbs > 0) || (alcohol > 0);
    if (!haveAny) return (kcal: 0, computed: false);

    final kcal = (protein * 4) + (fat * 9) + (carbs * 4) + (alcohol * 7);
    return (kcal: kcal, computed: true);
  }

  // Scale per-base value by selected grams
  double _scale(double perBase) {
    if (_baseGrams <= 0) return perBase;
    return perBase * (_grams / _baseGrams);
  }

  Future<void> _addToFoodLog() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to add food to log')),
      );
      return;
    }

    if (_detail == null) return;

    final energyInfo = _energyKcalPerBase();
    final protein = _getVal('Protein');
    final carbs = _getVal('Carbohydrate, by difference');
    final fat = _getVal('Total lipid (fat)');

    // Create a meal analysis-like structure for the food log
    final mealData = {
      'total_calories': _scale(energyInfo.kcal),
      'total_protein': _scale(protein),
      'total_carbs': _scale(carbs),
      'total_fat': _scale(fat),
      'ingredients': [
        {
          'name': _detail!['description']?.toString() ?? 'Food Item',
          'portion_desc': '${_grams.toStringAsFixed(0)} g',
          'portion_grams': _grams,
          'calories': _scale(energyInfo.kcal),
          'protein': _scale(protein),
          'carbs': _scale(carbs),
          'fat': _scale(fat),
          'usda_name': _detail!['description']?.toString(),
        }
      ],
    };

    try {
      await AnalyticsService.instance.saveMealToFoodLog(mealData, user.uid);
      
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added ${_detail!['description'] ?? 'food'} to food log!'),
          backgroundColor: Colors.green,
        ),
      );
      
      // Close the bottom sheet
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to add to food log: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(height: 260, child: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return SizedBox(height: 260, child: Center(child: Text(_error!)));
    }

    final energyInfo = _energyKcalPerBase();      // kcal per base
    final protein = _getVal('Protein');           // g per base
    final carbs   = _getVal('Carbohydrate, by difference');
    final fat     = _getVal('Total lipid (fat)');

    const otherNames = <String>[
      'Fatty acids, total saturated',
      'Fatty acids, total trans',
      'Cholesterol',
      'Sodium, Na',
      'Fiber, total dietary',
      'Sugars, total',
      'Added sugars',
      'Vitamin D',
      'Calcium, Ca',
      'Iron, Fe',
      'Potassium, K',
    ];

    return DraggableScrollableSheet(
      expand: false,
      builder: (context, controller) {
        return SingleChildScrollView(
          controller: controller,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text((_detail?['description'] ?? '').toString(),
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),

              Text('Base data per: $_baseLabel',
                  style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 8),

              _GramSelector(
                grams: _grams,
                onChanged: (g) => setState(() => _grams = g),
              ),

              const SizedBox(height: 12),
              Text('Macros (${_grams.toStringAsFixed(0)} g)',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),

              _MacroRow(
                label: energyInfo.computed ? 'Calories (computed)' : 'Calories',
                value: _scale(energyInfo.kcal),
                unit: 'kcal',
                precision: 0,
              ),
              _MacroRow(label: 'Protein', value: _scale(protein), unit: 'g'),
              _MacroRow(label: 'Carbs',   value: _scale(carbs),   unit: 'g'),
              _MacroRow(label: 'Fat',     value: _scale(fat),     unit: 'g'),

              const SizedBox(height: 12),
              Divider(color: Theme.of(context).dividerColor),
              const SizedBox(height: 6),

              Text('Other Nutrition Facts (${_grams.toStringAsFixed(0)} g)',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),

              ..._buildOther(otherNames),
              
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _addToFoodLog,
                  icon: const Icon(Icons.add),
                  label: const Text('Add to Food Log'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildOther(List<String> names) {
    final items = <Widget>[];
    for (final name in names) {
      final v = _getVal(name);
      if (v <= 0) continue;
      final unit = _getUnit(name);
      final scaled = _scale(v);
      final isIntUnit = unit == 'kcal' || unit == 'mg';
      final valueStr = isIntUnit ? scaled.toStringAsFixed(0) : scaled.toStringAsFixed(1);
      items.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text(name)),
              Text('$valueStr ${unit.isNotEmpty ? unit : ''}'),
            ],
          ),
        ),
      );
    }
    if (items.isEmpty) {
      return [const Text('No additional label nutrients available.')];
    }
    return items;
  }

  // ---- base inference ----
  _BaseInference _inferBaseFromDetail(Map<String, dynamic> d) {
    final dataType = (d['dataType'] ?? '').toString().toLowerCase();

    // 1) Serving explicitly in grams
    final servingSize = d['servingSize'];
    final servingUnit = (d['servingSizeUnit'] ?? '').toString().toLowerCase();
    if (servingSize is num && servingSize > 0 && servingUnit == 'g') {
      final g = servingSize.toDouble();
      return _BaseInference(g, '${_fmtNum(g)} g');
    }

    // 2) First foodPortions gramWeight
    final fps = d['foodPortions'];
    if (fps is List && fps.isNotEmpty) {
      final first = fps.first;
      final gw = (first is Map && first['gramWeight'] is num)
          ? (first['gramWeight'] as num).toDouble()
          : null;
      if (gw != null && gw > 0) {
        return _BaseInference(gw, '${_fmtNum(gw)} g');
      }
    }

    // 3) Non-branded → assume per 100 g
    if (dataType != 'branded') return const _BaseInference(100.0, '100 g');

    // 4) Fallback
    return const _BaseInference(100.0, '100 g');
  }

  String _fmtNum(num n) => n % 1 == 0 ? n.toStringAsFixed(0) : n.toStringAsFixed(1);
}

class _BaseInference {
  final double baseGrams;
  final String baseLabel;
  const _BaseInference(this.baseGrams, this.baseLabel);
}

class _GramSelector extends StatefulWidget {
  final double grams;
  final ValueChanged<double> onChanged;
  const _GramSelector({required this.grams, required this.onChanged});

  @override
  State<_GramSelector> createState() => _GramSelectorState();
}

class _GramSelectorState extends State<_GramSelector> {
  late final TextEditingController _c;

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: widget.grams.toStringAsFixed(0));
  }

  @override
  void didUpdateWidget(covariant _GramSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.grams != widget.grams) {
      _c.text = widget.grams.toStringAsFixed(0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _set(double v) {
    final clamped = v.isFinite ? v.clamp(0, 100000).toDouble() : 0.0;
    widget.onChanged(clamped);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          tooltip: '-10 g',
          icon: const Icon(Icons.remove),
          onPressed: () {
            final g = (double.tryParse(_c.text) ?? widget.grams) - 10;
            _c.text = g.toStringAsFixed(0);
            _set(g);
          },
        ),
        SizedBox(
          width: 110,
          child: TextField(
            controller: _c,
            keyboardType: const TextInputType.numberWithOptions(decimal: false, signed: false),
            decoration: const InputDecoration(
              labelText: 'Grams',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onSubmitted: (s) => _set(double.tryParse(s) ?? widget.grams),
            onChanged: (s) {
              final v = double.tryParse(s);
              if (v != null) _set(v);
            },
          ),
        ),
        IconButton(
          tooltip: '+10 g',
          icon: const Icon(Icons.add),
          onPressed: () {
            final g = (double.tryParse(_c.text) ?? widget.grams) + 10;
            _c.text = g.toStringAsFixed(0);
            _set(g);
          },
        ),
      ],
    );
  }
}

class _MacroRow extends StatelessWidget {
  final String label;
  final double value;
  final String unit;
  final int precision;

  const _MacroRow({
    required this.label,
    required this.value,
    required this.unit,
    this.precision = 1,
  });

  @override
  Widget build(BuildContext context) {
    final txt = (unit == 'kcal') ? value.toStringAsFixed(0) : value.toStringAsFixed(precision);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyLarge),
          Text('$txt $unit', style: Theme.of(context).textTheme.bodyLarge),
        ],
      ),
    );
  }
}
