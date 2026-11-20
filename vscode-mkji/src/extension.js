const vscode = require('vscode');
const cp = require('child_process');
const path = require('path');
const fs = require('fs');

let diagnosticCollection;
const pending = new Map();

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
    const folder = vscode.workspace.getWorkspaceFolder(documentUri);
    if (folder) return path.join(folder.uri.fsPath, configured);
    return configured;
  }
  const folder = vscode.workspace.getWorkspaceFolder(documentUri);
  if (folder) {
    const candidate = path.join(folder.uri.fsPath, 'tools', 'mkji-analyzer.py');
    if (fileExists(candidate)) return candidate;
  }
  // fallback: look relative to any workspace folder
  if (vscode.workspace.workspaceFolders) {
    for (const wf of vscode.workspace.workspaceFolders) {
      const candidate = path.join(wf.uri.fsPath, 'tools', 'mkji-analyzer.py');
      if (fileExists(candidate)) return candidate;
    }
  }
  return null;
}

function resolveCompilerPath(documentUri) {
  const cfg = getConfig();
  const configured = (cfg.get('compiler.path') || '').trim();
  if (configured) {
    if (path.isAbsolute(configured)) return configured;
    const folder = vscode.workspace.getWorkspaceFolder(documentUri);
    if (folder) return path.join(folder.uri.fsPath, configured);
    return configured;
  }
  if (!cfg.get('compiler.useWorkspaceDefault', true)) return null;

  const folders = [];
  const wf = vscode.workspace.getWorkspaceFolder(documentUri);
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

function parseDiagnostics(output, fallbackFile) {
  const diags = [];
  const lines = output.split(/\r?\n/);
  // format: file(line,col): severity: message
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

  // fallback: compiler-style "mkji: ..." or plain messages without location
  if (diags.length === 0) {
    const text = output.trim();
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
  if (document.languageId !== 'mkji') return;

  const filePath = document.uri.fsPath;
  const analyzer = resolveAnalyzerPath(document.uri);
  const python = (cfg.get('pythonPath') || 'python').trim() || 'python';

  const args = [];
  let command = null;

  if (analyzer && fileExists(analyzer)) {
    command = python;
    args.push(analyzer, '--format', 'vscode');
    const compiler = resolveCompilerPath(document.uri);
    if (compiler && fileExists(compiler)) {
      args.push('--compiler', compiler);
    }
    args.push(filePath);
  } else {
    // fallback: try running compiler directly
    const compiler = resolveCompilerPath(document.uri);
    if (!compiler || !fileExists(compiler)) {
      // no analyzer and no compiler available; clear only our stale diags if desired
      return;
    }
    command = compiler;
    const tmpOut = filePath + '.__mkji_vscode_tmp';
    args.push(filePath, '-o', tmpOut, '--target', 'pe');
    runProcess(command, args, { cwd: path.dirname(filePath), tmpOut, filePath });
    return;
  }

  runProcess(command, args, { cwd: path.dirname(filePath), filePath });
}

function runProcess(command, args, opts) {
  const filePath = opts.filePath;
  cp.execFile(command, args, { cwd: opts.cwd, windowsHide: true, maxBuffer: 1024 * 1024 }, (err, stdout, stderr) => {
    let output = `${stdout || ''}\n${stderr || ''}`.trim();
    if (err && !output) output = err.message || String(err);

    // cleanup temp output if compiler fallback created it
    if (opts.tmpOut) {
      try { if (fs.existsSync(opts.tmpOut)) fs.unlinkSync(opts.tmpOut); } catch (_) {}
    }

    const parsed = parseDiagnostics(output, filePath);

    // group by file uri
    const byFile = new Map();
    // clear current file first
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

function activate(context) {
  diagnosticCollection = vscode.languages.createDiagnosticCollection('mkji');
  context.subscriptions.push(diagnosticCollection);

  context.subscriptions.push(vscode.workspace.onDidSaveTextDocument(doc => {
    if (getConfig().get('analyzer.runOnSave', true)) scheduleAnalyze(doc, 0);
  }));

  context.subscriptions.push(vscode.workspace.onDidOpenTextDocument(doc => {
    if (getConfig().get('analyzer.runOnOpen', true)) scheduleAnalyze(doc, 100);
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

  // analyze already open mkji documents
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
