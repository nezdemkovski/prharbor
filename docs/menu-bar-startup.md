# Обычный запуск только в строке меню

При расследовании был найден один процесс из Xcode Debug, PID 83758. Он одновременно показывал status item / popover и отдельное окно `timeline-preview`. Причина — прежние безусловные настройки Debug: activation policy `.regular` и `.defaultLaunchBehavior(.presented)`.

Исправление:

- Debug и Release по умолчанию используют `.accessory`: без Dock icon.
- Окно разработки не открывается автоматически и не восстанавливается после перезапуска. Settings scene тоже не открывается и не восстанавливается автоматически.
- Отдельные development windows доступны только при явном `PULLBAR_PREVIEW=1` (mock preview) или `PULLBAR_DEBUG_WINDOW=1` (live diagnostics). В Release эти flags игнорируются.

Проверка: **65 tests / 11 suites passed**, `/tmp/prharbor-startup-test.log`. Новый integration test проверяет activation policy настоящего Debug test-host и отсутствие видимого самостоятельного окна. Debug в пользовательском Xcode DerivedData и Release успешно собраны; sandboxed ad hoc signatures проверены. `git diff --check` прошёл.

Старый экземпляр закрыт через ⌘Q. Запущена обновлённая Debug-сборка из той же папки Xcode: PID **85538**. Process inventory подтвердил один экземпляр PRHarbor. Отдельное окно не было доступно UI-инструменту после запуска; это соответствует menu-bar режиму. Release artifact `build/StatusMenu/PRHarbor.app` также обновлён, но второй процесс для него не запускался.

Публичные API: [Scene.defaultLaunchBehavior](https://developer.apple.com/documentation/swiftui/scene/defaultlaunchbehavior(_:)), [Scene.restorationBehavior](https://developer.apple.com/documentation/swiftui/scene/restorationbehavior(_:)).

Изменения не закоммичены и не отправлены в remote.
