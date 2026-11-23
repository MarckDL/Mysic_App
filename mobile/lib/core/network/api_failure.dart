/// Un fallo al pedir datos a YouTube Music o al catálogo público, ya con un
/// mensaje listo para mostrar.
class ApiFailure implements Exception {
  const ApiFailure(this.message, {this.statusCode, this.code, this.retryAfter});
  final String message;
  final int? statusCode;
  final String? code;
  final Duration? retryAfter;
}
