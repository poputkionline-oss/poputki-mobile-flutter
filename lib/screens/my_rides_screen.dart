import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/ride.dart';
import '../services/api_client.dart';
import '../services/auth_provider.dart';
import '../theme/app_theme.dart';

class MyRidesScreen extends StatefulWidget {
  const MyRidesScreen({super.key});

  @override
  State<MyRidesScreen> createState() => _MyRidesScreenState();
}

class _MyRidesScreenState extends State<MyRidesScreen> {
  final ApiClient _api = ApiClient();

  bool _loading = true;
  String _activeTab = 'active';
  List<Ride> _rides = [];
  final Set<int> _expanded = {};
  final Set<int> _phoneExpanded = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetch());
  }

  int? get _userId => context.read<AuthProvider>().user?.id;

  Future<void> _fetch() async {
    final userId = _userId;
    if (userId == null) {
      if (mounted) context.go('/auth');
      return;
    }
    setState(() => _loading = true);
    try {
      final res = await _api.get('/rides/my', queryParameters: {'userId': userId});
      final list = (res.data as List).map((e) => Ride.fromJson(e as Map<String, dynamic>)).toList();
      if (!mounted) return;
      setState(() {
        _rides = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showSnack('Ошибка при загрузке поездок', isError: true);
    }
  }

  List<Ride> get _activeRides => _rides.where((r) => r.status == 'active').toList();

  List<Ride> get _pastRides {
    final list = _rides.where((r) => r.status == 'completed' || r.status == 'cancelled').toList();
    list.sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  List<Ride> get _displayed => _activeTab == 'active' ? _activeRides : _pastRides;

  bool _isDriver(Ride r) => r.driverId == _userId;

  Map<String, dynamic>? _userBooking(Ride r) {
    if (r.bookings == null) return null;
    for (final b in r.bookings!) {
      final m = b as Map<String, dynamic>;
      if (m['passenger_id'] == _userId) return m;
    }
    return null;
  }

  bool _canCancel(Ride r) {
    if (r.status == 'completed' || r.status == 'cancelled') return false;
    try {
      final t = r.time.isEmpty ? '00:00' : r.time;
      final dt = DateTime.parse('${r.date}T${t.length == 5 ? '$t:00' : t}');
      return DateTime.now().isBefore(dt);
    } catch (_) {
      return true;
    }
  }

  String _formatDate(String dateStr) {
    try {
      return DateFormat('d MMMM', 'ru').format(DateTime.parse(dateStr));
    } catch (_) {
      return dateStr;
    }
  }

  Color _statusBg(Ride r) {
    if (r.status == 'completed') return const Color(0xFFF1F5F9);
    if (r.status == 'cancelled') return const Color(0xFFFEE2E2);
    return const Color(0xFFDCFCE7);
  }

  Color _statusFg(Ride r) {
    if (r.status == 'completed') return const Color(0xFF475569);
    if (r.status == 'cancelled') return const Color(0xFFDC2626);
    return const Color(0xFF16A34A);
  }

  String _statusText(Ride r) {
    if (r.status == 'completed') return 'Завершено';
    if (r.status == 'cancelled') return 'Отменено';
    return 'Активно';
  }

  void _toggleExpand(int id) {
    setState(() {
      if (_expanded.contains(id)) {
        _expanded.remove(id);
      } else {
        _expanded.add(id);
      }
    });
  }

  void _togglePhoneExpand(int id) {
    setState(() {
      if (_phoneExpanded.contains(id)) {
        _phoneExpanded.remove(id);
      } else {
        _phoneExpanded.add(id);
      }
    });
  }

  Future<void> _callPhone(String? phone, int rideId) async {
    if (phone == null || phone.isEmpty) return;
    _togglePhoneExpand(rideId);
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _copyPhone(String? phone) async {
    if (phone == null || phone.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: phone));
    _showSnack('Номер скопирован в буфер обмена');
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppTheme.errorColor : const Color(0xFF1E293B),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<bool> _confirm(String title, String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              minimumSize: const Size(120, 44),
            ),
            child: const Text('Подтвердить'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _completeRide(Ride r) async {
    final ok = await _confirm('Подтверждение', 'Вы уверены, что хотите завершить эту поездку?');
    if (!ok) return;
    try {
      await _api.post('/rides/${r.id}/complete', data: {'driver_id': _userId});
      if (!mounted) return;
      setState(() {
        final idx = _rides.indexWhere((x) => x.id == r.id);
        if (idx != -1) {
          _rides[idx] = _replaceStatus(_rides[idx], 'completed');
        }
      });
      _showSnack('Поездка завершена');
    } catch (e) {
      _showSnack('Ошибка при завершении поездки', isError: true);
    }
  }

  Future<void> _cancelRide(Ride r) async {
    final passengerCount = r.bookings?.length ?? 0;
    final message = passengerCount > 0
        ? 'Вы уверены, что хотите отменить поездку? У вас уже есть $passengerCount пассажиров.'
        : 'Вы уверены, что хотите отменить поездку?';
    final ok = await _confirm('Отмена поездки', message);
    if (!ok) return;
    try {
      await _api.post('/rides/${r.id}/cancel', data: {'driver_id': _userId});
      if (!mounted) return;
      setState(() => _rides.removeWhere((x) => x.id == r.id));
      _showSnack('Поездка отменена');
    } catch (e) {
      _showSnack('Ошибка при отмене поездки', isError: true);
    }
  }

  Future<void> _cancelBooking(Ride r) async {
    final booking = _userBooking(r);
    if (booking == null) return;
    final ok = await _confirm('Отмена брони', 'Вы уверены, что хотите отменить бронирование на эту поездку?');
    if (!ok) return;
    try {
      await _api.post('/bookings/${booking['id']}/cancel', data: {'passenger_id': _userId});
      if (!mounted) return;
      setState(() => _rides.removeWhere((x) => x.id == r.id));
      _showSnack('Бронирование отменено');
    } catch (e) {
      _showSnack('Ошибка при отмене бронирования', isError: true);
    }
  }

  void _repeatRide(Ride r) {
    final params = <String, String>{
      'role': _isDriver(r) ? 'driver' : 'passenger',
      'from': r.fromCity,
      'to': r.toCity,
      'time': r.time,
      'price': r.price.toString(),
      'seats': r.seats.toString(),
      'fromAddress': r.fromAddress ?? '',
      'toAddress': r.toAddress ?? '',
      'allows_delivery': r.allowsDelivery ? 'true' : 'false',
    };
    final query = params.entries
        .map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    context.go('/create?$query');
  }

  Future<void> _openReviewDialog(Ride r) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => _ReviewDialog(rideId: r.id, driverId: r.driverId ?? 0, reviewerId: _userId ?? 0),
    );
    if (result == true && mounted) {
      _showSnack('Ваш отзыв опубликован');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        title: const Text(
          'Мои поездки',
          style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          _buildTabs(),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppTheme.primaryColor),
                  )
                : _displayed.isEmpty
                    ? _buildEmpty()
                    : RefreshIndicator(
                        color: AppTheme.primaryColor,
                        onRefresh: _fetch,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                          itemCount: _displayed.length,
                          itemBuilder: (ctx, i) => _buildRideCard(_displayed[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            _buildTab('active', 'Активные (${_activeRides.length})'),
            _buildTab('past', 'Прошедшие (${_pastRides.length})'),
          ],
        ),
      ),
    );
  }

  Widget _buildTab(String key, String label) {
    final active = _activeTab == key;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _activeTab = key),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: active ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: active
                ? [const BoxShadow(color: Color(0x14000000), blurRadius: 4, offset: Offset(0, 1))]
                : [],
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: active ? const Color(0xFF1E293B) : const Color(0xFF64748B),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    final isActive = _activeTab == 'active';
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: const BoxDecoration(
                color: Color(0xFFF1F5F9),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Text('📭', style: TextStyle(fontSize: 38)),
            ),
            const SizedBox(height: 16),
            Text(
              isActive ? 'Нет активных поездок' : 'Нет прошедших поездок',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF334155),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isActive
                  ? 'Создайте новую поездку или найдите попутчика'
                  : 'Здесь будут отображаться завершенные поездки',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Color(0xFF64748B)),
            ),
            if (isActive) ...[
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => context.go('/create'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text('Создать поездку',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRideCard(Ride r) {
    final isExpanded = _expanded.contains(r.id);
    final isDriver = _isDriver(r);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: const [
          BoxShadow(color: Color(0x05000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: () => _toggleExpand(r.id),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    '${r.fromCity} → ${r.toCity}',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF1E293B),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _statusBg(r),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    _statusText(r).toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                      color: _statusFg(r),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(Icons.calendar_today_outlined, size: 14, color: Color(0xFF94A3B8)),
                                const SizedBox(width: 4),
                                Text(_formatDate(r.date), style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
                                const SizedBox(width: 16),
                                const Icon(Icons.access_time, size: 14, color: Color(0xFF94A3B8)),
                                const SizedBox(width: 4),
                                Text(r.time, style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
                              ],
                            ),
                          ],
                        ),
                      ),
                      AnimatedRotation(
                        turns: isExpanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: const BoxDecoration(
                            color: Color(0xFFF1F5F9),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.keyboard_arrow_down, size: 16, color: Color(0xFF475569)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: isDriver ? const Color(0xFFFEF3C7) : const Color(0xFFDBEAFE),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.person_outline,
                                size: 12,
                                color: isDriver ? const Color(0xFFB45309) : const Color(0xFF1D4ED8)),
                            const SizedBox(width: 4),
                            Text(
                              isDriver ? 'Водитель' : 'Пассажир',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isDriver ? const Color(0xFFB45309) : const Color(0xFF1D4ED8),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text('ЦЕНА',
                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8), letterSpacing: 0.5)),
                          Text('${r.price.toStringAsFixed(0)} с.',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded)
            Container(
              color: const Color(0xFFF8FAFC),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildDriverSection(r),
                  if (isDriver) ...[
                    const SizedBox(height: 16),
                    _buildPassengersSection(r),
                  ] else if (_userBooking(r) != null) ...[
                    const SizedBox(height: 16),
                    _buildMyBookingSection(r),
                  ],
                  const SizedBox(height: 16),
                  _buildActionButtons(r),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDriverSection(Ride r) {
    final isDriver = _isDriver(r);
    final name = r.driverName ?? '';
    final phoneOpen = _phoneExpanded.contains(r.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isDriver ? 'ВЫ - ВОДИТЕЛЬ' : 'ВОДИТЕЛЬ',
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8), letterSpacing: 0.5),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFFBBF24), Color(0xFFF97316)],
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : 'D',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isEmpty ? 'Водитель' : name,
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.star, size: 12, color: Color(0xFFF59E0B)),
                        const SizedBox(width: 2),
                        Text(
                          (r.driverRating ?? 5.0).toStringAsFixed(1),
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (!isDriver && r.driverPhone != null && r.driverPhone!.isNotEmpty)
                GestureDetector(
                  onTap: () => _callPhone(r.driverPhone, r.id),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCFCE7),
                      shape: BoxShape.circle,
                      border: phoneOpen ? Border.all(color: const Color(0xFF16A34A), width: 2) : null,
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.phone, size: 18, color: Color(0xFF16A34A)),
                  ),
                ),
            ],
          ),
        ),
        if (phoneOpen && r.driverPhone != null) ...[
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => _copyPhone(r.driverPhone),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.phone, size: 14, color: Colors.white),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      r.driverPhone!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.copy, size: 14, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (r.vehicle != null && !r.isPassengerEntry) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.directions_car, color: Color(0xFFB45309), size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${r.vehicle!['make'] ?? ''} ${r.vehicle!['model'] ?? ''}'.trim(),
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF334155), fontSize: 13),
                      ),
                      Text(
                        r.vehicle!['plate_number']?.toString() ?? '',
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Color(0xFF94A3B8)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPassengersSection(Ride r) {
    final bookings = (r.bookings ?? []).cast<Map<String, dynamic>>();
    final empty = (r.seats - bookings.length).clamp(0, r.seats);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ПАССАЖИРЫ (${bookings.length} / ${r.seats})',
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8), letterSpacing: 0.5),
        ),
        const SizedBox(height: 8),
        ...bookings.map((b) {
          final name = (b['passenger_name'] ?? '') as String? ?? '';
          final gender = b['passenger_gender'] as String?;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(color: Color(0xFFDBEAFE), shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : 'P',
                    style: const TextStyle(color: Color(0xFF1D4ED8), fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name.isEmpty ? 'Пассажир' : name,
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF334155))),
                      Text('Место ${b['seat_number'] ?? ''}',
                          style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                    ],
                  ),
                ),
                if (b['age'] != null)
                  Text(
                    '${b['age']} ${gender == 'male' ? '👨' : gender == 'female' ? '👩' : ''}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                  ),
              ],
            ),
          );
        }),
        ...List.generate(empty, (i) {
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0), style: BorderStyle.solid),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(color: Color(0xFFF8FAFC), shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: const Icon(Icons.person_outline, size: 18, color: Color(0xFFCBD5E1)),
                ),
                const SizedBox(width: 12),
                const Text('Свободное место',
                    style: TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.w500)),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildMyBookingSection(Ride r) {
    final b = _userBooking(r);
    if (b == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('МОЯ БРОНЬ',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8), letterSpacing: 0.5)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Место в автомобиле',
                  style: TextStyle(fontSize: 13, color: Color(0xFF64748B), fontWeight: FontWeight.w500)),
              Text('№${b['seat_number']}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons(Ride r) {
    final isDriver = _isDriver(r);
    final userBooking = _userBooking(r);
    final canCancel = _canCancel(r);
    final buttons = <Widget>[];

    buttons.add(_actionButton(
      label: 'Подробнее',
      onTap: () => context.go('/ride/${r.id}'),
      backgroundColor: const Color(0xFF0F172A),
      foregroundColor: Colors.white,
      trailingIcon: Icons.arrow_forward,
    ));

    if (isDriver && r.status == 'active') {
      buttons.add(_actionButton(
        label: 'Завершить поездку',
        onTap: () => _completeRide(r),
        backgroundColor: const Color(0xFF22C55E),
        foregroundColor: Colors.white,
      ));
    }

    if (isDriver && canCancel) {
      buttons.add(_actionButton(
        label: 'Отменить поездку',
        onTap: () => _cancelRide(r),
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.errorColor,
        border: Border.all(color: const Color(0xFFFEE2E2), width: 2),
      ));
    }

    if (!isDriver && userBooking != null && canCancel) {
      buttons.add(_actionButton(
        label: 'Отменить бронь',
        onTap: () => _cancelBooking(r),
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.errorColor,
        border: Border.all(color: const Color(0xFFFEE2E2), width: 2),
      ));
    }

    if (!isDriver && r.status == 'completed') {
      buttons.add(_actionButton(
        label: 'Оставить отзыв',
        onTap: () => _openReviewDialog(r),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
      ));
    }

    if (r.status == 'completed' || r.status == 'cancelled') {
      buttons.add(_actionButton(
        label: 'Повторить поездку',
        onTap: () => _repeatRide(r),
        backgroundColor: const Color(0xFFF1F5F9),
        foregroundColor: const Color(0xFF1E293B),
      ));
    }

    return Column(
      children: [
        for (int i = 0; i < buttons.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          buttons[i],
        ],
      ],
    );
  }

  Widget _actionButton({
    required String label,
    required VoidCallback onTap,
    required Color backgroundColor,
    required Color foregroundColor,
    IconData? trailingIcon,
    BoxBorder? border,
  }) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: border,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label,
                    style: TextStyle(color: foregroundColor, fontWeight: FontWeight.bold, fontSize: 14)),
                if (trailingIcon != null) ...[
                  const SizedBox(width: 6),
                  Icon(trailingIcon, size: 16, color: foregroundColor),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Ride _replaceStatus(Ride r, String newStatus) {
    return Ride(
      id: r.id,
      fromCity: r.fromCity,
      toCity: r.toCity,
      date: r.date,
      time: r.time,
      price: r.price,
      seats: r.seats,
      bookedSeats: r.bookedSeats,
      driverName: r.driverName,
      driverRating: r.driverRating,
      driverId: r.driverId,
      driverPhone: r.driverPhone,
      fromAddress: r.fromAddress,
      toAddress: r.toAddress,
      allowsDelivery: r.allowsDelivery,
      isPassengerEntry: r.isPassengerEntry,
      status: newStatus,
      vehicle: r.vehicle,
      driverPreferences: r.driverPreferences,
      bookings: r.bookings,
      reservedSeats: r.reservedSeats,
      rowPrices: r.rowPrices,
      totalSeats: r.totalSeats,
    );
  }
}

