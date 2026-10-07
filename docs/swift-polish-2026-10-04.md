# PR Harbor: Swift и отзывчивость — 4 октября 2026

После этого прохода встроенные OAuth/PAT подключения удалены по запросу пользователя. Текущая архитектура и проверки подключения описаны в [CLI-only отчёте](cli-only-2026-10-04.md); ниже сохранён результат предшествующего performance review.

Режим: **full**. Проверены основные пути SwiftUI/AppKit-приложения: timeline, поиск, детали PR и стеков, настройки, загрузка GitHub, gh-транспорт, аватары, таймеры и жизненный цикл задач. В инвентаризации 35 Swift-файлов приложения; статические preview-данные не проверялись строка за строкой. Используется существующая система `TimelineStyle` / `Theme`, SF Symbols и стандартные элементы macOS. Внешние действия над PR и организациями не выполнялись. Отчёт описывает исправления этого прохода, поверх уже существовавших изменений прототипа, авторизации и Apple Intelligence.

## Покрытие

| Категория | Проверенные данные | Результат |
| --- | --- | --- |
| Typography | AppKit-редактор поиска, относительные даты, счётчики, живой timeline и render-тесты | Исправлены лишняя стилизация редактора и вмешательство в marked text; форматтер переиспользуется |
| Surfaces | Timeline, детали, экраны настроек, светлый render и тёмное живое окно | Существующий дизайн сохранён; палитра кэшируется, preview настроек пересчитывается по входным данным |
| Animations | Hover/brush state, Copy feedback, задачи при исчезновении view | Pointer-state изолирован от списка, сброс Copy отменяется вместе с view; новых custom-анимаций нет |
| Icons | CI, review, аватары, loading/sync feedback | Исправлены стабильность identity, обновление содержимого и lifecycle загрузки аватаров |
| Performance | Два 20-секундных `sample`, поиск и прокрутка на 68 реальных PR, API/таймеры/кэш | Устранены повторные вычисления контекста и групп; список стал lazy, decoding выполняется вне MainActor |

Браузерное проигрывание анимаций на 10% неприменимо к этому native SwiftUI-экрану. Нативные состояния проверялись непосредственно; новых анимаций в этом проходе не добавлено.

## Исправления

Severity отражает прежнюю проблему. Все приведённые изменения реализованы.

### Вычисления и обновления представления

| Severity | Location | Before | After | Why |
| --- | --- | --- | --- | --- |
| HIGH | `PRHarbor/Views/Timeline/TimelinePanel.swift:27`, `PRHarbor/Models/TimelineModel.swift:281` | Фильтр каждого PR повторно вычислял query и собирал словарь всех репозиториев/людей; body повторял группировку для высоты, строк и навигации | Контекст обновляется при изменении входных PR; отдельный `TimelinePresentation` готовит фильтр, группы, высоту, selection lookup и navigation IDs один раз на набор параметров | Малый объём работы в `body`: прежний путь имел квадратичный рост и тормозил ввод |
| HIGH | `PRHarbor/Views/Timeline/TimelineDrawing.swift:300`, `PRHarbor/Views/Timeline/TimelinePanel.swift:181` | Hover/drag меняли state всего экрана; при извлечении состояния важно сохранить координаты padded view | Observation-state читают axis/grid; drag публикует изменения только при новом snapped range; координаты учитывают боковой inset | Изоляция частых обновлений предотвращает пересчёт списка при движении мыши; границы hover/drag совпадают с треком |
| HIGH | `PRHarbor/Views/Timeline/TimelinePanel.swift:163`, `PRHarbor/Models/TimelineModel.swift:281` | Eager VStack создавал все строки и track/canvas вне видимой области | Плоский LazyVStack со стабильными row IDs; слои стека имеют известный верхний scroll target; порядок с одинаковыми датами стабилен | Создаются нужные строки; клавиатурная навигация и связанные слои стека остаются согласованными |
| MEDIUM | `PRHarbor/Models/TimelineModel.swift:68`, `PRHarbor/Models/TimelineModel.swift:147`, `PRHarbor/Views/Timeline/TimelineDrawing.swift:210` | Regex bot-patterns, title/ticket/CI/review-derived значения и фильтрация истории повторялись при чтении строки | Matcher компилируется один раз на input; derived поля и отфильтрованная история хранятся в TimelineItem; повторный bot-filter в track удалён | Подготовка данных отделена от рисования; Unicode и литеральные regex-символы обработаны корректно |
| MEDIUM | `PRHarbor/Services/PullRequestStore.swift:370`, `PRHarbor/Services/PullRequestStore.swift:373` | Счётчики пересобирали timeline items из истории при каждом чтении | Кэш обновляется при публикации данных, локальных policy changes и минутном tick; вход сохраняет реальные review-request flags | Меню и уведомления используют один подготовленный набор данных |

