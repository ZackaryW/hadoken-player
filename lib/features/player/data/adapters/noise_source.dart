import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';

/// A short loopable PCM source in the app cache, generated without media access.
Future<Uri> createNoiseSource() async {
  final directory = await getTemporaryDirectory();
  final file = File('${directory.path}/hadoken-skill-noise-v1.wav');
  if (await file.exists()) return file.uri;
  const rate = 48000;
  const frames = rate * 2;
  final data = ByteData(44 + frames * 2);
  void text(int at, String value) {
    for (var i = 0; i < value.length; i++) {
      data.setUint8(at + i, value.codeUnitAt(i));
    }
  }

  text(0, 'RIFF');
  data.setUint32(4, 36 + frames * 2, Endian.little);
  text(8, 'WAVE');
  text(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, rate, Endian.little);
  data.setUint32(28, rate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  text(36, 'data');
  data.setUint32(40, frames * 2, Endian.little);
  final random = Random(17);
  for (var i = 0; i < frames; i++) {
    data.setInt16(
      44 + i * 2,
      ((random.nextDouble() * 2 - 1) * 10000).round(),
      Endian.little,
    );
  }
  await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
  return file.uri;
}
