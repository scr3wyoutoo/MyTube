import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:flutter_browser_app/services/segmented_stream_proxy.dart';

void main() {
  test(
    'liefert offene Client-Range vollständig über begrenzte Upstream-Ranges',
    () async {
      final content = List<int>.generate(8192, (index) => index % 251);
      final receivedRanges = <String>[];
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      upstream.listen((request) async {
        final rangeHeader = request.headers.value(HttpHeaders.rangeHeader)!;
        receivedRanges.add(rangeHeader);
        final match = RegExp(r'^bytes=(\d+)-(\d+)$').firstMatch(rangeHeader)!;
        final start = int.parse(match.group(1)!);
        final end = int.parse(match.group(2)!);

        request.response
          ..statusCode = HttpStatus.partialContent
          ..contentLength = end - start + 1
          ..headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes $start-$end/${content.length}',
          )
          ..add(content.sublist(start, end + 1));
        await request.response.close();
      });

      final proxy = SegmentedStreamProxy(chunkSize: 1024);
      final client = http.Client();
      addTearDown(() async {
        client.close();
        await proxy.close();
        await upstream.close(force: true);
      });

      final remoteUri = Uri(
        scheme: 'http',
        host: InternetAddress.loopbackIPv4.address,
        port: upstream.port,
        path: '/videoplayback',
        queryParameters: {
          'clen': content.length.toString(),
          'mime': 'video/mp4',
        },
      );
      final localUri = await proxy.register(remoteUri);
      final request = http.Request('GET', localUri)
        ..headers[HttpHeaders.rangeHeader] = 'bytes=2000-';
      final response = await client.send(request);
      final body = await response.stream.toBytes();

      expect(response.statusCode, HttpStatus.partialContent);
      expect(response.headers[HttpHeaders.acceptRangesHeader], 'bytes');
      expect(
        response.headers[HttpHeaders.contentRangeHeader],
        'bytes 2000-8191/${content.length}',
      );
      expect(response.contentLength, content.length - 2000);
      expect(receivedRanges, [
        'bytes=2000-3023',
        'bytes=3024-4047',
        'bytes=4048-5071',
        'bytes=5072-6095',
        'bytes=6096-7119',
        'bytes=7120-8143',
        'bytes=8144-8191',
      ]);
      expect(body, content.sublist(2000));
    },
  );

  test(
    'liefert eine Anfrage ohne Range als vollständige 200-Antwort',
    () async {
      final content = List<int>.generate(4096, (index) => index % 197);
      final receivedRanges = <String>[];
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      upstream.listen((request) async {
        final rangeHeader = request.headers.value(HttpHeaders.rangeHeader)!;
        receivedRanges.add(rangeHeader);
        final match = RegExp(r'^bytes=(\d+)-(\d+)$').firstMatch(rangeHeader)!;
        final start = int.parse(match.group(1)!);
        final end = int.parse(match.group(2)!);
        request.response
          ..statusCode = HttpStatus.partialContent
          ..contentLength = end - start + 1
          ..headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes $start-$end/${content.length}',
          )
          ..add(content.sublist(start, end + 1));
        await request.response.close();
      });

      final proxy = SegmentedStreamProxy(chunkSize: 1024);
      final client = http.Client();
      addTearDown(() async {
        client.close();
        await proxy.close();
        await upstream.close(force: true);
      });

      final localUri = await proxy.register(
        Uri(
          scheme: 'http',
          host: InternetAddress.loopbackIPv4.address,
          port: upstream.port,
          path: '/videoplayback',
          queryParameters: {
            'clen': content.length.toString(),
            'mime': 'video/mp4',
          },
        ),
      );
      final response = await client.get(localUri);

      expect(response.statusCode, HttpStatus.ok);
      expect(response.contentLength, content.length);
      expect(response.headers[HttpHeaders.contentRangeHeader], isNull);
      expect(receivedRanges, [
        'bytes=0-1023',
        'bytes=1024-2047',
        'bytes=2048-3071',
        'bytes=3072-4095',
      ]);
      expect(response.bodyBytes, content);
    },
  );

  test('liefert Metadaten für HEAD ohne Upstream-Download', () async {
    var upstreamRequests = 0;
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((request) {
      upstreamRequests++;
      request.response.close();
    });

    final proxy = SegmentedStreamProxy();
    final client = http.Client();
    addTearDown(() async {
      client.close();
      await proxy.close();
      await upstream.close(force: true);
    });

    final remoteUri = Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: upstream.port,
      queryParameters: const {'clen': '4096', 'mime': 'audio/mp4'},
    );
    final localUri = await proxy.register(remoteUri);
    final request = http.Request('HEAD', localUri);
    final response = await client.send(request);
    await response.stream.drain<void>();

    expect(response.statusCode, HttpStatus.ok);
    expect(response.contentLength, 4096);
    expect(response.headers[HttpHeaders.contentTypeHeader], 'audio/mp4');
    expect(upstreamRequests, 0);
  });

  test('serves a registered HLS master playlist locally', () async {
    const manifest = '#EXTM3U\n#EXT-X-VERSION:6\n';
    final proxy = SegmentedStreamProxy();
    final client = http.Client();
    addTearDown(() async {
      client.close();
      await proxy.close();
    });

    final localUri = await proxy.registerText(manifest);
    final response = await client.get(localUri);

    expect(response.statusCode, HttpStatus.ok);
    expect(
      response.headers[HttpHeaders.contentTypeHeader],
      contains('mpegurl'),
    );
    expect(response.body, manifest);
  });
}