### Concurrency, сеть и ограниченные ресурсы

| Severity | Location | Before | After | Why |
| --- | --- | --- | --- | --- |
| HIGH | `PRHarbor/Services/GitHubClient.swift:34`, `:114`, `:172` | Nonisolated async при выбранной approachable-concurrency конфигурации мог наследовать isolation вызывающего MainActor | API entry points явно `@concurrent`; cancellation проверяется между страницами и шагами rebase | Сетевой orchestration и JSON decoding не занимают UI actor |
| MEDIUM | `PRHarbor/Services/PullRequestStore.swift:88`, `:178`, `:206`, `:216` | Частые настройки и повторные refresh могли отменять друг друга и запускать новые запросы; локальная policy требовала refetch | Локальные изменения пересчитывают кэш; сетевые coalesce через 200 ms, одинаковые значения игнорируются, обычные overlapping refresh пропускаются; таймер не чаще минуты; deinit отменяет задачи/таймеры | Отзывчивость не должна зависеть от лишних сетевых циклов |
| MEDIUM | `PRHarbor/Services/GitHubClient.swift:62` | Проверялся только курсор предыдущей страницы | Set посещённых курсоров отвергает также цикл A → B → A | Загрузка не должна зациклиться на некорректной пагинации; адаптивный размер страниц сохранён |
| MEDIUM | `PRHarbor/Helpers/NSImageExtensions.swift:4`, `PRHarbor/Services/PullRequestStore.swift:373`, `PRHarbor/Views/PRRowView.swift:648` | Неограниченный avatar cache, eager prefetch и параллельные дубли загрузок; старый результат мог попасть в новую строку | Actor + NSCache (128 изображений / cost limit 32 MB), одна shared flight на URL, загрузка по видимости, HTTPS/2xx validation, `.task(id: url)` с проверкой cancellation | Память и downloads ограничены; view не публикует устаревшее изображение. NSCache limits являются рекомендациями eviction, не жёстким пределом общей памяти процесса |
| MEDIUM | `PRHarbor/Services/GitHubCLI.swift:253`, `PRHarbor/Views/PanelSettingsView.swift:104`, `PRHarbor/Views/PRRowView.swift:484` | DispatchWorkItem crossing Sendable callback, незавершённый auth/validation при закрытии окна, Copy timer без привязки к view | Cancellable Swift Task deadline; auth/validator cancel onDisappear; Copy reset через `.task(id:)` | Ownership и cancellation явны, предупреждения Swift concurrency устранены; existing sandbox bridge сохранён |

### Identity, ввод и визуальная стабильность

