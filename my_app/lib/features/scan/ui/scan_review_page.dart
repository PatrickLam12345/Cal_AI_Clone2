// lib/features/scan/ui/scan_review_page.dart
import 'dart:io';
import 'package:flutter/material.dart';
import '../data/food_scan_service.dart';

class ScanReviewPage extends StatefulWidget {
  final File photo; // passed from camera page
  const ScanReviewPage({super.key, required this.photo});

  @override
  State<ScanReviewPage> createState() => _ScanReviewPageState();
}

class _ScanReviewPageState extends State<ScanReviewPage> {
  late File _photo;
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _photo = widget.photo;
  }

  Future<void> _backToCamera() async {
    if (!mounted) return;
    Navigator.of(context).pop('retake'); // tell parent to reopen camera
  }

  Future<void> _analyze() async {
    setState(() {
      _loading = true;
      _error = null;
      _items.clear();
    });

    // quick sanity: very small file = likely invalid/black
    final bytes = await _photo.length();
    if (bytes < 10 * 1024) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Photo looks invalid. Retake and try again.')),
      );
      await _backToCamera();
      setState(() => _loading = false);
      return;
    }

    try {
      // UI hard timeout (~8s) so we never spin forever
      final out = await Future.any<List<Map<String, dynamic>>>([
        FoodScanService.instance.analyzeAndResolve(_photo),
        Future.delayed(const Duration(seconds: 8),
            () => throw Exception('Analysis took too long')),
      ]);

      if (!mounted) return;

      // If either scan or resolve ended up empty, treat as "no food"
      if (out.isEmpty) {
        if (!mounted) return;

        // Show a modal alert first
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('No Food Detected'),
            content: const Text(
                'We couldn’t detect any food in this photo. Please retake a clearer photo.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );

        await _backToCamera(); // go back to retake
        return;
      }

      setState(() => _items = out);
    } catch (e) {
      if (!mounted) return;

      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Analyze Failed'),
          content: Text('Error analyzing image: $e'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );

      await _backToCamera();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Review Photo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.camera_alt),
            tooltip: 'Retake Photo',
            onPressed: _loading
                ? null
                : _backToCamera, // manual retake → parent handles
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(_photo),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _loading ? null : _analyze,
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.insights),
            label: Text(_loading ? 'Analyzing…' : 'Analyze Food'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: theme.textTheme.bodyMedium?.copyWith(color: Colors.red)),
          ],
          if (_items.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Detected items', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final it in _items)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(it['name']?.toString() ?? 'Unknown'),
                  subtitle: Text('${it['portion_desc']} • ${it['data_type']}'),
                  trailing: Text(
                    '${(it['nutrients']?['calories'] ?? 0)} kcal',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  onTap: () {
                    // TODO: add to diary or open detail
                  },
                ),
              ),
          ],
        ],
      ),
      floatingActionButton: _items.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () {
                // TODO: bulk-add to diary
              },
              icon: const Icon(Icons.check),
              label: const Text('Add to Diary'),
            ),
    );
  }
}
