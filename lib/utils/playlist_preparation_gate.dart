class PlaylistPreparationTicket {
  const PlaylistPreparationTicket._({
    required this.videoId,
    required this.serial,
  });

  final String videoId;
  final int serial;
}

class PlaylistPreparationGate {
  PlaylistPreparationTicket? _activeTicket;
  int _nextSerial = 0;

  String? get activeVideoId => _activeTicket?.videoId;

  bool isPreparing(String videoId) => activeVideoId == videoId;

  PlaylistPreparationTicket begin(String videoId) {
    final ticket = PlaylistPreparationTicket._(
      videoId: videoId,
      serial: ++_nextSerial,
    );
    _activeTicket = ticket;
    return ticket;
  }

  bool isActive(PlaylistPreparationTicket ticket) =>
      identical(_activeTicket, ticket);

  bool complete(PlaylistPreparationTicket ticket) {
    if (!isActive(ticket)) {
      return false;
    }
    _activeTicket = null;
    return true;
  }

  void cancel() {
    _activeTicket = null;
  }
}
