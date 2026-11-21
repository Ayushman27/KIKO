/// Memory Screen — shows and manages KIKO's personal memory items.
library;

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../config/kiko_theme.dart';

class MemoryScreen extends StatefulWidget {
  const MemoryScreen({super.key});
  @override
  State<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends State<MemoryScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = false;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({String? query}) async {
    setState(() => _loading = true);
    try {
      final url = query != null && query.isNotEmpty
          ? '${ApiConfig.baseUrl}/api/v1/memory?query=${Uri.encodeComponent(query)}'
          : '${ApiConfig.baseUrl}/api/v1/memory';
      final res =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body);
        setState(() {
          _items = data is List
              ? List<Map<String, dynamic>>.from(data)
              : List<Map<String, dynamic>>.from(
                  data['items'] ?? data['memories'] ?? []);
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _delete(String id) async {
    try {
      await http
          .delete(Uri.parse('${ApiConfig.baseUrl}/api/v1/memory/$id'))
          .timeout(const Duration(seconds: 5));
      _load();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _searchCtrl,
            style: const TextStyle(color: KikoColors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Search memory...',
              prefixIcon:
                  const Icon(Icons.search, color: KikoColors.textMuted, size: 18),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear,
                          color: KikoColors.textMuted, size: 16),
                      onPressed: () {
                        _searchCtrl.clear();
                        _load();
                      },
                    )
                  : null,
            ),
            onChanged: (v) => _load(query: v),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(
                      color: KikoColors.cyan, strokeWidth: 2))
              : _items.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.memory,
                              color: KikoColors.textMuted, size: 48),
                          SizedBox(height: 12),
                          Text('No memory items',
                              style: TextStyle(color: KikoColors.textMuted)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _items.length,
                      itemBuilder: (_, i) => _memCard(_items[i]),
                    ),
        ),
      ],
    );
  }

  Widget _memCard(Map<String, dynamic> item) {
    final key = item['key'] ?? item['category'] ?? '';
    final value = item['value'] ?? item['content'] ?? '';
    final type = item['memory_type'] ?? item['type'] ?? 'fact';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: KikoDecor.card(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: KikoDecor.statusBadge(KikoColors.cyan),
            child: Text(type.toString().toUpperCase(),
                style: const TextStyle(
                    color: KikoColors.cyan,
                    fontSize: 9,
                    fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(key,
                    style: const TextStyle(
                        color: KikoColors.cyan,
                        fontWeight: FontWeight.w700,
                        fontSize: 12)),
                const SizedBox(height: 4),
                Text(value.toString(),
                    style: const TextStyle(
                        color: KikoColors.textPrimary, fontSize: 13)),
              ],
            ),
          ),
          if (item['id'] != null)
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  size: 16, color: KikoColors.textMuted),
              tooltip: 'Delete',
              onPressed: () => _delete(item['id']),
            ),
        ],
      ),
    );
  }
}
