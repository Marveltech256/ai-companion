import 'package:flutter/material.dart';

import 'dart:async';

import 'app/companion_controller.dart';
import 'application/bootstrap.dart';
import 'application/connection.dart';
import 'core/app_config.dart';
import 'core/app_failure.dart';
import 'core/live_runtime.dart';
import 'voice/voice_controller.dart';
import 'voice/voice_hardware.dart';
import 'billing/billing_controller.dart';
import 'billing/store_gateway.dart';

Future<void> main() => launchMorrow();

Future<void> launchMorrow({bool deviceOnly = false}) async {
  WidgetsFlutterBinding.ensureInitialized();
  Future<AppConnection> device() async {
    return openDeviceWorkspace();
  }

  Future<AppConnection> cloud() async {
    final config = AppConfig.fromEnvironment();
    try {
      config.validate();
    } on AppFailure {
      throw const AppFailure(
        'cloud_configuration_required',
        'Cloud connection is not configured in this build yet. Your device workspace is available.',
      );
    }
    final runtime = await LiveRuntime.connect(config)
        .timeout(const Duration(seconds: 20));
    final controller = CompanionController(
      session: runtime.session,
      api: runtime.api,
      push: runtime.push,
    );
    if (!controller.anonymousAccount) await controller.restore();
    unawaited(controller.refreshReviewGuestAvailability());
    if (controller.error != null) {
      final error = controller.error!;
      controller.dispose();
      throw error;
    }
    final voice = VoiceController(
      companion: controller,
      hardware: DeviceVoiceHardware(),
      gateway: runtime.speech,
    );
    return AppConnection(
      controller: controller,
      deviceOnly: false,
      voice: voice,
      billing: BillingController(
        companion: controller,
        store: GooglePlayStoreGateway(),
      ),
    );
  }

  runApp(
    ApplicationBootstrap(
      open: () => openInitialConnection(
        deviceOnly: deviceOnly,
        openCloud: cloud,
        openDevice: device,
      ),
      connectCloud: cloud,
      openDevice: deviceOnly ? device : null,
      requireSignIn: !deviceOnly,
    ),
  );
}
