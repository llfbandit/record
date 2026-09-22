# record web

Web specific implementation for record package called by record_platform_interface.

When sample rate is not supported natively, the package resamples the buffers in audio thread.

## Tests

Tests run in a real browser, so they need a WebDriver server.
See https://docs.flutter.dev/testing/integration-tests#test-in-a-web-browser

If Chrome and chromedriver are already installed, skip to step 3.

1. Install both in one command so their versions match. Always pass `--path`, or npx downloads them into the current folder.

```
npx @puppeteer/browsers install chrome@stable chromedriver@stable --path <dir>
```

2. Note the two paths the command prints: each program lands in its own subfolder.

3. Start the driver, on the port expected by `flutter drive`:

```
<path/to/chromedriver> --port=4444
```

4. Run the tests:

```
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/route_change_test.dart \
  -d web-server --browser-name=chrome \
  --chrome-binary=<path/to/chrome>
```

Omit `--chrome-binary` when Chrome is installed system-wide.
