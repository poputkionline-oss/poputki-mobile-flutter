import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import '../services/api_client.dart';
import '../services/auth_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/bus_review_dialog.dart';

class MyTicketsScreen extends StatefulWidget {
  const MyTicketsScreen({super.key});

  @override
  State<MyTicketsScreen> createState() => _MyTicketsScreenState();
}

class _MyTicketsScreenState extends State<MyTicketsScreen> {
  final ApiClient _apiClient = ApiClient();
  List<dynamic> _bookings = [];
  bool _isLoading = true;
  final Set<String> _expandedPhoneBookings = {};
  List<dynamic> _reviewEligibility = [];

  @override
  void initState() {
    super.initState();
    _fetchBookings();
    _fetchReviewEligibility();
  }

  Future<void> _fetchReviewEligibility() async {
    try {
      final res = await _apiClient.get('/reviews/bus/eligible');
      if (mounted) setState(() => _reviewEligibility = res.data as List<dynamic>);
    } catch (_) {
      if (mounted) setState(() => _reviewEligibility = []);
    }
  }

  Map<String, dynamic>? _eligibilityFor(dynamic bookingId) {
    for (final r in _reviewEligibility) {
      if (r['booking_id'].toString() == bookingId.toString()) return r as Map<String, dynamic>;
    }
    return null;
  }

