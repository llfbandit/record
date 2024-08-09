import 'package:web/web.dart' as web;
import 'dart:js_util' as js_util;

class ImportJsLibrary {
  /// Injects the library by its [url]
  void import(String content, String id) {
    if (!_isLoaded(id)) {
      final scriptTag = _createScriptTag(content, id);
      head.appendChild(scriptTag);
    }
  }

  web.Element get head {
    web.Element? head = web.document.head;
    if (head == null) {
      head = web.document.createElement("head");
      web.document.append(head);
    }
    return head;
  }

  web.HTMLScriptElement _createScriptTag(String content, String id) {
    final web.HTMLScriptElement script = web.HTMLScriptElement()
      ..type = "text/javascript"
      ..charset = "utf-8"
      ..id = id
      ..innerHTML = js_util.jsify(content); // Use jsify to convert
    return script;
  }

  bool _isLoaded(String id) {
    for (var i = 0; i < head.children.length; i++) {
      final element = head.children.item(i);

      if (element is web.HTMLScriptElement) {
        if (element.id == id) {
          return true;
        }
      }
    }
    return false;
  }
}
