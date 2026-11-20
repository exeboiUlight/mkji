const vscode = require('vscode');
const cp = require('child_process');
const path = require('path');
const fs = require('fs');

let diagnosticCollection;
const pending = new Map();

/** -------------------- Configuration & paths -------------------- */

function getConfig() {
  return vscode.workspace.getConfiguration('mkji');
}

function fileExists(p) {
  try { fs.accessSync(p, fs.constants.F_OK); return true; } catch (_) { return false; }
}

function resolveAnalyzerPath(documentUri) {
  const cfg = getConfig();
  const configured = (cfg.get('analyzer.path') || '').trim();
  if (configured) {
    if (path.isAbsolute(configured)) return configured;
    const folder = documentUri ? vscode.workspace.getWorkspaceFolder(documentUri) : null;
    if (folder) return path.join(folder.uri.fsPath, configured);
    return configured;
  }
  const folders = [];
  const wf = documentUri ? vscode.workspace.getWorkspaceFolder(documentUri) : null;
  if (wf) folders.push(wf.uri.fsPath);
  if (vscode.workspace.workspaceFolders) {
    for (const f of vscode.workspace.workspaceFolders) if (!folders.includes(f.uri.fsPath)) folders.push(f.uri.fsPath);
  }
  for (const folder of folders) {
    const candidate = path.join(folder, 'tools', 'mkji-analyzer.py');
    if (fileExists(candidate)) return candidate;
  }
  return null;
}

function resolveCompilerPath(documentUri) {
  const cfg = getConfig();
  const configured = (cfg.get('compiler.path') || '').trim();
  if (configured) {
    if (path.isAbsolute(configured)) return configured;
    const folder = documentUri ? vscode.workspace.getWorkspaceFolder(documentUri) : null;
    if (folder) return path.join(folder.uri.fsPath, configured);
    return configured;
  }
  if (!cfg.get('compiler.useWorkspaceDefault', true)) return null;

  const folders = [];
  const wf = documentUri ? vscode.workspace.getWorkspaceFolder(documentUri) : null;
  if (wf) folders.push(wf.uri.fsPath);
  if (vscode.workspace.workspaceFolders) {
    for (const f of vscode.workspace.workspaceFolders) if (!folders.includes(f.uri.fsPath)) folders.push(f.uri.fsPath);
  }
  const names = process.platform === 'win32' ? ['mkji.exe', 'mkji_elf'] : ['mkji_elf', 'mkji', 'mkji.exe'];
  for (const folder of folders) {
    for (const name of names) {
      const p = path.join(folder, name);
      if (fileExists(p)) return p;
    }
  }
  return null;
}

/** -------------------- Diagnostics -------------------- */

function parseDiagnostics(output, fallbackFile) {
  const diags = [];
  const lines = String(output || '').split(/\r?\n/);
  const re = /^(.*)\((\d+),(\d+)\):\s+(error|warning|info):\s+(.*)$/;
  for (const line of lines) {
    const m = line.match(re);
    if (!m) continue;
    const file = m[1];
    const ln = Math.max(0, parseInt(m[2], 10) - 1);
    const col = Math.max(0, parseInt(m[3], 10) - 1);
    const sevStr = m[4].toLowerCase();
    const msg = m[5];
    let severity = vscode.DiagnosticSeverity.Error;
    if (sevStr === 'warning') severity = vscode.DiagnosticSeverity.Warning;
    else if (sevStr === 'info') severity = vscode.DiagnosticSeverity.Information;
    const range = new vscode.Range(ln, col, ln, col + 1);
    const d = new vscode.Diagnostic(range, msg, severity);
    d.source = 'mkji';
    diags.push({ file: path.normalize(file), diagnostic: d });
  }

  if (diags.length === 0) {
    const text = String(output || '').trim();
    if (text) {
      const range = new vscode.Range(0, 0, 0, 1);
      const severity = /error|panic|cannot|failed|expected|unknown|undefined|invalid|missing/i.test(text)
        ? vscode.DiagnosticSeverity.Error : vscode.DiagnosticSeverity.Information;
      const d = new vscode.Diagnostic(range, text, severity);
      d.source = 'mkji';
      diags.push({ file: path.normalize(fallbackFile), diagnostic: d });
    }
  }
  return diags;
}

