/// An error talking to the API, with a message the app can show as is (in Spanish).
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;

  /// `null` when no response came back (no connection, timeout).
  final int? statusCode;

  @override
  String toString() => 'ApiException($statusCode): $message';
}
