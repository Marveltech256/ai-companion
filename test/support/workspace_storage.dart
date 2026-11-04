import 'package:ai_companion/data/device_workspace.dart';

class MemoryWorkspaceStorage implements WorkspaceStorage {
  String? value;
  bool failWrites = false;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async {
    if (failWrites) throw StateError('Storage is unavailable');
    this.value = value;
  }

  @override
  Future<void> remove() async {
    value = null;
  }
}
