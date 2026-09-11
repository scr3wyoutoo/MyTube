class SegmentedStreamProxy {
  SegmentedStreamProxy({
    Map<String, String> upstreamHeaders = const {},
    int chunkSize = 2 * 1024 * 1024,
  });

  bool get isSupported => false;

  String? get lastErrorDetails => null;

  void clearLastError() {}

  Future<Uri> register(Uri remoteUri) async => remoteUri;

  Future<Uri> registerText(
    String content, {
    String contentType = 'application/vnd.apple.mpegurl',
  }) async => Uri.dataFromString(content, mimeType: contentType);

  Future<void> close() async {}
}