function runAnalyzer(document) {
  const cfg = getConfig();
  if (!cfg.get('analyzer.enabled', true)) return;
  if (!document || document.languageId !== 'mkji' || document.uri.scheme !== 'file') return;

  const filePath = document.uri.fsPath;
  const analyzer = resolveAnalyzerPath(document.uri);
  const python = (cfg.get('pythonPath') || 'python').trim() || 'python';

  let command = null;
  let args = [];

  if (analyzer && fileExists(analyzer)) {
    command = python;
    args.push(analyzer, '--format', 'vscode');
    const compiler = resolveCompilerPath(document.uri);
    if (compiler && fileExists(compiler)) {
      args.push('--compiler', compiler);
    }
    args.push(filePath);
    runProcess(command, args, { cwd: path.dirname(filePath), filePath });
    return;
  }

  const compiler = resolveCompilerPath(document.uri);
  if (!compiler || !fileExists(compiler)) return;
  command = compiler;
  const tmpOut = filePath + '.__mkji_vscode_tmp';
  args = [filePath, '-o', tmpOut, '--target', 'pe'];
  runProcess(command, args, { cwd: path.dirname(filePath), tmpOut, filePath });
}

function runProcess(command, args, opts) {
  const filePath = opts.filePath;
  cp.execFile(command, args, { cwd: opts.cwd, windowsHide: true, maxBuffer: 1024 * 1024 }, (err, stdout, stderr) => {
    let output = `${stdout || ''}\n${stderr || ''}`.trim();
    if (err && !output) output = err.message || String(err);

    if (opts.tmpOut) {
      try { if (fs.existsSync(opts.tmpOut)) fs.unlinkSync(opts.tmpOut); } catch (_) {}
    }

    const parsed = parseDiagnostics(output, filePath);
    const byFile = new Map();
    byFile.set(path.normalize(filePath), []);
    for (const item of parsed) {
      const key = item.file;
      if (!byFile.has(key)) byFile.set(key, []);
      byFile.get(key).push(item.diagnostic);
    }
    for (const [file, diags] of byFile.entries()) {
      let uri;
      try { uri = vscode.Uri.file(file); } catch (_) { uri = vscode.Uri.file(filePath); }
      diagnosticCollection.set(uri, diags);
    }
  });
}

function scheduleAnalyze(document, delayOverride) {
  if (!document || document.languageId !== 'mkji') return;
  const cfg = getConfig();
  if (!cfg.get('analyzer.enabled', true)) return;
  const key = document.uri.toString();
  if (pending.has(key)) clearTimeout(pending.get(key));
  const delay = typeof delayOverride === 'number' ? delayOverride : (cfg.get('analyzer.debounceMs') || 400);
  pending.set(key, setTimeout(() => {
    pending.delete(key);
    runAnalyzer(document);
  }, delay));
}

function analyzeAllWorkspace() {
  if (!vscode.workspace.workspaceFolders) return;
  vscode.workspace.findFiles('**/*.mk', '**/node_modules/**').then(files => {
    for (const uri of files) {
      vscode.workspace.openTextDocument(uri).then(doc => runAnalyzer(doc), () => {});
    }
  });
}

/** -------------------- Code intelligence (hints/completions) -------------------- */

const KEYWORDS = ['if', 'else', 'while', 'return', 'use', 'fn', 'class', 'new', 'this', 'true', 'false', 'null', 'extern', 'as'];
const TYPES = ['int', 'bool', 'string', 'byte', 'void'];

