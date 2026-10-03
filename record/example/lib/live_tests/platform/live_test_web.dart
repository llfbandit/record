String get osVersion => 'web';

// The browser ignores the path.
Future<String> tempPath(String name) async => name;

// The file is a blob in the browser. We do not read it.
Future<double?> wavSeconds(String path) async => null;
