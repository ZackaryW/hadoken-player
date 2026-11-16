/// Session replacement/stop notifications, distinct from track/queue edits.
abstract interface class PlaybackSessionLifecycle {
  int get sessionGeneration;
  Stream<int> get sessionGenerations;
}
