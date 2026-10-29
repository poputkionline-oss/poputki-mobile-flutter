import 'package:geolocator/geolocator.dart';

class GeoCoordinates {
  final double latitude;
  final double longitude;
  final double accuracy;
  GeoCoordinates(this.latitude, this.longitude, this.accuracy);
}

class GeoException implements Exception {
  /// 'denied' | 'action_required' | 'unavailable'
  final String code;
  GeoException(this.code);
}

/// Requests coarse coordinates. With [automatic] it never shows a permission
/// prompt: the user must press the button first.
Future<GeoCoordinates> requestCoordinates({bool automatic = false}) async {
  if (!await Geolocator.isLocationServiceEnabled()) throw GeoException('unavailable');
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    if (automatic) throw GeoException('action_required');
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
    throw GeoException('denied');
  }
  try {
    final p = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.low,
        timeLimit: Duration(seconds: 12),
      ),
    );
    return GeoCoordinates(p.latitude, p.longitude, p.accuracy);
  } catch (_) {
    throw GeoException('unavailable');
  }
}

String locationErrorMessage(Object error) {
  if (error is GeoException) {
    if (error.code == 'denied') {
      return 'Доступ к геолокации запрещён. Разрешите его в настройках или выберите город вручную.';
    }
    if (error.code == 'action_required') {
      return 'Нажмите «Определить мой город», чтобы разрешить геолокацию.';
    }
  }
  return 'Не удалось определить город. Выберите его вручную или попробуйте ещё раз.';
}
