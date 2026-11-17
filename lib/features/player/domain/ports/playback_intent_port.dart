/// Changes even when a repeated transport command leaves playback status alone.
abstract interface class PlaybackIntentPort {
  int get playbackIntentRevision;
}
