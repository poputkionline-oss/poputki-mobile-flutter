import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../services/api_client.dart';
import '../theme/app_theme.dart';

/// Reviews the current user has left (GET /reviews/sent), paginated.
class MyReviewsScreen extends StatefulWidget {
  const MyReviewsScreen({super.key});

  @override
  State<MyReviewsScreen> createState() => _MyReviewsScreenState();
}

class _MyReviewsScreenState extends State<MyReviewsScreen> {
  final ApiClient _api = ApiClient();
  List<dynamic> _reviews = [];
  int _page = 1;
  int _count = 0;
  int _pageSize = 20;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load(1);
  }

  Future<void> _load(int page) async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final res = await _api.get('/reviews/sent', queryParameters: {'page': page});
      final data = res.data as Map<String, dynamic>;
      setState(() {
        _reviews = data['reviews'] as List<dynamic>? ?? [];
        _count = data['count'] as int? ?? 0;
        _pageSize = data['page_size'] as int? ?? 20;
        _page = page;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  String _date(String? value) {
    if (value == null || value.isEmpty) return '';
    try {
      return DateFormat('d MMM yyyy', 'ru').format(DateTime.parse(value).toLocal());
    } catch (_) {
      return value;
    }
  }

  Widget _card(Map<String, dynamic> r) {
    final isBus = r['type'] == 'bus';
    final title = (isBus ? (r['company'] ?? r['person_name']) : r['person_name']) ?? '';
    final tripDate = _date(r['trip_date'] as String?);
    final comment = r['comment'] as String?;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(title.toString(),
                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
              ),
              Text('★ ${r['rating']} / 5',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFD97706))),
            ],
          ),
          const SizedBox(height: 2),
          Text('Отзыв от ${_date(r['created_at'] as String?)}',
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 8),
          Text(
            '${r['from_city'] ?? ''} → ${r['to_city'] ?? ''}'
            '${tripDate.isNotEmpty ? ' · $tripDate' : ''} · ${isBus ? 'Автобус' : 'Попутка'}',
            style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 8),
          Text(
            (comment != null && comment.isNotEmpty) ? comment : 'Оценка без комментария',
            style: TextStyle(
              fontSize: 13,
              color: (comment != null && comment.isNotEmpty) ? AppTheme.textPrimary : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColor)));
    }
    if (_failed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Не удалось загрузить отзывы'),
            TextButton(onPressed: () => _load(_page), child: const Text('Повторить')),
          ],
        ),
      );
    }
    if (_count == 0) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Вы пока не оставили отзывов. После завершения рейса и подтверждения посадки оценить перевозчика можно в «Мои билеты».',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textSecondary),
              ),
              TextButton(onPressed: () => context.push('/my-tickets'), child: const Text('Перейти в «Мои билеты»')),
            ],
          ),
        ),
      );
    }
    final pages = (_count / _pageSize).ceil();
    return RefreshIndicator(
      onRefresh: () => _load(_page),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          ..._reviews.map((r) => _card(r as Map<String, dynamic>)),
          if (pages > 1)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(onPressed: _page > 1 ? () => _load(_page - 1) : null, child: const Text('Назад')),
                Text('$_page / $pages'),
                TextButton(onPressed: _page < pages ? () => _load(_page + 1) : null, child: const Text('Далее')),
              ],
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Мои отзывы',
            style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: _body(),
    );
  }
}