| Severity | Location | Before | After | Why |
| --- | --- | --- | --- | --- |
| MEDIUM | `PRHarbor/Views/PRRowView.swift:42`, `:371`, `PRHarbor/Models/CheckStatus.swift:9` | Equatable учитывал слишком мало полей; CI ID включал изменяемый статус; duplicate reviewer login давал одинаковые IDs | Сравнивается весь Pull; CI identity = name/index; reviewers deduplicate по login в исходном порядке | CI/review/title обновляются даже без нового updatedAt, а status transition сохраняет identity элемента |
| MEDIUM | `PRHarbor/Views/Timeline/TimelineToolbar.swift:93`, `:125` | Editor регулярно перезаписывал attributed string и мог вмешиваться в IME composition | Highlight кэшируется по text/appearance; marked text не перезаписывается; caret/selection сохраняются; regex переиспользуется | Native editing должен сохранять композицию и не делать лишнюю работу при обновлении соседнего UI |
| LOW | `PRHarbor/Views/Timeline/TimelineToolbar.swift:196`, `PRHarbor/Views/Timeline/TimelinePanel.swift:83` | Last-sync label мог показывать Live при новой загрузке/ошибке и всегда имел зелёный цвет; loading indicator плохо помещался в пустую область; empty message использовал forced unwrap | Приоритет Syncing / Sync failed, muted loading и error color; компактный loading layout; безопасный optional branching | Пользователь получает достоверный feedback и читаемые loading/empty/error состояния |
| LOW | `PRHarbor/Views/Timeline/TimelineSettingsPane.swift:111`, `:163` | Sample history пересоздавалась в body, включая обновления drag; записывались одинаковые thresholds | Preview-кэш по sample input с округлением времени до минуты; identical threshold writes пропускаются | Ползунки настроек не должны повторно разбирать fixture и дёргать подписчиков |
| LOW | `PRHarbor/Views/Timeline/TimelineDrawing.swift:4`, `PRHarbor/Helpers/DateExtensions.swift:5`, `PRHarbor/Views/PRRowView.swift:674`, `PRHarbor/Views/Timeline/TimelinePreview.swift:9` | Color/formatter allocations при чтениях, unsafe mutable color dictionary, try! preview decode | Общая палитра и formatter переиспользуются, dictionary изолирован MainActor, decode имеет guarded fallback + debug assertion | Меньше allocations; actor isolation выражена без unsafe; fixture failure имеет понятную диагностику |

## Рассмотрено и отклонено

| Location | Candidate | Rejected because |
| --- | --- | --- |
| `PRHarbor/PRHarbor.entitlements`, `Services/GitHubCLI.swift` | Отключить App Sandbox ради простого запуска gh | Защита приложения сохранена; рабочий NSUserUnixTask bridge уже предоставляет нужный транспорт |
| `Services/PullRequestStore.swift`, все views | Перевести весь ObservableObject слой на Observation | Подтверждённая проблема решается изоляцией pointer-state и подготовкой данных; полный rewrite не обоснован этим профилем |
| `Views/Timeline/TimelineDetailView.swift` | Отменять rebase при исчезновении view | Частично выполненную пользовательскую операцию над стеком нельзя привязать только к присутствию detail view; отмена между сетевыми шагами поддерживается клиентом |
| `Views/Timeline/TimelinePanel.swift` | Добавить custom animation на каждое hover/selection/filter изменение | Это частые взаимодействия; мгновенный feedback сохраняет внимание и существующий дизайн |

## Проверка

1. `xcodebuild -project PRHarbor.xcodeproj -scheme PRHarbor -destination 'platform=macOS' -derivedDataPath /tmp/pullbar-derived -clonedSourcePackagesDirPath /Users/yuri/Library/Developer/Xcode/DerivedData/PRHarbor-fpxzpkowwumourhcozokttwdrkes/SourcePackages -disableAutomaticPackageResolution CODE_SIGNING_ALLOWED=NO test` — **67 tests / 11 suites passed**, Swift 6.
   Новые regression checks: cursor cycle, coalesced avatar requests и uncached HTTP failure, stack companions/order/collapse/navigation targets, repository/Bots collapse, query/tab/brush/sort stability, Unicode bot patterns, CI/review change без изменения updatedAt, stable CI IDs, границы padded hover/drag и reset interaction. Проверка log-scale endpoint использует допуск floating-point, а не точное сравнение обратной экспоненты с целым числом. Существующие render/search/auth/stack tests также прошли. Тестовый лог: `/tmp/prharbor-performance-test.log`.