const BUILTINS = [
  { name: 'print', detail: 'print(value)', doc: 'Выводит значение и перевод строки.', insert: 'print(${1:value});', kind: vscode.CompletionItemKind.Function },
  { name: 'read_file', detail: 'read_file(path) -> string', doc: 'Читает файл по пути и возвращает содержимое как строку (или null при ошибке).', insert: 'read_file(${1:path})', kind: vscode.CompletionItemKind.Function },
  { name: 'write_file', detail: 'write_file(path, data) -> bool', doc: 'Записывает данные (обычно byte[]) в файл. Возвращает признак успеха.', insert: 'write_file(${1:path}, ${2:data})', kind: vscode.CompletionItemKind.Function },
  { name: 'panic', detail: 'panic(message)', doc: 'Аварийно завершает выполнение с сообщением.', insert: 'panic(${1:message});', kind: vscode.CompletionItemKind.Function },
  { name: 'str_from', detail: 'str_from(bytes, len) -> string', doc: 'Создаёт строку из байтового буфера заданной длины.', insert: 'str_from(${1:bytes}, ${2:len})', kind: vscode.CompletionItemKind.Function },
  { name: 'arg_count', detail: 'arg_count() -> int', doc: 'Возвращает количество аргументов командной строки.', insert: 'arg_count()', kind: vscode.CompletionItemKind.Function },
  { name: 'get_arg', detail: 'get_arg(i) -> string', doc: 'Возвращает аргумент командной строки по индексу i.', insert: 'get_arg(${1:i})', kind: vscode.CompletionItemKind.Function },
];

const SNIPPETS = [
  { label: 'fn', detail: 'Объявление функции', insert: 'fn ${1:int} ${2:name}(${3:params}) {\n\t$0\n}', kind: vscode.CompletionItemKind.Snippet },
  { label: 'class', detail: 'Объявление класса', insert: 'class ${1:Name} {\n\t${2:int} ${3:field};\n\n\tfn void init(${4:params}) {\n\t\t$0\n\t}\n}', kind: vscode.CompletionItemKind.Snippet },
  { label: 'if', detail: 'Условие if', insert: 'if (${1:condition}) {\n\t$0\n}', kind: vscode.CompletionItemKind.Snippet },
  { label: 'ifelse', detail: 'Условие if/else', insert: 'if (${1:condition}) {\n\t$2\n} else {\n\t$0\n}', kind: vscode.CompletionItemKind.Snippet },
  { label: 'while', detail: 'Цикл while', insert: 'while (${1:condition}) {\n\t$0\n}', kind: vscode.CompletionItemKind.Snippet },
  { label: 'use', detail: 'Подключение файла', insert: 'use "${1:file.mk}";', kind: vscode.CompletionItemKind.Snippet },
  { label: 'extern block', detail: 'Импорт функций из библиотеки', insert: 'extern "${1:library.dll}" {\n\tfn ${2:int} ${3:Name}(${4:params});\n}', kind: vscode.CompletionItemKind.Snippet },
  { label: 'extern fn', detail: 'Импорт одной функции из библиотеки', insert: 'extern "${1:library.dll}" fn ${2:int} ${3:Name}(${4:params});', kind: vscode.CompletionItemKind.Snippet },
  { label: 'new array', detail: 'Создание массива', insert: 'new ${1:int}[${2:size}]', kind: vscode.CompletionItemKind.Snippet },
  { label: 'new object', detail: 'Создание объекта класса', insert: 'new ${1:ClassName}(${2:args})', kind: vscode.CompletionItemKind.Snippet },
  { label: 'print', detail: 'print(...)', insert: 'print(${1:value});', kind: vscode.CompletionItemKind.Snippet },
];

const HOVER_DOCS = {
  'print': '**print(value)**\n\nВыводит значение и перевод строки.',
  'read_file': '**read_file(path) -> string**\n\nЧитает файл и возвращает содержимое как строку (или `null` при ошибке).',
  'write_file': '**write_file(path, data) -> bool**\n\nЗаписывает данные в файл. Обычно `data` — `byte[]`.',
  'panic': '**panic(message)**\n\nАварийно завершает выполнение с сообщением.',
  'str_from': '**str_from(bytes, len) -> string**\n\nСоздаёт строку из байтового буфера длиной `len`.',
  'arg_count': '**arg_count() -> int**\n\nВозвращает количество аргументов командной строки.',
  'get_arg': '**get_arg(i) -> string**\n\nВозвращает аргумент командной строки с индексом `i`.',
  'fn': '**fn** — объявление функции: `fn <тип> <имя>(<параметры>) { ... }`',
  'class': '**class** — объявление класса: `class Name { <поля>; <методы> }`',
  'if': '**if** — условная инструкция: `if (условие) { ... } else { ... }`',
  'while': '**while** — цикл: `while (условие) { ... }`',
  'return': '**return** — возврат из функции: `return;` или `return expr;`',
  'use': '**use** — подключение файла: `use "path.mk";` (относительно текущего файла)',
  'new': '**new** — создание массива или объекта: `new int[n]`, `new Class(args)`',
  'this': '**this** — ссылка на текущий объект внутри метода класса.',
  'int': '**int** — целочисленный тип.',
  'bool': '**bool** — логический тип (`true`/`false`).',
  'string': '**string** — строковый тип.',
  'byte': '**byte** — байтовый тип (часто используется как `byte[]`).',
  'void': '**void** — отсутствие возвращаемого значения.',
  'true': '**true** — логическое значение истина.',
  'false': '**false** — логическое значение ложь.',
  'null': '**null** — пустая ссылка.',
};

