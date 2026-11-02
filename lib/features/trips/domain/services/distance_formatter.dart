/// Trip distances are stored and passed around in metres; only display code
/// converts to kilometres, through this function.
String formatKilometers(double meters) =>
    '${(meters / 1000).toStringAsFixed(1)} km';
