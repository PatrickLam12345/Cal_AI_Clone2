// lib/features/analytics/ui/enhanced_analytics.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../data/analytics_service.dart';

class EnhancedAnalyticsPage extends StatefulWidget {
  const EnhancedAnalyticsPage({super.key});

  @override
  State<EnhancedAnalyticsPage> createState() => _EnhancedAnalyticsPageState();
}

class _EnhancedAnalyticsPageState extends State<EnhancedAnalyticsPage> {
  String? _uid;
  List<DailyNutrition> _dailyData = [];
  bool _loading = true;
  String? _error;
  int _startIndex = 0; // For scrolling through weeks

  @override
  void initState() {
    super.initState();
    _uid = FirebaseAuth.instance.currentUser?.uid;
    _loadData();
  }

  Future<void> _loadData() async {
    if (_uid == null) return;

    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final last30Days = await AnalyticsService.instance.getLast30Days(_uid!);

      if (!mounted) return;
      setState(() {
        _dailyData = last30Days;
        _loading = false;
        // Start at the most recent week
        _startIndex = _dailyData.length > 7 ? _dailyData.length - 7 : 0;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_uid == null) {
      return const Center(child: Text('Not signed in'));
    }

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Error: $_error'),
            ElevatedButton(
              onPressed: _loadData,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_dailyData.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bar_chart, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('No nutrition data available'),
            Text('Start logging meals to see your analytics!', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    // Get current week data (7 days starting from _startIndex)
    final currentWeekData = _getCurrentWeekData();
    final canGoBack = _startIndex > 0;
    final canGoForward = _startIndex + 7 < _dailyData.length;

    return Column(
      children: [
        // Week navigation header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: canGoBack ? _goToPreviousWeek : null,
                icon: const Icon(Icons.chevron_left),
                tooltip: 'Previous week',
              ),
              Text(
                _getWeekRangeText(currentWeekData),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              IconButton(
                onPressed: canGoForward ? _goToNextWeek : null,
                icon: const Icon(Icons.chevron_right),
                tooltip: 'Next week',
              ),
            ],
          ),
        ),
        // Bar chart
        SizedBox(
          height: 260,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: _buildMacroBarChart(currentWeekData),
          ),
        ),
      ],
    );
  }

  // Helper methods for the simple bar chart view
  List<DailyNutrition> _getCurrentWeekData() {
    final endIndex = (_startIndex + 7).clamp(0, _dailyData.length);
    return _dailyData.sublist(_startIndex, endIndex);
  }

  void _goToPreviousWeek() {
    setState(() {
      _startIndex = (_startIndex - 7).clamp(0, _dailyData.length - 7);
    });
  }

  void _goToNextWeek() {
    setState(() {
      _startIndex = (_startIndex + 7).clamp(0, _dailyData.length - 7);
    });
  }

  String _getWeekRangeText(List<DailyNutrition> weekData) {
    if (weekData.isEmpty) return 'No data';
    if (weekData.length == 1) {
      return DateFormat('MMM d, yyyy').format(weekData.first.date);
    }
    return '${DateFormat('MMM d').format(weekData.first.date)} - ${DateFormat('MMM d, yyyy').format(weekData.last.date)}';
  }

  double _calculateNiceMaxY(double maxCalories) {
    // Nice intervals: 2500, 3000, 3500, 4000, 4500, 5000, etc.
    if (maxCalories <= 2500) return 2500;
    if (maxCalories <= 3000) return 3000;
    if (maxCalories <= 3500) return 3500;
    if (maxCalories <= 4000) return 4000;
    if (maxCalories <= 4500) return 4500;
    if (maxCalories <= 5000) return 5000;
    if (maxCalories <= 5500) return 5500;
    if (maxCalories <= 6000) return 6000;
    
    // For higher values, round up to nearest 1000
    return ((maxCalories / 1000).ceil() * 1000).toDouble();
  }

  Widget _buildMacroBarChart(List<DailyNutrition> weekData) {
    if (weekData.isEmpty) {
      return const Center(
        child: Text('No data for this week', style: TextStyle(color: Colors.grey)),
      );
    }

    // Calculate max calories for scaling with nice intervals
    final maxCalories = weekData.map((d) => d.calories).fold(0.0, (a, b) => a > b ? a : b);
    final chartMaxY = _calculateNiceMaxY(maxCalories);

    return Column(
      children: [
        // Legend
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildLegendItem('Protein', Colors.blue),
            const SizedBox(width: 20),
            _buildLegendItem('Carbs', Colors.green),
            const SizedBox(width: 20),
            _buildLegendItem('Fat', Colors.red),
          ],
        ),
        const SizedBox(height: 12),
        // Chart
        Expanded(
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: chartMaxY,
              gridData: FlGridData(
                show: true,
                horizontalInterval: 500, // Grid lines every 500 calories
                verticalInterval: 1,
                getDrawingHorizontalLine: (value) {
                  return FlLine(
                    color: Colors.grey[300]!,
                    strokeWidth: 1,
                  );
                },
                getDrawingVerticalLine: (value) {
                  return FlLine(
                    color: Colors.grey[200]!,
                    strokeWidth: 0.5,
                  );
                },
              ),
              barTouchData: BarTouchData(
                enabled: true,
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    if (groupIndex >= weekData.length) return null;
                    final day = weekData[groupIndex];
                    final dayName = DateFormat('E MMM d').format(day.date);
                    
                    if (rodIndex == 0) {
                      return BarTooltipItem(
                        '$dayName\n'
                        '${day.calories.toStringAsFixed(0)} kcal\n'
                        'P: ${day.protein.toStringAsFixed(0)}g\n'
                        'C: ${day.carbs.toStringAsFixed(0)}g\n'
                        'F: ${day.fat.toStringAsFixed(0)}g',
                        const TextStyle(color: Colors.white, fontSize: 12),
                      );
                    }
                    return null;
                  },
                ),
              ),
              titlesData: FlTitlesData(
                show: true,
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      final index = value.toInt();
                      if (index >= 0 && index < weekData.length) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            DateFormat('E\nM/d').format(weekData[index].date),
                            style: const TextStyle(fontSize: 10),
                            textAlign: TextAlign.center,
                          ),
                        );
                      }
                      return const Text('');
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 50,
                    interval: 500, // Show every 500 calories
                    getTitlesWidget: (value, meta) {
                      // Only show nice round numbers (multiples of 500)
                      if (value % 500 == 0) {
                        return Text(
                          '${value.toInt()}',
                          style: const TextStyle(fontSize: 10),
                        );
                      }
                      return const Text('');
                    },
                  ),
                ),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(
                show: true,
                border: Border.all(color: Colors.grey[300]!),
              ),
              barGroups: weekData.asMap().entries.map((entry) {
                final index = entry.key;
                final day = entry.value;
                
                // Calculate macro contributions to total calories
                final proteinCals = day.protein * 4; // 4 calories per gram
                final carbsCals = day.carbs * 4;     // 4 calories per gram  
                final fatCals = day.fat * 9;         // 9 calories per gram
                
                return BarChartGroupData(
                  x: index,
                  barRods: [
                    BarChartRodData(
                      toY: day.calories,
                      color: Colors.transparent, // Invisible rod for total height
                      width: 30,
                      rodStackItems: [
                        BarChartRodStackItem(0, proteinCals, Colors.blue),
                        BarChartRodStackItem(proteinCals, proteinCals + carbsCals, Colors.green),
                        BarChartRodStackItem(proteinCals + carbsCals, proteinCals + carbsCals + fatCals, Colors.red),
                      ],
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
      ],
    );
  }
}
