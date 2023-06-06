import 'dart:html';
import 'dart:js';

import 'package:js/js.dart';

@JS('jsFixWebmDuration')
external dynamic fixWebmDuration(Blob blob, num duration, JsObject options);
