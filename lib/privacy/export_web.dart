import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

Future<void> downloadExport(String json) async {
  final blob = web.Blob(
    [json.toJS].toJS,
    web.BlobPropertyBag(type: 'application/json'),
  );
  final url = web.URL.createObjectURL(blob);
  final link = web.HTMLAnchorElement()
    ..href = url
    ..download = 'ai-companion-your-story.json';
  web.document.body?.append(link);
  link.click();
  link.remove();
  Timer(const Duration(seconds: 5), () => web.URL.revokeObjectURL(url));
}
