import 'package:flutter/material.dart';

import 'app/morrow_app.dart';
import 'design/scene.dart';

/// Archived visual reference only. This is not the shipped application.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MorrowApp(library: await DesignLibrary.load(), reviewMode: true));
}
