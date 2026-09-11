import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'app_log.dart';

/// Delivers large, adaptive media streams to the native player in bounded
/// byte ranges. Some Googlevideo endpoints throttle or reject the open-ended
/// range requests used by native players.
class SegmentedStreamProxy {
  SegmentedStreamProxy({
    Map<String, String> upstreamHeaders = const {},
    this.chunkSize = 2 * 1024 * 1024,
  }) : assert(chunkSize > 0),
       _upstreamHeaders = Map.unmodifiable(upstreamHeaders);

  final int chunkSize;
  final Map<String, String> _upstreamHeaders;
  final http.Client _client = http.Client();
  final Map<String, _ProxySource> _sources = {};
  final Map<Uri, Uri> _localUris = {};
  final Map<String, _StaticSource> _staticSources = {};

  HttpServer? _server;
  int _nextSourceId = 0;
  bool _closed = false;
  String? _lastErrorDetails;

  bool get isSupported => true;

  String? get lastErrorDetails => _lastErrorDetails;

  void clearLastError() => _lastErrorDetails = null;

  Future<Uri> register(Uri remoteUri) async {
    if (_closed) {
      throw StateError('Der lokale Stream-Proxy wurde bereits geschlossen.');
    }
    if (remoteUri.scheme != 'https' && remoteUri.scheme != 'http') {
      throw ArgumentError.value(
        remoteUri,
        'remoteUri',
        'Nur HTTP(S)-Streams werden unterstützt.',
      );
    }

    final existing = _localUris[remoteUri];
    if (existing != null) {
      return existing;
    }

    final contentLength = int.tryParse(remoteUri.queryParameters['clen'] ?? '');
    if (contentLength == null || contentLength <= 0) {
      throw FormatException(
        'Der adaptive Stream enthält keine gültige Inhaltslänge.',
        remoteUri.host,
      );
    }

    final server = await _ensureServer();
    final sourceId = (++_nextSourceId).toString();
    final source = _ProxySource(
      remoteUri: remoteUri,
      contentLength: contentLength,
      contentType:
          remoteUri.queryParameters['mime'] ?? 'application/octet-stream',
    );
    _sources[sourceId] = source;

    final localUri = Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      pathSegments: ['stream', sourceId],
    );
    _localUris[remoteUri] = localUri;
    return localUri;
  }

  Future<Uri> registerText(
    String content, {
    String contentType = 'application/vnd.apple.mpegurl',
  }) async {
    if (_closed) {
      throw StateError('Der lokale Stream-Proxy wurde bereits geschlossen.');
    }
    final server = await _ensureServer();
    final sourceId = (++_nextSourceId).toString();
    _staticSources[sourceId] = _StaticSource(
      bytes: utf8.encode(content),
      contentType: contentType,
    );
    return Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      pathSegments: ['manifest', sourceId],
    );
  }

  Future<HttpServer> _ensureServer() async {
    final running = _server;
    if (running != null) {
      return running;
    }
    final server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
      shared: false,
    );
    server.listen(_handleRequest, cancelOnError: false);
    _server = server;
    AppLog.instance.info(
      'stream_proxy.started',
      fields: {'port': server.port, 'chunkBytes': chunkSize},
    );
    return server;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    if (request.uri.pathSegments case ['manifest', final sourceId]) {
      await _handleStaticRequest(request, sourceId);
      return;
    }

    var responseStarted = false;
    _ProxySource? source;
    _ByteRange? byteRange;

    try {
      source = _sourceFor(request.uri);
      _setCommonHeaders(request.response, source);

      if (request.method == 'HEAD') {
        request.response
          ..statusCode = HttpStatus.ok
          ..contentLength = source.contentLength;
        responseStarted = true;
        await request.response.close();
        return;
      }
      if (request.method != 'GET') {
        request.response
          ..statusCode = HttpStatus.methodNotAllowed
          ..headers.set(HttpHeaders.allowHeader, 'GET, HEAD');
        responseStarted = true;
        await request.response.close();
        return;
      }

      final requestedRange = _parseRequestedRange(
        request.headers.value(HttpHeaders.rangeHeader),
        source.contentLength,
      );
      byteRange = _nextUpstreamRange(requestedRange.start, requestedRange.end);
      var upstream = await _requestUpstreamRange(source, byteRange);

      final response = request.response
        ..statusCode = requestedRange.isPartial
            ? HttpStatus.partialContent
            : HttpStatus.ok
        ..contentLength = requestedRange.length
        ..bufferOutput = false;
      if (requestedRange.isPartial) {
        response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes ${requestedRange.start}-${requestedRange.end}/'
          '${source.contentLength}',
        );
      }
      responseStarted = true;

      var nextStart = requestedRange.start;
      while (nextStart <= requestedRange.end) {
        byteRange = _nextUpstreamRange(nextStart, requestedRange.end);
        if (nextStart != requestedRange.start) {
          upstream = await _requestUpstreamRange(source, byteRange);
        }
        await _writeExactBytes(
          response,
          upstream.stream,
          byteRange.length,
          source,
          byteRange,
        );
        await response.flush();
        nextStart = byteRange.end + 1;
      }
      await response.close();
    } on _InvalidRange catch (error) {
      _recordError(error, source: source, range: byteRange);
      final response = request.response;
      response
        ..statusCode = HttpStatus.requestedRangeNotSatisfiable
        ..headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes */${source?.contentLength ?? 0}',
        );
      await response.close();
    } on Object catch (error, stackTrace) {
      _recordError(
        error,
        stackTrace: stackTrace,
        source: source,
        range: byteRange,
      );
      if (!responseStarted) {
        request.response
          ..statusCode = HttpStatus.badGateway
          ..headers.contentType = ContentType.text
          ..write('Der externe Videostream konnte nicht geladen werden.');
      }
      try {
        await request.response.close();
      } on Object {
        // Der Player kann eine laufende Range-Anfrage beim Springen abbrechen.
      }
    }
  }

  Future<void> _handleStaticRequest(
    HttpRequest request,
    String sourceId,
  ) async {
    final source = _staticSources[sourceId];
    if (source == null) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    if (request.method != 'GET' && request.method != 'HEAD') {
      request.response
        ..statusCode = HttpStatus.methodNotAllowed
        ..headers.set(HttpHeaders.allowHeader, 'GET, HEAD');
      await request.response.close();
      return;
    }

    request.response
      ..statusCode = HttpStatus.ok
      ..contentLength = source.bytes.length
      ..headers.set(HttpHeaders.contentTypeHeader, source.contentType)
      ..headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    if (request.method == 'GET') {
      request.response.add(source.bytes);
    }
    await request.response.close();
  }

  _ProxySource _sourceFor(Uri requestUri) {
    final segments = requestUri.pathSegments;
    if (segments.length != 2 || segments.first != 'stream') {
      throw const HttpException('Unbekannter lokaler Stream-Pfad.');
    }
    final source = _sources[segments.last];
    if (source == null) {
      throw const HttpException('Der lokale Stream ist nicht registriert.');
    }
    return source;
  }

  void _setCommonHeaders(HttpResponse response, _ProxySource source) {
    response.headers
      ..set(HttpHeaders.acceptRangesHeader, 'bytes')
      ..set(HttpHeaders.contentTypeHeader, source.contentType)
      ..set(HttpHeaders.cacheControlHeader, 'no-store');
  }

  _RequestedRange _parseRequestedRange(String? header, int contentLength) {
    var start = 0;
    var requestedEnd = contentLength - 1;
    final isPartial = header != null && header.trim().isNotEmpty;
    if (isPartial) {
      final match = RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(header.trim());
      if (match == null) {
        throw _InvalidRange('Nicht unterstützter Range-Header: $header');
      }
      start = int.tryParse(match.group(1)!) ?? -1;
      final endText = match.group(2)!;
      if (endText.isNotEmpty) {
        requestedEnd = int.tryParse(endText) ?? -1;
      }
    }
    if (start < 0 || start >= contentLength || requestedEnd < start) {
      throw _InvalidRange('Ungültiger Byte-Bereich: $header');
    }
    if (requestedEnd >= contentLength) {
      requestedEnd = contentLength - 1;
    }
    return _RequestedRange(start, requestedEnd, isPartial: isPartial);
  }

  _ByteRange _nextUpstreamRange(int start, int requestedEnd) {
    final chunkEnd = start + chunkSize - 1;
    final end = requestedEnd < chunkEnd ? requestedEnd : chunkEnd;
    return _ByteRange(start, end);
  }

  Future<http.StreamedResponse> _requestUpstreamRange(
    _ProxySource source,
    _ByteRange range,
  ) async {
    final upstreamRequest = http.Request('GET', source.remoteUri);
    upstreamRequest.headers.addAll(_upstreamHeaders);
    upstreamRequest.headers
      ..remove(HttpHeaders.hostHeader)
      ..remove(HttpHeaders.contentLengthHeader)
      ..remove(HttpHeaders.rangeHeader)
      ..[HttpHeaders.acceptEncodingHeader] = 'identity'
      ..[HttpHeaders.rangeHeader] = range.headerValue;

    final upstream = await _client
        .send(upstreamRequest)
        .timeout(const Duration(seconds: 15));
    if (upstream.statusCode != HttpStatus.ok &&
        upstream.statusCode != HttpStatus.partialContent) {
      unawaited(upstream.stream.drain<void>());
      throw HttpException(
        'Googlevideo antwortete mit HTTP ${upstream.statusCode}.',
        uri: Uri(scheme: source.remoteUri.scheme, host: source.remoteUri.host),
      );
    }
    if (upstream.statusCode == HttpStatus.ok && range.start != 0) {
      unawaited(upstream.stream.drain<void>());
      throw HttpException(
        'Googlevideo hat den angeforderten Byte-Bereich nicht berücksichtigt.',
        uri: Uri(scheme: source.remoteUri.scheme, host: source.remoteUri.host),
      );
    }
    return upstream;
  }

  Future<void> _writeExactBytes(
    HttpResponse response,
    Stream<List<int>> source,
    int expectedBytes,
    _ProxySource proxySource,
    _ByteRange range,
  ) async {
    var remaining = expectedBytes;
    await for (final chunk in source) {
      if (remaining <= 0) {
        break;
      }
      if (chunk.length <= remaining) {
        response.add(chunk);
        remaining -= chunk.length;
      } else {
        response.add(chunk.sublist(0, remaining));
        remaining = 0;
      }
    }
    if (remaining != 0) {
      throw HttpException(
        'Googlevideo lieferte für ${range.headerValue} '
        '$remaining Bytes zu wenig.',
        uri: Uri(
          scheme: proxySource.remoteUri.scheme,
          host: proxySource.remoteUri.host,
        ),
      );
    }
  }

  void _recordError(
    Object error, {
    StackTrace? stackTrace,
    _ProxySource? source,
    _ByteRange? range,
  }) {
    final details = StringBuffer('SegmentedStreamProxy');
    if (source != null) {
      details
        ..writeln()
        ..write(
          'Upstream: ${source.remoteUri.scheme}://${source.remoteUri.host}',
        );
    }
    if (range != null) {
      details
        ..writeln()
        ..write('Range: ${range.headerValue}');
    }
    details
      ..writeln()
      ..write('${error.runtimeType}: $error');
    if (stackTrace != null) {
      details
        ..writeln()
        ..write(stackTrace);
    }
    _lastErrorDetails = details.toString();
    AppLog.instance.error(
      'stream_proxy.request.failed',
      error: error,
      stackTrace: stackTrace,
      fields: {
        if (source != null) 'upstreamHost': source.remoteUri.host,
        if (range != null) 'range': range.headerValue,
        if (source != null) 'contentLength': source.contentLength,
      },
    );
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    AppLog.instance.info(
      'stream_proxy.closed',
      fields: {
        'streamSources': _sources.length,
        'manifestSources': _staticSources.length,
      },
    );
    _closed = true;
    _client.close();
    await _server?.close(force: true);
    _sources.clear();
    _localUris.clear();
    _staticSources.clear();
  }
}

class _StaticSource {
  const _StaticSource({required this.bytes, required this.contentType});

  final List<int> bytes;
  final String contentType;
}

class _ProxySource {
  const _ProxySource({
    required this.remoteUri,
    required this.contentLength,
    required this.contentType,
  });

  final Uri remoteUri;
  final int contentLength;
  final String contentType;
}

class _ByteRange {
  const _ByteRange(this.start, this.end);

  final int start;
  final int end;

  int get length => end - start + 1;

  String get headerValue => 'bytes=$start-$end';
}

class _RequestedRange extends _ByteRange {
  const _RequestedRange(super.start, super.end, {required this.isPartial});

  final bool isPartial;
}

class _InvalidRange implements Exception {
  const _InvalidRange(this.message);

  final String message;

  @override
  String toString() => message;
}
