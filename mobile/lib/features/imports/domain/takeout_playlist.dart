class TakeoutPlaylist {
  const TakeoutPlaylist({
    required this.name,
    required this.sourceIds,
    this.invalidRows = 0,
  });

  final String name;
  final List<String> sourceIds;
  final int invalidRows;
}

class TakeoutFailure implements Exception {
  const TakeoutFailure(this.message);
  final String message;
}
