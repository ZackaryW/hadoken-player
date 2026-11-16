import 'package:flutter/services.dart';
import 'package:troona/features/library/domain/entities/track.dart';

final class AndroidMediaAccess {
  static const channel = MethodChannel('com.hadoken.player/media_access');
  const AndroidMediaAccess();
  Future<bool> canRead(Track track) async =>
      await channel.invokeMethod<bool>('canRead', {
        'uri': track.uri.isNotEmpty
            ? track.uri
            : Uri.file(track.path).toString(),
      }) ??
      false;
}
