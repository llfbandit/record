# record Windows

Windows specific implementation for record package called by record_platform_interface.

## Native tests

Run from the example app (`record/example`):

```shell
flutter build windows --debug
cmake -S windows -B build/windows/x64 -Dinclude_record_windows_tests=ON
cmake --build build/windows/x64 --config Debug --target record_windows_test
build\windows\x64\plugins\record_windows\Debug\record_windows_test.exe
```
