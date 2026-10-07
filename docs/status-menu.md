# Контекстное меню иконки PR Harbor

У иконки в строке меню добавлен единственный пункт **Quit** (⌘Q). Правый клик и Ctrl-клик показывают нативный NSMenu; действие вызывает стандартный `NSApplication.terminate`. Левый клик открывает и закрывает существующий SwiftUI PanelView.

Иконкой управляет отдельный `StatusBarController` через публичные NSStatusItem / NSStatusBarButton API. Счётчик PR обновляется через Combine после изменения store. Панель размещена в transient NSPopover, который закрывается при клике снаружи; settings открываются в повторно используемом NSWindow. AppDelegate владеет одним store для панели, настроек и Debug-окна. Скрытые API и глобальные перехватчики событий не используются.

Проверка:

- **64 tests / 11 suites passed**, `/tmp/prharbor-status-test.log`.
- **Release BUILD SUCCEEDED**, `/tmp/prharbor-status-release.log`. После успешных тестов изменено только название меню с `Quit PR Harbor` на `Quit` и повторно выполнен Release build.
- В Debug загрузились **68 PR**, из панели открылось окно настроек. Quit через стандартное ⌘Q закрыл Debug-процесс.
- `build/StatusMenu/PRHarbor.app` подписан ad hoc с прежними sandbox entitlements; strict codesign verification и `git diff --check` прошли. Release запущен, PID **83211**.
- Нативный UI-инструмент не видит саму иконку / закрытую accessory-панель. **Пользователь подтвердил живую проверку: после правого клика появился Quit.** Само завершение приложения через этот пункт отдельно не нажималось; стандартное завершение проверено через ⌘Q.

Источники API: [NSStatusItem.button](https://developer.apple.com/documentation/appkit/nsstatusitem/button), [NSMenu.popUpContextMenu](https://developer.apple.com/documentation/appkit/nsmenu/popupcontextmenu(_:with:for:)), [NSPopover](https://developer.apple.com/documentation/appkit/nspopover).

Изменения не закоммичены и не отправлены в remote.