2. Та же команда с `-configuration Release` и `build` — **BUILD SUCCEEDED**. Собранный bundle: `build/SwiftPolish-2026-10-04/PRHarbor.app`.
3. `codesign --verify --deep --strict --verbose=2 build/SwiftPolish-2026-10-04/PRHarbor.app` — **valid on disk / satisfies Designated Requirement**. Проверены sandbox + network-client entitlements. Подпись ad hoc для локального запуска; notarization не выполнялась.
4. В подписанном sandboxed Debug-приложении через текущий gh sign-in загружено **68 PR (Mine 19 / Reviewing 49)**. Проверены поиск `noona-api`, очистка, прокрутка вниз/вверх, Down-key selection, поиск `#4298` с сохранением всех трёх активных слоёв стека, collapse/expand, Timeline settings, независимые AI toggles и Account с действующим gh connection. Временный collapse восстановлен; auth и AI preferences не изменялись.
5. Светлый snapshot после изменений и живой тёмный timeline визуально проверены. Loading, empty, error и settings rendering покрыты существующими snapshot/render smoke tests; это проверки рендера, не pixel-diff утверждение.
6. `git diff --check` — прошёл. Swift compile warnings о Sendable capture устранены. Осталась штатная metadata warning об отсутствии AppIntents.framework dependency.
7. После последнего test-запуска восстановлена sandbox-подпись Debug-host и проверена свежая загрузка 68 PR без sync error. Xcode test перезаписывает bundle с `CODE_SIGNING_ALLOWED=NO`, поэтому дальнейший UI smoke выполнялся только после подписи/перезапуска. Финальный снимок: [живой timeline](/Users/yuri/.codex/visualizations/2026/10/04/01a10783-b209-79e0-b06a-1bc7dc0d3ba8/prharbor-performance-live.png).
8. Debug закрыт; Release запущена через macOS. `ps` подтвердил PID **75873**, путь `/Users/yuri/Apps/PullBar/build/SwiftPolish-2026-10-04/PRHarbor.app/Contents/MacOS/PRHarbor`, launch **23:28:32 CEST**. Release работает как приложение строки меню; computer-use не получил её закрытую accessory-панель, поэтому автоматизированная проверка самого Release UI не завершена. Живой UI и gh smoke проверены на подписанном Debug той же финальной версии исходников.

### Профиль до / после

Два 20-секундных `sample`, Debug, один набор 68 PR, похожие действия search/clear/scroll через UI automation. Счётчики ниже — inclusive samples для точного символа в call graph, а не время всех потомков.

| Наблюдение | До | После |
| --- | ---: | ---: |
| Physical footprint | 188.7 MB | 94.2 MB |
| Peak physical footprint | 216.1 MB | 109.9 MB |
| `IntelligenceSearchContext.init(items:)` samples | 1688 | 0 |
| `TimelinePanel.body.getter` samples | 1403 | 7 |

Исходные профили: `/tmp/prharbor-interaction.sample.txt`, `/tmp/prharbor-interaction-after.sample.txt`. Это подтверждает устранение выявленного горячего пути; не является контролируемым FPS/latency benchmark или гарантией конкретного множителя ускорения. Память зависит от срока жизни процесса, кэшей и UI automation.

**Not verified:** IME composition с реальной системой ввода (guard проверен по AppKit contract и коду); физическое drag-выделение диапазона (computer-use interaction прервалась, coordinates/filter semantics покрыты тестами); выполнение реального rebase и другие записи в GitHub (только существующие transport/model tests); UI закрытой Release accessory-панели (launch/process/signature проверены).

## Основание решений

- [Apple: Understanding and improving SwiftUI performance](https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance) — уменьшаем работу в body и зависимости обновления.
- [Swift SE-0461: Async function isolation](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0461-async-function-isolation.md) — явный `@concurrent` для работы вне isolation вызывающего actor.
- [Apple: LazyVStack](https://developer.apple.com/documentation/swiftui/lazyvstack) — создание содержимого по необходимости.
- [Apple: NSTextInputClient](https://developer.apple.com/documentation/appkit/nstextinputclient) — сохранение marked text/composition при обновлении редактора.

**Verdict: Approve** для исправленных и проверенных путей. Известных оставленных actionable findings в этом проходе нет. Unverified beside verdict: реальная IME composition, физический drag, внешние GitHub mutations, UI Release accessory-панели. Коммит и push не выполнялись.
