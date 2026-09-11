import 'package:flutter_browser_app/utils/playlist_preparation_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('commits the next video before asynchronous preparation starts', () {
    final gate = PlaylistPreparationGate();

    final ticket = gate.begin('next-video');

    expect(gate.activeVideoId, 'next-video');
    expect(gate.isPreparing('next-video'), isTrue);
    expect(gate.isActive(ticket), isTrue);
  });

  test('an obsolete preparation cannot clear its successor', () {
    final gate = PlaylistPreparationGate();
    final obsolete = gate.begin('first-next-video');
    final current = gate.begin('second-next-video');

    expect(gate.complete(obsolete), isFalse);
    expect(gate.isActive(current), isTrue);
    expect(gate.complete(current), isTrue);
    expect(gate.activeVideoId, isNull);
  });
}
