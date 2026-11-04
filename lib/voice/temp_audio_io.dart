import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

Future<Directory> _directory() async => Directory(
  '${(await getTemporaryDirectory()).path}${Platform.pathSeparator}morrow_voice',
);
Future<String?> writeSpeech(Uint8List bytes) async {
  final directory = await _directory();
  await directory.create(recursive: true);
  final file = File(
    '${directory.path}${Platform.pathSeparator}${const Uuid().v4()}.${bytes.length >= 4 && String.fromCharCodes(bytes.take(4)) == 'RIFF' ? 'wav' : 'mp3'}',
  );
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

Future<void> removeSpeech(String path) async {
  final directory = await _directory();
  final file = File(path);
  if (file.parent.absolute.path != directory.absolute.path ||
      !RegExp(r'^[a-f0-9-]{36}\.(mp3|wav)$')
          .hasMatch(file.uri.pathSegments.last)) {
    throw StateError('Audio cleanup is limited to owned temporary clips.');
  }
  if (await file.exists()) await file.delete();
}

Future<void> cleanupSpeech() async {
  final directory = await _directory();
  if (!await directory.exists()) return;
  await for (final item in directory.list(followLinks: false)) {
    if (item is File &&
        RegExp(r'^[a-f0-9-]{36}\.(mp3|wav)$')
            .hasMatch(item.uri.pathSegments.last)) {
      await removeSpeech(item.path);
    }
  }
}
