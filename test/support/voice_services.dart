import 'dart:async';
import 'dart:typed_data';

import 'package:ai_companion/voice/voice_hardware.dart';
import 'package:ai_companion/voice/speech_gateway.dart';

class TestVoiceHardware implements VoiceHardware {
  bool allowed = true;
  int permissionRequests = 0, stops = 0, plays = 0;
  var chunks = StreamController<Uint8List>();
  Completer<void>? playback;
  @override
  Future<bool> permission() async {
    permissionRequests++;
    return allowed;
  }

  @override
  Future<Stream<Uint8List>> record() async {
    if (chunks.isClosed) chunks = StreamController<Uint8List>();
    return chunks.stream;
  }

  @override
  Future<void> finishRecording() async {
    await chunks.close();
  }

  @override
  Future<void> play(Uint8List bytes) async {
    plays++;
    await playback?.future;
  }

  @override
  Future<void> stop() async {
    stops++;
    if (playback?.isCompleted == false) playback!.complete();
  }

  @override
  Future<void> dispose() async {
    if (!chunks.isClosed) await chunks.close();
  }
}

class TestSpeechGateway implements SpeechGateway {
  Uint8List? received;
  Completer<String>? pending;
  final spoken = <String>[];
  @override
  Future<String> transcribe(Uint8List wave) async {
    received = Uint8List.fromList(wave);
    return pending == null ? 'I enjoy cycling.' : pending!.future;
  }

  @override
  Future<List<Uint8List>> speech(String id) async {
    spoken.add(id);
    return [
      Uint8List.fromList([1, 2, 3]),
    ];
  }

  @override
  void close() {}
}
