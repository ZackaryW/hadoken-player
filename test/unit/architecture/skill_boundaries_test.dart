import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'skill source modules depend only on Dart and their own source folder',
    () {
      final root = Directory('lib/skills').absolute.uri;
      final files = Directory.fromUri(root)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();
      expect(files, isNotEmpty);
      final directives = RegExp(r'''(?:import|export|part)\s+[^;]+;''');
      final quoted = RegExp(r'''['"]([^'"]+)['"]''');
      for (final file in files) {
        for (final directive in directives.allMatches(
          file.readAsStringSync(),
        )) {
          for (final match in quoted.allMatches(directive.group(0)!)) {
            final uri = match.group(1)!;
            if (uri.startsWith('dart:')) continue;
            expect(
              Uri.parse(uri).hasScheme,
              isFalse,
              reason: '${file.path}: $uri',
            );
            expect(
              file.absolute.uri
                  .resolve(uri)
                  .toString()
                  .startsWith(root.toString()),
              isTrue,
              reason: '${file.path}: $uri leaves lib/skills',
            );
          }
        }
      }
    },
  );
}
