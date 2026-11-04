import '../app/companion_controller.dart';
import '../data/device_workspace.dart';
import '../voice/voice_controller.dart';
import '../billing/billing_controller.dart';

class AppConnection {
  AppConnection({
    required this.controller,
    required this.deviceOnly,
    this.voice,
    this.billing,
    this.closeSession,
  });
  final CompanionController controller;
  final VoiceController? voice;
  final BillingController? billing;
  final bool deviceOnly;
  final Future<void> Function()? closeSession;
  Future<void> dispose() async {
    await voice?.stop();
    voice?.dispose();
    billing?.dispose();
    controller.dispose();
    await closeSession?.call();
  }
}

/// Normal startup always opens the required account experience. Device-only
/// entry points exist for development previews, separate from the shipped app.
Future<AppConnection> openInitialConnection({
  required bool deviceOnly,
  required Future<AppConnection> Function() openCloud,
  required Future<AppConnection> Function() openDevice,
}) async {
  if (deviceOnly) {
    return openDevice();
  }
  return openCloud();
}

Future<AppConnection> openDeviceWorkspace({WorkspaceStorage? storage}) async {
  final api = DeviceWorkspaceApi(storage ?? SecureWorkspaceStorage());
  await api.open();
  final session = DeviceSession();
  final controller = CompanionController(
    session: session,
    api: api,
    journalOnly: true,
  );
  await controller.restore();
  return AppConnection(
    controller: controller,
    deviceOnly: true,
    closeSession: session.dispose,
  );
}