class _ReviewDialog extends StatefulWidget {
  final int rideId;
  final int driverId;
  final int reviewerId;
  const _ReviewDialog({required this.rideId, required this.driverId, required this.reviewerId});

  @override
  State<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<_ReviewDialog> {
  final ApiClient _api = ApiClient();
  final TextEditingController _comment = TextEditingController();
  int _rating = 0;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rating == 0) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await _api.post('/reviews', data: {
        'ride_id': widget.rideId,
        'reviewer_id': widget.reviewerId,
        'driver_id': widget.driverId,
        'rating': _rating,
        'comment': _comment.text,
      });
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      var message = 'Ошибка при отправке отзыва';
      if (e is DioException && e.response?.data is Map) {
        message = (e.response!.data['message'] as String?) ?? message;
      }
      setState(() {
        _submitting = false;
        _error = message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Оставить отзыв',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
            const SizedBox(height: 4),
            const Text('Оцените поездку и водителя',
                style: TextStyle(fontSize: 13, color: Color(0xFF64748B))),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (i) {
                final star = i + 1;
                return IconButton(
                  onPressed: () => setState(() => _rating = star),
                  iconSize: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  icon: Icon(
                    Icons.star,
                    color: star <= _rating ? const Color(0xFFFBBF24) : const Color(0xFFE2E8F0),
                  ),
                );
              }),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _comment,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Комментарий (необязательно)',
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                contentPadding: const EdgeInsets.all(12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: AppTheme.errorColor, fontSize: 12)),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
                    child: const Text('Отмена', style: TextStyle(color: Color(0xFF64748B))),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: (_rating == 0 || _submitting) ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _submitting
                        ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Отправить', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
