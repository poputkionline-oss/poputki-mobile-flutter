import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/search_provider.dart';
import '../widgets/custom_button.dart';
import '../widgets/custom_text_field.dart';
import '../theme/app_theme.dart';
import '../models/ride.dart';
import '../models/bus_ticket.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../services/geo_city_resolver.dart';
import '../services/geolocation_service.dart';

class SearchResultsScreen extends StatefulWidget {
  const SearchResultsScreen({super.key});

  @override
  State<SearchResultsScreen> createState() => _SearchResultsScreenState();
}

class _SearchResultsScreenState extends State<SearchResultsScreen> {
  final TextEditingController _fromController = TextEditingController();
  final TextEditingController _toController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();

  static bool _geoAttempted = false; // automatic attempt once per app run
  String? _fromCity;
  bool _geoLoading = false;
  String _geoMessage = '';
  int _geoRevision = 0;

  void _setFromCity(String? city) {
    _geoRevision++;
    _geoMessage = '';
    _fromCity = city;
    _fromController.text = city ?? '';
  }

  /// Detects the nearest service city. Returns true if the origin was changed.
  Future<bool> _detectMyCity(SearchProvider provider, {bool automatic = false}) async {
    if (_geoLoading || provider.cities.isEmpty) return false;
    if (automatic) {
      if (_fromCity != null || _geoAttempted) return false;
      _geoAttempted = true;
    }
    final revision = _geoRevision;
    final tab = provider.activeTab;
    setState(() {
      _geoLoading = true;
      _geoMessage = 'Определяем город…';
    });
    try {
      final coords = await requestCoordinates(automatic: automatic);
      final resolver = await GeoCityResolver.load();
      final city = resolver.resolve(coords.latitude, coords.longitude, provider.cities,
          accuracy: coords.accuracy);
      if (!mounted || revision != _geoRevision || tab != provider.activeTab) return false;
      if (city == null) {
        setState(() => _geoMessage =
            'Город рядом с Вами отсутствует в списке отправления. Выберите город вручную.');
        return false;
      }
      setState(() {
        _fromCity = city;
        _fromController.text = city;
        _geoMessage = 'Ближайший город отправления: $city. Вы можете его изменить.';
      });
      return true;
    } catch (e) {
      if (mounted && revision == _geoRevision && tab == provider.activeTab) {
        setState(() => _geoMessage = locationErrorMessage(e));
      }
      return false;
    } finally {
      if (mounted) setState(() => _geoLoading = false);
    }
  }

