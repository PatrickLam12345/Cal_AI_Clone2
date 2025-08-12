import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:pati/features/home/ui/home.dart';
import 'package:pati/features/analytics/ui/analytics.dart';
import 'package:pati/features/settings/ui/settings.dart';
import 'package:pati/features/food_database/ui/food_database_page.dart';

import '../../scan/ui/meal_analysis_page.dart';

class MainNavPage extends StatefulWidget {
  const MainNavPage({super.key});

  @override
  State<MainNavPage> createState() => _MainNavPageState();
}

class _MainNavPageState extends State<MainNavPage> {
  int _selectedIndex = 0;

  final List<Widget> _pages = const [
    HomePage(),
    AnalyticsPage(),
    SettingsPage(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  void _onFabPressed() {
    _showQuickActionsSheet(context);
  }

  Future<void> _onAnalyzeMeal(BuildContext context) async {
    final picker = ImagePicker();
    final shot = await picker.pickImage(source: ImageSource.camera);
    if (shot == null) return;

    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MealAnalysisPage(photo: File(shot.path)),
      ),
    );

// If the review screen asks for a retake, open camera again
    if (result == 'retake') {
      final shot2 = await picker.pickImage(source: ImageSource.camera);
      if (shot2 == null) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MealAnalysisPage(photo: File(shot2.path)),
        ),
      );
    }
  }

  void _onFoodDatabase(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const FoodDatabasePage()),
    );
  }

  void _showQuickActionsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final color = Theme.of(ctx).colorScheme;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Row(
            children: [
              Expanded(
                child: _ActionCard(
                  icon: Icons.camera_alt_rounded,
                  label: 'Analyze Meal',
                  color: color.primary,
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _onAnalyzeMeal(context);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ActionCard(
                  icon: Icons.menu_book_rounded,
                  label: 'Food Database',
                  color: color.secondary,
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _onFoodDatabase(context);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_selectedIndex],
      floatingActionButton: FloatingActionButton(
        onPressed: _onFabPressed,
        child: const Icon(Icons.add),
      ),
      floatingActionButtonLocation:
          FloatingActionButtonLocation.endFloat, // bottom-right
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart),
            label: 'Analytics',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest.withOpacity(0.6),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 28, color: color),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
