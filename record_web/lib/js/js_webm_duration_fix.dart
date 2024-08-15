import 'dart:js_interop';

import 'package:web/web.dart' as web;

@JS('jsFixWebmDuration')
external JSPromise<web.Blob> fixWebmDuration(
  web.Blob blob,
  JSNumber duration,
);

String jsFixWebmDurationContentId() => 'fix-webm-duration';
