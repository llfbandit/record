import 'dart:html';
import 'dart:js';

import 'package:js/js.dart';

@JS('fixWebmDuration')
external dynamic fixWebmDuration(Blob blob, [JsObject options]);