import 'package:geolocator/geolocator.dart';

class LocationResult {
  final double lat;
  final double lng;
  final double? accuracyMeters;
  LocationResult({required this.lat, required this.lng, this.accuracyMeters});
}

class LocationService {
  /// Requests permission (if needed) and returns the device's current
  /// position. Works fully offline — GPS fix doesn't need connectivity,
  /// only the basemap tiles (cached separately) need to have been
  /// downloaded ahead of time for the map to render.
  Future<LocationResult> getCurrentLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const LocationServiceDisabledException();
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw LocationPermissionDeniedException();
      }
    }
    if (permission == LocationPermission.deniedForever) {
      throw LocationPermissionDeniedException();
    }

    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    return LocationResult(
      lat: position.latitude,
      lng: position.longitude,
      accuracyMeters: position.accuracy,
    );
  }
}

class LocationPermissionDeniedException implements Exception {
  @override
  String toString() => 'Location permission denied';
}
