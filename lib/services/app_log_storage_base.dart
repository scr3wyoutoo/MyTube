abstract interface class AppLogStorage {
  Future<void> append(String value, {required int maxBytes});

  Future<String> read();

  Future<void> clear();
}
