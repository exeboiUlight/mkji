# MKJI для Visual Studio Code

Расширение добавляет поддержку языка MKJI в VSCode:

- подсветка синтаксиса (`.mk`)
- базовая авто-конфигурация языка (скобки, комментарии, авто-закрытие)
- диагностика ошибок (через анализатор и/или компилятор MKJI)

## Возможности

- Подсветка ключевых слов, типов, встроенных функций, строк, чисел, комментариев
- Проверка файла при открытии и сохранении
- Команды:
  - **MKJI: Analyze Current File**
  - **MKJI: Analyze Workspace**
- Problem matcher для формата `file(line,col): severity: message`

## Диагностика

По умолчанию расширение пытается запустить `tools/mkji-analyzer.py` из открытого рабочего каталога (workspace), используя Python (`mkji.pythonPath`, по умолчанию `python`).

Если анализатор найден, он может дополнительно вызывать компилятор MKJI (`mkji.compiler.path`), чтобы показывать ошибки компиляции. Если путь к компилятору не задан, расширение пытается найти `mkji.exe` или `mkji_elf` в корне workspace.

Если анализатор недоступен, расширение пытается запустить компилятор напрямую как fallback.

## Настройки

- `mkji.analyzer.enabled` — включить диагностику
- `mkji.analyzer.runOnSave` — анализ при сохранении
- `mkji.analyzer.runOnOpen` — анализ при открытии
- `mkji.analyzer.path` — путь к `mkji-analyzer.py`
- `mkji.pythonPath` — путь к Python
- `mkji.compiler.path` — путь к компилятору `mkji`
- `mkji.compiler.useWorkspaceDefault` — искать компилятор в workspace автоматически
- `mkji.analyzer.debounceMs` — задержка перед анализом

## Установка из исходников

1. Откройте папку `vscode-mkji` в VSCode или скопируйте её в каталог расширений.
2. Для разработки: запустите VSCode с этим расширением (F5 / Extension Development Host).
3. Убедитесь, что в проекте MKJI доступен `tools/mkji-analyzer.py` и/или компилятор.
