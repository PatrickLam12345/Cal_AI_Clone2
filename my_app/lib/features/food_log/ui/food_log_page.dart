import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/timezone_service.dart';

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
              return ListTile(
                title: Text(name),
                subtitle: Text('P ${p.toStringAsFixed(0)}g · C ${c.toStringAsFixed(0)}g · F ${f.toStringAsFixed(0)}g'),
                trailing: Text('${kcal.toStringAsFixed(0)} kcal'),
              );
            },
          );
        },
      ),

    );
  }
}
