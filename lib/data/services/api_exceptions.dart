class ApiConfigurationException implements Exception {
  final String message;

  const ApiConfigurationException(this.message);

  @override
  String toString() => message;
}

class ApiAuthException implements Exception {
  final String message;

  const ApiAuthException(this.message);

  @override
  String toString() => message;
}
