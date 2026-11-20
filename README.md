# MKJI

MKJI — компилируемый язык программирования с C-подобным синтаксисом.  
Компилятор написан на самом MKJI (self-hosted) и генерирует нативные исполняемые файлы без внешних ассемблеров и линкеров:

- **Windows:** PE64 (`.exe`)
- **Linux x86-64:** ELF64

Цель проекта — простой и практичный системный язык с понятным синтаксисом и постепенным развитием в сторону строгой статической модели и безопасной работы с памятью.

## Возможности языка

- Статически типизированные переменные: `int`, `bool`, `string`, `byte`, массивы (`int[]`, `byte[]`, `string[]`, массивы классов), классы
- Функции (`fn`) с параметрами и возвращаемыми значениями
- Классы: поля, методы, `this`, конструктор `init`, создание через `new`
- Управление потоком: `if` / `else`, `while`, `return`, блоки `{ ... }`
- Выражения: арифметика, сравнения, логические и побитовые операции, вызовы, доступ к полям/методам, индексация, `.len`
- Массивы и строки: литералы, индексация, длина
- Встроенные функции: `print`, `read_file`, `write_file`, `panic`, `str_from`, `arg_count`, `get_arg`
- Подключение файлов: `use "path.mk";` (текстовое включение относительно текущего файла)
- Внешние функции из динамических библиотек (FFI): `extern "lib" { ... }` для DLL (Windows) и `.so` (Linux)
- Проекты с манифестом и подключением библиотек

Подробная документация: [docs/index.html](docs/index.html)

## Быстрый старт

В репозитории есть готовые компиляторы:

- `mkji.exe` — для Windows (PE64)
- `mkji_elf` — для Linux x86-64 (ELF64)

### Компиляция одной программы

```powershell
# Windows
.\mkji.exe examples\hello.mk -o hello.exe --target pe
.\hello.exe
```

```sh
# Linux / WSL
./mkji_elf examples/hello.mk -o hello --target elf
chmod +x hello
./hello
```

Формат команды:

```text
mkji <file.mk> [-o <out>] [--target pe|elf]
```

Если выходной файл не указан, компилятор выбирает имя автоматически (`.exe` для PE, `.elf` для ELF).  
Если цель не указана, по умолчанию используется `pe`.

### Legacy-режим (`mkji_build.txt`)

Запуск без аргументов читает файл `mkji_build.txt` в текущем каталоге:

```text
src/main.mk
mkji.exe
pe
```

Строки: входной файл, выходной файл, цель (`pe` или `elf`).

## Проекты

Создание проекта:

```powershell
.\mkji.exe new Demo
```

Будут созданы:
- `DemoProjects.mk` — манифест проекта
- `Demo.mk` — точка входа

Сборка проекта:

```powershell
.\mkji.exe build DemoProjects.mk
```

Пример манифеста:

```text
main: Demo.mk
target: pe
output: Demo.exe
lib: lib/utils.mk
lib: lib/math.mk
```

Поддерживаемые ключи:
- `main:` — главный исходный файл
- `target:` — `pe` или `elf`
- `output:` — путь к выходному файлу (необязательно)
- `lib:` — дополнительный исходный файл/библиотека (может повторяться)

Библиотеки и `use`-файлы подключаются на уровне исходного кода и компилируются в одну программу.

## Пример программы

```mk
fn int sum(int a, int b) {
    return a + b;
}

class Counter {
    int value;

    fn void init(int start) {
        this.value = start;
    }

    fn void inc() {
        this.value = this.value + 1;
    }
}

Counter c = new Counter(10);
c.inc();
print(sum(c.value, 5));
```

Больше примеров: [`examples/`](examples/) и [`tests/`](tests/).

## Внешние библиотеки (FFI)

MKJI поддерживает импорт функций из динамических библиотек через объявления `extern`.

```mk
// Импорт функций из Windows DLL
extern "kernel32.dll" {
    fn int GetCurrentProcessId();
    fn void SetLastError(int err);
    fn int GetLastError();
}

// Одиночное объявление с явным именем символа
extern "kernel32.dll" fn int GetTickCount() as "GetTickCount";

SetLastError(0);
print(GetCurrentProcessId());
```

- В блоке `extern "lib" { ... }` можно объявить несколько функций из одной библиотеки.
- Ключевое слово `as "SymbolName"` задаёт имя экспортируемого символа, если оно отличается от имени в MKJI.
- Для строковых параметров (`string`) в вызов передаётся указатель на данные строки (совместимо с C-строками), для `byte[]` — указатель на данные массива.
- Поддерживается импорт из **DLL на Windows (PE64)** и из **разделяемых библиотек `.so` на Linux (ELF64)** (динамическое связывание).

## Пересборка компилятора

Исходники компилятора находятся в [`src/`](src/), точка входа — `src/main.mk`.

```powershell
# Windows
.\mkji.exe src\main.mk -o mkji.exe --target pe
```

```sh
# Linux / WSL
./mkji_elf src/main.mk -o mkji_elf --target elf
chmod +x mkji_elf
```

## Инструменты

- **VSCode-расширение:** [`vscode-mkji/`](vscode-mkji/) — подсветка синтаксиса и диагностика ошибок
- **Статический анализатор:** [`tools/mkji-analyzer.py`](tools/mkji-analyzer.py)
- **Сайт и подробная документация:** [`docs/index.html`](docs/index.html)

## Структура репозитория

- `src/` — исходный код компилятора MKJI
- `examples/` — примеры программ
- `tests/` — тесты
- `tools/` — вспомогательные инструменты
- `vscode-mkji/` — расширение для Visual Studio Code
- `docs/` — сайт и документация
- `mkji.exe`, `mkji_elf` — готовые компиляторы

## Лицензия

MIT — см. [LICENSE](LICENSE).
