import 'package:flutter/material.dart';
import '../../services/usda_api.dart';
import 'food_detail_sheet.dart';

class FoodDatabasePage extends StatefulWidget {
  const FoodDatabasePage({super.key});

  @override
  State<FoodDatabasePage> createState() => _FoodDatabasePageState();
}

class _FoodDatabasePageState extends State<FoodDatabasePage> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  final _api = const UsdaApi();

  List<Map<String, dynamic>> _results = [];
  bool _loading = false;
  bool _hasMore = false;
  int _currentPage = 1;
  int _pageSize = 25;
  int _totalHits = 0;
  String _currentQuery = '';

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScrollBackup);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScrollBackup);
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScrollBackup() {
    if (!_loading &&
        _hasMore &&
        _scrollController.position.extentAfter < 300) {
      _loadMore();
    }
  }

  Future<void> _search(String q) async {
    final query = q.trim();
    if (query.isEmpty) return;

    setState(() {
      _loading = true;
      _results.clear();
      _currentPage = 1;
      _currentQuery = query;
      _hasMore = true;
      _totalHits = 0;
    });

    try {
      final first = await _api.search(query, page: 1);
      if (!mounted) return;

      setState(() {
        _results = first.foods;
        _currentPage = first.page;
        _pageSize = first.pageSize;
        _totalHits = first.totalHits;
        _hasMore = _results.length < _totalHits;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeTopUpViewport());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Search error: $e')),
      );
      setState(() => _hasMore = false);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _maybeTopUpViewport() async {
    int attempts = 0;
    while (mounted &&
        !_loading &&
        _hasMore &&
        _scrollController.position.maxScrollExtent <= 0 &&
        attempts < 3) {
      attempts++;
      await _loadMore();
      await Future.delayed(const Duration(milliseconds: 50));
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _currentQuery.isEmpty || !_hasMore) return;

    setState(() => _loading = true);
    try {
      final nextPage = _currentPage + 1;
      final more = await _api.search(_currentQuery, page: nextPage);
      if (!mounted) return;

      final seen = _results.map((e) => e['fdcId']).toSet();
      final fresh = more.foods.where((e) => !seen.contains(e['fdcId'])).toList();

      setState(() {
        _currentPage = more.page;
        _pageSize = more.pageSize;
        _totalHits = more.totalHits;
        _results.addAll(fresh);
        _hasMore = _results.length < _totalHits;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _hasMore = false);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final showInitialLoader = _loading && _results.isEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Food Database')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      hintText: 'Search for a food...',
                      border: OutlineInputBorder(),
                    ),
                    textInputAction: TextInputAction.search,
                    onSubmitted: _search,
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => _search(_searchController.text),
                  child: const Text('Search'),
                ),
              ],
            ),
          ),

          if (showInitialLoader)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_results.isEmpty && _currentQuery.isNotEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('No results. Try another search.'),
              ),
            ),

          if (_results.isNotEmpty)
            Expanded(
              child: NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  if (n is ScrollUpdateNotification) {
                    final m = n.metrics;
                    if (!_loading &&
                        _hasMore &&
                        m.pixels >= (m.maxScrollExtent - 200)) {
                      _loadMore();
                    }
                  }
                  return false;
                },
                child: ListView.builder(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: _results.length + ((_loading && _results.isNotEmpty) ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index >= _results.length) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }

                    final food = _results[index];
                    final name = (food['name'] as String?)?.trim().isNotEmpty == true
                        ? food['name'] as String
                        : 'Unknown item';

                    final caloriesNum = food['calories'];
                    final cals = caloriesNum is num ? caloriesNum.toDouble() : 0.0;
                    final calsText = cals > 0 ? '${cals.toStringAsFixed(0)} kcal' : '—';
                    final unitText = (food['unit'] ?? '—').toString();

                    return ListTile(
                      title: Text(name),
                      subtitle: Text('$calsText, $unitText'),
                      trailing: IconButton(
                        icon: const Icon(Icons.add_circle, color: Colors.green),
                        onPressed: () {
                          final id = food['fdcId'];
                          final idInt = id is int ? id : (id is num ? id.toInt() : null);
                          if (idInt != null && idInt > 0) {
                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              builder: (_) => FoodDetailSheet(fdcId: idInt),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('No details for this item')),
                            );
                          }
                        },
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}
