import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/timezone_service.dart';
import 'ingredient_breakdown_sheet.dart';

class FoodLogPage extends StatelessWidget {
  const FoodLogPage({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final todayKey = TimezoneService.instance.getTodayKey();

    final query = FirebaseFirestore.instance
        .collection('food_log_entries')
        .where('uid', isEqualTo: uid)
        .where('date', isEqualTo: todayKey)
        .orderBy('created_at');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Food Log'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: query.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(child: Text("No entries yet. Tap + to add your first."));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final d = docs[i].data();
              final name = d['name'] as String? ?? 'Food';
              final kcal = (d['kcal'] as num?)?.toDouble() ?? 0;
              final p = (d['protein_g'] as num?)?.toDouble() ?? 0;
              final c = (d['carb_g'] as num?)?.toDouble() ?? 0;
              final f = (d['fat_g'] as num?)?.toDouble() ?? 0;
              final source = d['source'] as String? ?? 'manual';
              final imageUrl = d['image_url'] as String?;
              
              return ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    color: Colors.grey[200],
                  ),
                  child: imageUrl != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Icon(
                                source == 'scan' ? Icons.camera_alt : Icons.search,
                                color: Colors.grey[400],
                                size: 16,
                              );
                            },
                          ),
                        )
                      : Icon(
                          source == 'scan' ? Icons.camera_alt : Icons.search,
                          size: 16,
                          color: source == 'scan' ? Colors.green : Colors.blue,
                        ),
                ),
                title: Text(name),
                subtitle: RichText(
                  text: TextSpan(
                    style: DefaultTextStyle.of(context).style,
                    children: [
                      TextSpan(
                        text: 'P ${p.toStringAsFixed(0)}g',
                        style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.w500),
                      ),
                      const TextSpan(text: ' · '),
                      TextSpan(
                        text: 'C ${c.toStringAsFixed(0)}g',
                        style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w500),
                      ),
                      const TextSpan(text: ' · '),
                      TextSpan(
                        text: 'F ${f.toStringAsFixed(0)}g',
                        style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${kcal.toStringAsFixed(0)} kcal'),
                    const SizedBox(width: 8),
                    const Icon(Icons.chevron_right, color: Colors.grey),
                  ],
                ),
                onTap: () => showIngredientBreakdown(context, d),
              );
            },
          );
        },
      ),

    );
  }
}
