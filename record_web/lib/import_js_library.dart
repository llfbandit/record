import 'dart:html' as html;

class ImportJsLibrary {
  /// Injects the library by its [url]
  void import(String content, String id) {
    if (!_isLoaded(id)) {
      final scriptTag = _createScriptTag(content, id);
      head.children.add(scriptTag);
    }
  }

  html.Element get head {
    html.Element? head = html.document.head;
    if (head == null) {
      head = html.document.createElement("head");
      html.document.append(head);
    }
    return head;
  }

  html.ScriptElement _createScriptTag(String content, String id) {
    final html.ScriptElement script = html.ScriptElement()
      ..type = "text/javascript"
      ..charset = "utf-8"
      ..id = id
      ..innerHtml = content;
    return script;
  }

  bool _isLoaded(String id) {
    for (var element in head.children) {
      if (element is html.ScriptElement) {
        if (element.id == id) {
          return true;
        }
      }
    }
    return false;
  }
}
