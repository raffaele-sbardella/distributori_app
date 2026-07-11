import 'package:geolocator/geolocator.dart';

/// Esito possibile di una richiesta di posizione.
/// Un enum invece di un bool: cosi' la UI sa ESATTAMENTE cosa mostrare.
enum LocationStatus {
  ok,
  serviceDisabled,          // GPS spento a livello di sistema operativo
  permissionDenied,         // negato, ma puoi richiederlo di nuovo
  permissionDeniedForever,  // negato "per sempre": serve andare nelle impostazioni
  error,                    // fallimento imprevisto
}

class LocationResult {
  final Position? position;
  final LocationStatus status;
  const LocationResult(this.status, [this.position]);

  bool get isOk => status == LocationStatus.ok && position != null;
}

/// Risultato del controllo di prossimita' a un distributore.
/// Alimenta PriceReport.createMap(...).
class ProximityResult {
  final bool gpsVerified;       // l'utente e' entro la soglia?
  final double? distanceMeters;
  final LocationStatus status;
  const ProximityResult({
    required this.gpsVerified,
    required this.distanceMeters,
    required this.status,
  });
}

class LocationService {
  /// Soglia di prossimita'. 50 m e' un compromesso: il GPS urbano sbaglia
  /// facilmente di 10-30 m, quindi un valore troppo stretto darebbe falsi
  /// "sei lontano" a gente davvero davanti al distributore (D6).
  static const double proximityThresholdMeters = 50;

  /// Ottiene la posizione gestendo TUTTA la scala dei permessi.
  Future<LocationResult> getCurrentPosition() async {
    try {
      // 1) Il GPS e' acceso a livello di sistema?
      final serviceOn = await Geolocator.isLocationServiceEnabled();
      if (!serviceOn) {
        return const LocationResult(LocationStatus.serviceDisabled);
      }

      // 2) Che permesso abbiamo ORA?
      LocationPermission perm = await Geolocator.checkPermission();

      // 3) Se e' negato (ma non "per sempre"), CHIEDILO.
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }

      // 4) Negato per sempre -> requestPermission() non mostra piu' NESSUN
      //    popup: il sistema lo ignora in silenzio. La UI deve mandare alle
      //    impostazioni, o l'utente resta bloccato senza capire perche'.
      if (perm == LocationPermission.deniedForever) {
        return const LocationResult(LocationStatus.permissionDeniedForever);
      }

      // 5) Ancora negato dopo la richiesta.
      if (perm == LocationPermission.denied) {
        return const LocationResult(LocationStatus.permissionDenied);
      }

      // 6) Permesso concesso: prendi la posizione.
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      return LocationResult(LocationStatus.ok, pos);
    } catch (e) {
      // Qualsiasi fallimento hardware/imprevisto finisce qui, senza crash.
      return const LocationResult(LocationStatus.error);
    }
  }

  /// Verifica se l'utente e' abbastanza vicino a un distributore.
  Future<ProximityResult> checkProximity({
    required double machineLat,
    required double machineLng,
  }) async {
    final loc = await getCurrentPosition();

    if (!loc.isOk) {
      // Nessuna posizione: il report resta possibile ma NON verificato
      // (pesera' 0.3). Propaghiamo lo status per informare la UI.
      return ProximityResult(
        gpsVerified: false,
        distanceMeters: null,
        status: loc.status,
      );
    }

    // distanceBetween e' statica e restituisce METRI (calcolo geodetico).
    final meters = Geolocator.distanceBetween(
      loc.position!.latitude,
      loc.position!.longitude,
      machineLat,
      machineLng,
    );

    return ProximityResult(
      gpsVerified: meters <= proximityThresholdMeters,
      distanceMeters: meters,
      status: LocationStatus.ok,
    );
  }
}
