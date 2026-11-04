import '../core/app_failure.dart';

Future<void> downloadExport(String json) async {
  throw const AppFailure(
    'export_unavailable',
    'Download your export from Ai Companion in a browser.',
  );
}
