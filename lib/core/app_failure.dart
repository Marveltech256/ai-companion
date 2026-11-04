class AppFailure implements Exception {
  const AppFailure(this.code, this.message, {this.retryable = false});
  final String code;
  final String message;
  final bool retryable;
  @override
  String toString() => 'AppFailure($code): $message';
}
