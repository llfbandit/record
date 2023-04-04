import 'dart:async';
import 'dart:html' as html;

class ImportJsLibrary {
  /// Injects the library by its [url]
  static Future<void> import({required String url, String? flutterPluginName}) {
    if (flutterPluginName == null) {
      return _importJSLibrary(url);
    } else {
      return _importJSLibrary(_libraryUrl(url, flutterPluginName));
    }
  }

  static String _libraryUrl(String url, String pluginName) {
    if (url.startsWith("./")) {
      url = url.replaceFirst("./", "");
      return "./assets/packages/$pluginName/$url";
    }
    if (url.startsWith("assets/")) {
      return "./assets/packages/$pluginName/$url";
    } else {
      return url;
    }
  }

  static html.Element get head {
    html.Element? head = html.document.head;
    if (head == null) {
      head = html.document.createElement("head");
      html.document.append(head);
    }
    return head;
  }

  static html.ScriptElement _createScriptTag(String library) {
    final html.ScriptElement script = html.ScriptElement()
      ..type = "text/javascript"
      ..charset = "utf-8"
      ..async = true
      ..src = library;
    return script;
  }

  /// Injects a bunch of libraries in the <head> and returns a
  /// Future that resolves when all load.
  static Future<void> _importJSLibrary(String library) async {
    if (!isImported(library)) {
      final scriptTag = _createScriptTag(library);
      head.children.add(scriptTag);
      await scriptTag.onLoad.first;
    }
  }

  static bool _isLoaded(String url) {
    if (url.startsWith("./")) {
      url = url.replaceFirst("./", "");
    }
    for (var element in head.children) {
      if (element is html.ScriptElement) {
        if (element.src.endsWith(url)) {
          return true;
        }
      }
    }
    return false;
  }

  static bool isImported(String url) {
    return _isLoaded(url);
  }
}
