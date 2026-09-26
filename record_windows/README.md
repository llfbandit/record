# record Windows

Windows specific implementation for record package called by record_platform_interface.

## Native tests

Run from the example app (`record/example`), which builds the plugin from source:

```shell
# Run once to generate project files.
flutter build windows --debug
# Turn the tests on; app builds leave them off, so only this build downloads googletest.
cmake -S windows -B build/windows/x64 -Dinclude_record_windows_tests=ON
# Build plugin sources and tests.
cmake --build build/windows/x64 --config Debug --target record_windows_test
# Run tests
build\windows\x64\plugins\record_windows\Debug\record_windows_test.exe
```