  Future<void> _openReview(int bookingId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => BusReviewDialog(bookingId: bookingId),
    );
    if (ok == true) await _fetchReviewEligibility();
  }

  Future<void> _fetchBookings() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (auth.user == null) {
      setState(() => _isLoading = false);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final response = await _apiClient.get('/users/${auth.user!.id}/bus-bookings');
      if (response.statusCode == 200) {
        setState(() {
          _bookings = response.data;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error fetching bookings: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ошибка при загрузке билетов')),
        );
      }
      setState(() => _isLoading = false);
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '';
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('d MMMM', 'ru').format(date);
    } catch (e) {
      return dateStr;
    }
  }

  String _formatDuration(int? minutes) {
    if (minutes == null) return '';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return '$h ч.${m > 0 ? ' $m м.' : ''}';
  }

  Future<void> _makeCall(String? phone, String bookingId) async {
    if (phone == null || phone.isEmpty) return;
    
    setState(() {
      if (_expandedPhoneBookings.contains(bookingId)) {
        _expandedPhoneBookings.remove(bookingId);
      } else {
        _expandedPhoneBookings.add(bookingId);
      }
    });

    final Uri url = Uri.parse('tel:${phone.replaceAll(' ', '')}');
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url);
      } else {
        throw 'Could not launch $url';
      }
    } catch (e) {
      print('Error launching phone: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось совершить звонок на $phone')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final todayStr = DateTime.now().toIso8601String().split('T')[0];
    final upcoming = _bookings.where((b) => (b['departure_date'] as String).compareTo(todayStr) >= 0).toList();
    final past = _bookings.where((b) => (b['departure_date'] as String).compareTo(todayStr) < 0).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Мои билеты',
          style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColor)))
          : RefreshIndicator(
              onRefresh: () async { await _fetchBookings(); await _fetchReviewEligibility(); },
              color: AppTheme.primaryColor,
              child: _bookings.isEmpty
                  ? _buildEmptyState()
                  : SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (upcoming.isNotEmpty) ...[
                            Text(
                              'ПРЕДСТОЯЩИЕ (${upcoming.length})',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                color: Colors.grey,
                                letterSpacing: 1,
                              ),
                            ),
                            const SizedBox(height: 16),
                            ...upcoming.map((b) => _buildTicketCard(b, isPast: false)),
                            const SizedBox(height: 24),
                          ],
                          if (past.isNotEmpty) ...[
                            Text(
                              'ПРОШЕДШИЕ (${past.length})',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                color: Colors.grey,
                                letterSpacing: 1,
                              ),
                            ),
                            const SizedBox(height: 16),
                            ...past.map((b) => _buildTicketCard(b, isPast: true)),
                          ],
                        ],
                      ),
                    ),
            ),
    );
  }

  Widget _buildEmptyState() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.6,
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(32),
              ),
              child: const Icon(Icons.confirmation_number_outlined, size: 48, color: Color(0xFF60A5FA)),
            ),
            const SizedBox(height: 24),
            const Text(
              'Нет билетов',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 8),
            const Text(
              'У вас ещё нет купленных автобусных билетов',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 28),
            ElevatedButton(
              onPressed: () => context.go('/'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                shadowColor: const Color(0x662563EB),
                elevation: 8,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: const Text('Найти рейс', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTicketCard(dynamic b, {required bool isPast}) {
    final seatNumbers = b['seat_numbers'] as List<dynamic>? ?? [];
    final id = b['id'].toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isPast ? 0.02 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Opacity(
          opacity: isPast ? 0.7 : 1.0,
          child: Column(
            children: [
              // Card Top Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  gradient: isPast
                      ? const LinearGradient(colors: [Color(0xFF94A3B8), Color(0xFF64748B)])
                      : const LinearGradient(colors: [Color(0xFF1D4ED8), Color(0xFF4338CA)]),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      (b['transport_company'] ?? '').toString().toUpperCase(),
                      style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withOpacity(0.2)),
                      ),
                      child: Text(
                        isPast ? 'Завершено' : 'Подтверждено',
                        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                      ),
                    ),
                  ],
                ),
              ),

              // Time Route Segment
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Departure
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          b['departure_time'] ?? '',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: isPast ? Colors.grey : const Color(0xFF2563EB),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _formatDate(b['departure_date']),
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppTheme.textPrimary, letterSpacing: -0.5),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          b['from_city'] ?? '',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),

                    // Travel Path Arrow/Duration
                    Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isPast ? Colors.grey.shade100 : const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            _formatDuration(b['duration_minutes']),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isPast ? Colors.grey : const Color(0xFF1E40AF),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          width: 80,
                          child: Row(
                            children: [
                              Expanded(
                                child: Container(
                                  height: 1,
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: isPast ? Colors.grey.shade300 : const Color(0xFF93C5FD),
                                      style: BorderStyle.solid,
                                      width: 0.5,
                                    ),
                                  ),
                                ),
                              ),
                              Icon(Icons.chevron_right_rounded, size: 16, color: isPast ? Colors.grey : const Color(0xFF60A5FA)),
                            ],
                          ),
                        ),
                      ],
                    ),

                    // Arrival
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          b['arrival_time'] ?? '',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: isPast ? Colors.grey : const Color(0xFF2563EB),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _formatDate(b['arrival_date'] ?? b['departure_date']),
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppTheme.textPrimary, letterSpacing: -0.5),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          b['to_city'] ?? '',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Passengers & Specifics Row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('ПАССАЖИРЫ', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey)),
                        const SizedBox(height: 4),
                        Text(
                          '${b['passenger_count']} ${b['passenger_count'] == 1 ? 'пассажир' : b['passenger_count'] <= 4 ? 'пассажира' : 'пассажиров'}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textPrimary),
                        ),
                        const SizedBox(height: 16),
                        const Text('ДАТА И ВРЕМЯ', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey)),
                        const SizedBox(height: 4),
                        Text(
                          _formatDate(b['departure_date']),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textPrimary),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text('МЕСТА', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey)),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 4,
                          children: seatNumbers
                              .map((seat) => Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '№$seat',
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade800),
                                    ),
                                  ))
                              .toList(),
                        ),
                        const SizedBox(height: 16),
                        const Text('СУММА', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey)),
                        const SizedBox(height: 4),
                        Text(
                          '${b['total_price'] ?? b['price']} с.',
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: AppTheme.textPrimary),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Contact Operator Panel if available and not past
              if (b['operator_phone'] != null && !isPast) ...[
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _makeCall(b['operator_phone'], id),
                          icon: const Icon(Icons.phone_in_talk_outlined, size: 16, color: Colors.green),
                          label: const Text('Связаться с оператором', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.green)),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: const Color(0xFFF0FDF4),
                            side: const BorderSide(color: Color(0xFFDCFCE7)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_expandedPhoneBookings.contains(id))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.phone, color: Colors.white, size: 16),
                              const SizedBox(width: 8),
                              Text(
                                b['operator_phone'] ?? '',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ],
                          ),
                          const Text('Позвонить', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
              ],

              if (_eligibilityFor(b['id']) != null) ...[
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _eligibilityFor(b['id'])!['can_review'] == true
                      ? OutlinedButton.icon(
                          onPressed: () => _openReview(int.parse(b['id'].toString())),
                          icon: const Icon(Icons.star, size: 16, color: Color(0xFFD97706)),
                          label: const Text('Оставить отзыв',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFFD97706))),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 44),
                            side: const BorderSide(color: Color(0xFFFDE68A)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        )
                      : const Text('Отзыв оставлен',
                          style: TextStyle(fontSize: 12, color: Color(0xFF059669), fontWeight: FontWeight.bold)),
                ),
              ],

              const SizedBox(height: 16),

              // Perforated Cutout Separator
              SizedBox(
                height: 24,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          width: 12,
                          height: 24,
                          decoration: const BoxDecoration(
                            color: Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.only(topRight: Radius.circular(12), bottomRight: Radius.circular(12)),
                          ),
                        ),
                        Container(
                          width: 12,
                          height: 24,
                          decoration: const BoxDecoration(
                            color: Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.only(topLeft: Radius.circular(12), bottomLeft: Radius.circular(12)),
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: List.generate(
                          30,
                          (index) => Expanded(
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              height: 1,
                              color: Colors.grey.shade200,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Barcode & Ticket Number Footer
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('НОМЕР БИЛЕТА', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.grey)),
                        const SizedBox(height: 2),
                        Text(
                          'TK-${id.padLeft(6, '0')}-${b['departure_date'] != null ? DateTime.parse(b['departure_date']).month : 1}',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Colors.grey.shade800,
                          ),
                        ),
                      ],
                    ),
                    
                    // Simple programmatic Barcode Drawing
                    Row(
                      children: [
                        Container(width: 3, height: 28, color: Colors.grey.shade800),
                        const SizedBox(width: 1),
                        Container(width: 1, height: 28, color: Colors.grey.shade800),
                        const SizedBox(width: 2),
                        Container(width: 4, height: 28, color: Colors.grey.shade800),
                        const SizedBox(width: 1),
                        Container(width: 2, height: 28, color: Colors.grey.shade800),
                        const SizedBox(width: 1),
                        Container(width: 1, height: 28, color: Colors.grey.shade800),
                        const SizedBox(width: 2),
                        Container(width: 5, height: 28, color: Colors.grey.shade800),
                        const SizedBox(width: 1),
                        Container(width: 2, height: 28, color: Colors.grey.shade800),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
