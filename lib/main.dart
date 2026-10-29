import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'theme/app_theme.dart';
import 'services/search_provider.dart';
import 'services/auth_provider.dart';
import 'screens/search_results_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/ride_details_screen.dart';
import 'screens/ride_seat_selection_screen.dart';
import 'screens/bus_ticket_details_screen.dart';
import 'screens/bus_booking_screen.dart';
import 'screens/vehicle_screen.dart';
import 'screens/create_ride_screen.dart';
import 'screens/my_rides_screen.dart';
import 'screens/my_tickets_screen.dart';
import 'screens/user_profile_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/my_reviews_screen.dart';
import 'widgets/main_shell.dart';

"Ронандаи гироми фалончи. Сервиси poputki.online барои Шумо мусофир дарефт кард. Лутфан барои тамос бо мусофир "

import 'package:intl/date_symbol_data_local.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ru', null);
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => SearchProvider()),
      ],
      child: const PoputkiApp(),
    ),
  );
}

class PoputkiApp extends StatefulWidget {
  const PoputkiApp({super.key});

  @override
  State<PoputkiApp> createState() => _PoputkiAppState();
}

class _PoputkiAppState extends State<PoputkiApp> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    _router = GoRouter(
      initialLocation: '/',
      refreshListenable: authProvider,
      redirect: (context, state) {
        final isAuthenticated = authProvider.isAuthenticated;
        final isAuthPath = state.matchedLocation == '/auth';

        if (!isAuthenticated) {
          return '/auth';
        }

        if (isAuthenticated && isAuthPath) {
          return '/';
        }

        return null;
      },
      routes: [
        ShellRoute(
          builder: (context, state, child) => MainShell(child: child),
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) => const SearchResultsScreen(),
            ),
            GoRoute(
              path: '/my-rides',
              builder: (context, state) => const MyRidesScreen(),
            ),
            GoRoute(
              path: '/profile',
              builder: (context, state) => const ProfileScreen(),
            ),
            GoRoute(
              path: '/create',
              builder: (context, state) => const CreateRideScreen(),
            ),
            GoRoute(
              path: '/my-tickets',
              builder: (context, state) => const MyTicketsScreen(),
            ),
          ],
        ),
        GoRoute(
          path: '/auth',
          builder: (context, state) => const AuthScreen(),
        ),
        GoRoute(
          path: '/ride/:id',
          builder: (context, state) => RideDetailsScreen(rideId: state.pathParameters['id']!),
        ),
        GoRoute(
          path: '/ride/:id/select-seat',
          builder: (context, state) => RideSeatSelectionScreen(rideId: state.pathParameters['id']!),
        ),
        GoRoute(
          path: '/bus-ticket/:id',
          builder: (context, state) => BusTicketDetailsScreen(ticketId: state.pathParameters['id']!),
        ),
        GoRoute(
          path: '/bus-booking/:id',
          builder: (context, state) => BusBookingScreen(
            ticketId: state.pathParameters['id']!,
          ),
        ),
        GoRoute(
          path: '/vehicle',
          builder: (context, state) => const VehicleScreen(),
        ),
        GoRoute(
          path: '/user-profile/:id',
          builder: (context, state) => UserProfileScreen(userId: state.pathParameters['id']!),
        ),
        GoRoute(
          path: '/my-reviews',
          builder: (context, state) => const MyReviewsScreen(),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsScreen(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Poputki.online',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      routerConfig: _router,
    );
  }
}