  String _formatRideDate(String dateStr, String timeStr) {
    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();
      final tomorrow = now.add(const Duration(days: 1));
      
      String dayPart;
      if (dateStr == now.toIso8601String().split('T')[0]) {
        dayPart = 'Сегодня';
      } else if (dateStr == tomorrow.toIso8601String().split('T')[0]) {
        dayPart = 'Завтра';
      } else {
        dayPart = DateFormat('d MMMM', 'ru').format(date);
      }
      
      return '$dayPart в $timeStr';
    } catch (e) {
      return '$dateStr в $timeStr';
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<SearchProvider>(context, listen: false);
      final initialSearch = provider.search();
      provider.fetchCities().then((_) => _detectMyCity(provider, automatic: true)).then((changed) async {
        await initialSearch;
        if (changed && mounted) {
          provider.search(from: _fromController.text, to: _toController.text, date: _dateController.text);
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: Consumer<SearchProvider>(
        builder: (context, provider, child) {
          return CustomScrollView(
            slivers: [
              _buildHeader(provider),
              _buildResults(provider),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader(SearchProvider provider) {
    final isRides = provider.activeTab == 'rides';
    
    return SliverToBoxAdapter(
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 60, 20, 30),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isRides
                ? [const Color(0xFFFBBF24), const Color(0xFFF59E0B)] // Amber 400 to 500
                : [const Color(0xFF2563EB), const Color(0xFF4338CA)], // Blue 600 to Indigo 700
          ),
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(40)),
          boxShadow: [
            BoxShadow(
              color: (isRides ? Colors.amber : Colors.blue).withOpacity(0.2),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Tab Switcher
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  _buildTabButton(
                    'rides', 
                    'Попутки', 
                    Icons.directions_car, 
                    provider.activeTab == 'rides',
                    () => provider.setActiveTab('rides'),
                  ),
                  _buildTabButton(
                    'buses', 
                    'Автобусы', 
                    Icons.directions_bus, 
                    provider.activeTab == 'buses',
                    () => provider.setActiveTab('buses'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              isRides ? 'Поиск попутки' : 'Билеты на автобус',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 20),
            // Search Form
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  _buildCityDropdown(
                    label: 'Откуда',
                    icon: Icons.circle_outlined,
                    iconColor: isRides ? Colors.amber : Colors.blue,
                    provider: provider,
                    value: _fromCity,
                    onChanged: (val) => setState(() => _setFromCity(val)),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: _geoLoading ? null : () => _detectMyCity(provider),
                      child: Text(_geoLoading ? '📍 Определяем город…' : '📍 Определить мой город'),
                    ),
                  ),
                  if (_geoMessage.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(_geoMessage,
                          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                    ),
                  const Text(
                    'Геолокация используется только для выбора города. Данные GeoNames (CC BY 4.0).',
                    style: TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  _buildCityDropdown(
                    label: 'Куда',
                    icon: Icons.location_on_outlined,
                    iconColor: Colors.grey,
                    provider: provider,
                    onChanged: (val) => _toController.text = val ?? '',
                  ),
                  const SizedBox(height: 16),
                  CustomTextField(
                    label: 'Дата',
                    hint: 'Выберите дату',
                    readOnly: true,
                    prefixIcon: Icons.calendar_today_outlined,
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 90)),
                      );
                      if (date != null) {
                        _dateController.text = date.toIso8601String().split('T')[0];
                        setState(() {});
                      }
                    },
                    controller: _dateController,
                  ),
                  const SizedBox(height: 24),
                  CustomButton(
                    text: isRides ? 'Найти попутку' : 'Найти билеты',
                    onPressed: () => provider.search(
                      from: _fromController.text,
                      to: _toController.text,
                      date: _dateController.text,
                    ),
                    color: isRides ? AppTheme.textPrimary : const Color(0xFF2563EB),
                    textColor: Colors.white,
                    isLoading: provider.isLoading,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabButton(String value, String label, IconData icon, bool isActive, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isActive ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: isActive ? AppTheme.textPrimary : Colors.white,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: isActive ? AppTheme.textPrimary : Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCityDropdown({
    required String label,
    required IconData icon,
    required Color iconColor,
    required SearchProvider provider,
    required Function(String?) onChanged,
    String? value,
  }) {
    return DropdownButtonFormField<String>(
      value: provider.cities.contains(value) ? value : null,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: iconColor, size: 18),
      ),
      items: provider.cities.map((city) => DropdownMenuItem(value: city, child: Text(city))).toList(),
      onChanged: onChanged,
      dropdownColor: Colors.white,
    );
  }

  Widget _buildResults(SearchProvider provider) {
    if (provider.isLoading) {
      return SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) => _buildSkeletonCard(),
          childCount: 3,
        ),
      );
    }

    if (provider.activeTab == 'rides') {
      if (provider.rides.isEmpty) return _buildEmptyState('Попуток пока нет');
      return SliverPadding(
        padding: const EdgeInsets.only(top: 10, bottom: 32),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => _buildRideCard(provider.rides[index]),
            childCount: provider.rides.length,
          ),
        ),
      );
    } else {
      if (provider.busTickets.isEmpty) return _buildEmptyState('Рейсов пока нет');
      return SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => _buildBusCard(provider.busTickets[index]),
            childCount: provider.busTickets.length,
          ),
        ),
      );
    }
  }

  Widget _buildRideCard(Ride ride) {
    final availableSeats = ride.seats - (ride.bookedSeats ?? 0);
    
    return GestureDetector(
      onTap: () => context.push('/ride/${ride.id}'),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top row: badge + price
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB), // Amber 50
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.directions_car_outlined, color: Color(0xFFD97706), size: 13),
                        SizedBox(width: 5),
                        Text(
                          'Попутка',
                          style: TextStyle(color: Color(0xFFD97706), fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4), // Green 50
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFDCFCE7)),
                    ),
                    child: Text(
                      '${ride.price.toInt()} с.',
                      style: const TextStyle(
                        color: Color(0xFF166534),
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Date & Time
              Text(
                _formatRideDate(ride.date, ride.time),
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              // Route
              _buildRouteLine(ride.fromCity, ride.toCity),
              const SizedBox(height: 24),
              // Driver & Seats
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: const Color(0xFFF3F4F6),
                    child: Text(
                      ride.driverName?[0] ?? 'D',
                      style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ride.driverName ?? 'Водитель',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textPrimary),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(Icons.star, color: Color(0xFFFBBF24), size: 14),
                            const SizedBox(width: 4),
                            Text(
                              ride.driverRating?.toString() ?? '5.0',
                              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: availableSeats > 0 ? const Color(0xFFF3F4F6) : const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      availableSeats > 0 ? '$availableSeats мест свободно' : 'Мест нет',
                      style: TextStyle(
                        color: availableSeats > 0 ? AppTheme.textSecondary : const Color(0xFFDC2626),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBusCard(BusTicket ticket) {
    final depDate = DateTime.parse(ticket.departureDate);
    final arrDate = DateTime.parse(ticket.arrivalDate);
    final depDay = DateFormat('d MMM', 'ru').format(depDate);
    final arrDay = DateFormat('d MMM', 'ru').format(arrDate);
    final availableSeats = ticket.totalSeats - (ticket.bookedSeats?.length ?? 0);

    return GestureDetector(
      onTap: () => context.push('/bus-ticket/${ticket.id}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top row: bus type badge + price
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.directions_bus_outlined, color: Color(0xFF2563EB), size: 13),
                        const SizedBox(width: 5),
                        Text(
                          ticket.busType == 'double' ? 'Двухэтажный' : 'Автобус',
                          style: const TextStyle(color: Color(0xFF2563EB), fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFDCFCE7)),
                    ),
                    child: Text(
                      '${ticket.price.toInt()} с.',
                      style: const TextStyle(
                        color: Color(0xFF166534),
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Main route row
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Departure
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ticket.departureTime,
                          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          depDay,
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          ticket.fromCity,
                          style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ],
                    ),
                  ),
                  // Duration + arrow
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Column(
                      children: [
                        Text(
                          '${ticket.durationMinutes ~/ 60}ч ${ticket.durationMinutes % 60}м',
                          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(width: 6, height: 6, decoration: BoxDecoration(color: Colors.blue.shade100, shape: BoxShape.circle)),
                            Container(width: 28, height: 2, color: Colors.blue.shade50),
                            const Icon(Icons.arrow_forward, color: Color(0xFF2563EB), size: 16),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Arrival
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          ticket.arrivalTime,
                          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          arrDay,
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          ticket.toCity,
                          style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 15),
                          textAlign: TextAlign.right,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Bottom row: company + seats
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    ticket.transportCompany ?? 'Перевозчик',
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: availableSeats > 5
                          ? const Color(0xFFF0FDF4)
                          : availableSeats > 0
                              ? const Color(0xFFFFF7ED)
                              : const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      availableSeats > 0 ? '$availableSeats мест' : 'Мест нет',
                      style: TextStyle(
                        color: availableSeats > 5
                            ? const Color(0xFF16A34A)
                            : availableSeats > 0
                                ? const Color(0xFFEA580C)
                                : const Color(0xFFDC2626),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }


  Widget _buildRouteLine(String from, String to) {
    return Row(
      children: [
        Column(
          children: [
            const Icon(Icons.circle, color: AppTheme.primaryColor, size: 14),
            Container(width: 2, height: 24, decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(1))),
            Icon(Icons.location_on, color: Colors.grey.shade400, size: 16),
          ],
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(from, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textPrimary)),
            const SizedBox(height: 20),
            Text(to, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textPrimary)),
          ],
        ),
      ],
    );
  }

  Widget _buildSkeletonCard() {
    return Card(
      child: Container(height: 160, decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(20))),
    );
  }

  Widget _buildEmptyState(String message) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.grey.shade50, shape: BoxShape.circle),
              child: const Icon(Icons.search_off, size: 48, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            Text(message, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 18, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            const Text('Попробуйте другие параметры поиска', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}
