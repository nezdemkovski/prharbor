# PR Harbor: быстрая прокрутка

Пользователь уточнил, что при быстром скролле подёргивается движение, а не скачет позиция списка и не мигают строки. Проверка выполнена на реальных 68 PR через существующее CLI-подключение.

## Изменения

- Фоновая сетка перенесена с полного содержимого LazyVStack на видимую область ScrollView. Вертикальные линии, выходные, курсор и brush сохраняют координаты, но больше не требуют поверхности на всю высоту списка.
- Диагональная штриховка каждого трека собирается в один Path и рисуется одной командой stroke. Шаг, толщина, цвет, clipping и fade остались прежними.
- Hover-подсветка вынесена в отдельный ViewModifier со своим State. Смена строки под курсором обновляет подсветку без повторного построения содержимого TimelineRow.
- Аватары декодируются в `@concurrent` загрузчике через ImageIO до максимум 96 pixels с учётом ориентации и немедленным декодированием. Это покрывает самый большой аватар 30 pt даже при 3x. NSImage содержит готовый NSBitmapImageRep; кеш учитывает реальные размеры bitmap.
- AsyncAvatarView сохраняет уже загруженную картинку при повторном появлении lazy-строки с тем же URL. Смена URL и отмена задачи сохраняют прежнюю защиту от устаревшего результата.

Изменения не затрагивают CLI auth или права GitHub. Запросы доступа в организации и операции записи в PR не выполнялись.

## Проверка

- `xcodebuild ... CODE_SIGNING_ALLOWED=NO test`: **64 tests / 11 suites passed**, `/tmp/prharbor-scroll-final-test.log`. Добавлены проверки ограничения размера, aspect ratio, EXIF orientation, малых изображений и некорректных данных. Существующий тест общих загрузок/HTTP failures использует PNG с корректным CRC.
- Signed sandboxed Debug собран с `SWIFT_OPTIMIZATION_LEVEL=-O`, как Release. Загрузились **68 PR / Mine 19 / Reviewing 49**. Проверены повторные прокрутки вверх-вниз, Mine, 2W с weekend shading и возврат All/6M. Отрисовка светлой и тёмной темы проверена по snapshot-файлам.
- Финальный Release: **BUILD SUCCEEDED**, `/tmp/prharbor-scroll-release.log`. [Готовая аппка](/Users/yuri/Apps/PullBar/build/ScrollPolish-2026-10-04/PRHarbor.app) подписана ad hoc с сохранёнными app-sandbox / network-client entitlements; `codesign --verify --deep --strict` прошёл. Запущен PID **80967**, 23:55:12 CEST. Диагностическая сборка закрыта. Инструмент управления не получил закрытую accessory-панель Release; живой UI проверен в оптимизированном sandboxed Debug из тех же финальных исходников, запуск Release подтверждён по процессу.
- Профили сняты системным `sample` при нативной автоматизированной прокрутке: три пары down/up по три страницы и ещё down по три страницы. Это проверяет создание и отрисовку строк, но не воспроизводит в точности инерцию физического трекпада.

| Профиль | Период | CanvasDisplayList.updateValue, main-thread samples | Track Canvas closure samples | NSHostingView.layout samples |
| --- | --- | ---: | ---: | ---: |
| До изменений | 25 s | 61 | 57 | 1416 |
| Финальный, без тестов и переключения фильтров | 20 s | 4 | 4 | 714 |

Файлы: `/tmp/prharbor-scroll-before.sample.txt`, `/tmp/prharbor-scroll-final-clean.sample.txt`. В финальном профиле TimelineRow.body встретился один раз; TimelineItem.init не встретился. Footprint в этих снимках 90.3 MB и 86.5 MB соответственно.

Это направленное подтверждение уменьшения работы отрисовки, **не FPS-бенчмарк и не доказательство полного устранения всех лагов**: длительности различаются, кеш финального прохода уже прогрет, тайминг ввода и системная нагрузка не контролировались. Промежуточные профили `scroll-after` и `scroll-final` не используются как итоговая проверка: первый пересекался с тестами, второй — с переключением фильтров.

![Финальный таймлайн](/Users/yuri/.codex/visualizations/2026/10/04/01a10783-b209-79e0-b06a-1bc7dc0d3ba8/prharbor-scroll-final.png)

Подход к декодированию следует [Apple: Image and Graphics Best Practices](https://devstreaming-cdn.apple.com/videos/wwdc/2018/219mybpx95zm9x/219/219_image_and_graphics_best_practices.pdf). LazyVStack сохранён; Apple описывает его особенности в [Creating performant scrollable stacks](https://developer.apple.com/documentation/swiftui/creating-performant-scrollable-stacks/).

Изменения не закоммичены и не отправлены в remote.