function collectDocumentSymbols(text) {
  const symbols = [];
  const seen = new Set();
  const add = (name, kind, detail) => {
    if (!name || seen.has(kind + ':' + name)) return;
    seen.add(kind + ':' + name);
    symbols.push({ name, kind, detail });
  };

  // classes
  const classRe = /\bclass\s+([A-Za-z_][A-Za-z0-9_]*)/g;
  let m;
  while ((m = classRe.exec(text)) !== null) add(m[1], vscode.CompletionItemKind.Class, 'Класс');

  // functions/methods: fn <type...> <name>(
  const fnRe = /\bfn\s+((?:[A-Za-z_][A-Za-z0-9_]*)(?:\s*\[\s*\])*)\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(/g;
  while ((m = fnRe.exec(text)) !== null) add(m[2], vscode.CompletionItemKind.Function, `fn ${m[1]} ${m[2]}(...)`);

  // top-level / local typed vars (best-effort): Type name = /;
  const varRe = /(?:^|[;{\n]\s*)([A-Za-z_][A-Za-z0-9_]*(?:\s*\[\s*\])*)\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?=[=;])/g;
  while ((m = varRe.exec(text)) !== null) {
    const type = m[1];
    const name = m[2];
    if (KEYWORDS.includes(name) || TYPES.includes(name) || ['print','panic','read_file','write_file','str_from','arg_count','get_arg'].includes(name)) continue;
    if (['if','while','return','class','fn','use','new','else'].includes(type)) continue;
    add(name, vscode.CompletionItemKind.Variable, `${type} ${name}`);
  }

  return symbols;
}

function createCompletionProvider() {
  return vscode.languages.registerCompletionItemProvider('mkji', {
    provideCompletionItems(document, position) {
      const items = [];

      for (const kw of KEYWORDS) {
        if (['true','false','null','this'].includes(kw)) continue;
        const it = new vscode.CompletionItem(kw, vscode.CompletionItemKind.Keyword);
        it.detail = 'Ключевое слово MKJI';
        if (HOVER_DOCS[kw]) it.documentation = new vscode.MarkdownString(HOVER_DOCS[kw]);
        items.push(it);
      }
      for (const t of TYPES) {
        const it = new vscode.CompletionItem(t, vscode.CompletionItemKind.TypeParameter);
        it.detail = 'Тип MKJI';
        if (HOVER_DOCS[t]) it.documentation = new vscode.MarkdownString(HOVER_DOCS[t]);
        items.push(it);
      }
      for (const c of ['true','false','null','this']) {
        const it = new vscode.CompletionItem(c, c === 'this' ? vscode.CompletionItemKind.Variable : vscode.CompletionItemKind.Constant);
        it.detail = c === 'this' ? 'Текущий объект' : 'Константа';
        if (HOVER_DOCS[c]) it.documentation = new vscode.MarkdownString(HOVER_DOCS[c]);
        items.push(it);
      }
      for (const b of BUILTINS) {
        const it = new vscode.CompletionItem(b.name, b.kind);
        it.detail = b.detail;
        it.documentation = new vscode.MarkdownString(b.doc);
        it.insertText = new vscode.SnippetString(b.insert);
        items.push(it);
      }
      for (const s of SNIPPETS) {
        const it = new vscode.CompletionItem(s.label, s.kind);
        it.detail = s.detail;
        it.insertText = new vscode.SnippetString(s.insert);
        if (s.label === 'fn' || s.label === 'class' || s.label === 'if' || s.label === 'while' || s.label === 'ifelse') {
          it.sortText = '0_' + s.label;
        } else {
          it.sortText = '1_' + s.label;
        }
        items.push(it);
      }

      const text = document.getText();
      const symbols = collectDocumentSymbols(text);
      for (const s of symbols) {
        const it = new vscode.CompletionItem(s.name, s.kind);
        it.detail = s.detail;
        items.push(it);
      }

      // member completion after '.'
      const linePrefix = document.lineAt(position).text.slice(0, position.character);
      if (/\.\s*[A-Za-z_0-9]*$/.test(linePrefix)) {
        const lenItem = new vscode.CompletionItem('len', vscode.CompletionItemKind.Property);
        lenItem.detail = 'Длина строки/массива';
        lenItem.documentation = new vscode.MarkdownString('**len** — длина строки, `byte[]`, `int[]`, `string[]` или массива объектов.');
        items.push(lenItem);
        // also suggest known method names from document
        for (const s of symbols) {
          if (s.kind === vscode.CompletionItemKind.Function) {
            const it = new vscode.CompletionItem(s.name, vscode.CompletionItemKind.Method);
            it.detail = s.detail;
            items.push(it);
          }
        }
      }

      return items;
    }
  }, '.', '"');
}

function createHoverProvider() {
  return vscode.languages.registerHoverProvider('mkji', {
    provideHover(document, position) {
      const range = document.getWordRangeAtPosition(position, /[A-Za-z_][A-Za-z0-9_]*/);
      if (!range) return null;
      const word = document.getText(range);
      const doc = HOVER_DOCS[word];
      if (doc) return new vscode.Hover(new vscode.MarkdownString(doc), range);

      // dynamic symbol hover
      const text = document.getText();
      const fnRe = new RegExp(`\\bfn\\s+((?:[A-Za-z_][A-Za-z0-9_]*)(?:\\s*\\[\\s*\\])*)\\s+(${word})\\s*\\(`);
      const fm = text.match(fnRe);
      if (fm) return new vscode.Hover(new vscode.MarkdownString(`**fn ${fm[1]} ${fm[2]}(...)**`), range);
      const classRe = new RegExp(`\\bclass\\s+(${word})\\b`);
      if (classRe.test(text)) return new vscode.Hover(new vscode.MarkdownString(`**class ${word}**`), range);
      return null;
    }
  });
}

/** -------------------- Activation -------------------- */

function activate(context) {
  diagnosticCollection = vscode.languages.createDiagnosticCollection('mkji');
  context.subscriptions.push(diagnosticCollection);

  context.subscriptions.push(vscode.workspace.onDidSaveTextDocument(doc => {
    if (getConfig().get('analyzer.runOnSave', true)) scheduleAnalyze(doc, 0);
  }));

  context.subscriptions.push(vscode.workspace.onDidOpenTextDocument(doc => {
    if (getConfig().get('analyzer.runOnOpen', true)) scheduleAnalyze(doc, 100);
  }));

  context.subscriptions.push(vscode.workspace.onDidChangeTextDocument(e => {
    // lightweight: re-run analysis after pause, do not block typing; completions use live doc text
    if (e.document && e.document.languageId === 'mkji' && getConfig().get('analyzer.runOnSave', true)) {
      scheduleAnalyze(e.document);
    }
  }));

  context.subscriptions.push(vscode.workspace.onDidCloseTextDocument(doc => {
    const key = doc.uri.toString();
    if (pending.has(key)) {
      clearTimeout(pending.get(key));
      pending.delete(key);
    }
  }));

  context.subscriptions.push(vscode.commands.registerCommand('mkji.analyzeFile', () => {
    const editor = vscode.window.activeTextEditor;
    if (editor) runAnalyzer(editor.document);
  }));

  context.subscriptions.push(vscode.commands.registerCommand('mkji.analyzeWorkspace', () => {
    analyzeAllWorkspace();
  }));

  context.subscriptions.push(createCompletionProvider());
  context.subscriptions.push(createHoverProvider());

  for (const doc of vscode.workspace.textDocuments) {
    if (doc.languageId === 'mkji' && getConfig().get('analyzer.runOnOpen', true)) {
      scheduleAnalyze(doc, 100);
    }
  }
}

function deactivate() {
  for (const t of pending.values()) clearTimeout(t);
  pending.clear();
  if (diagnosticCollection) diagnosticCollection.dispose();
}

module.exports = { activate, deactivate };
