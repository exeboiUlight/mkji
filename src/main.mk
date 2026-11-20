// MKJI 1.0 — драйвер самохостящегося компилятора.
use "core.mk";
use "lexer.mk";
use "emit.mk";
use "runtime.mk";
use "parser.mk";
use "codegen.mk";
use "image.mk";

fn bool streq(string a, string b) {
    if (a.len != b.len) return false;
    int i = 0;
    while (i < a.len) {
        if (a[i] != b[i]) return false;
        i = i + 1;
    }
    return true;
}

fn string trim_line(string s) {
    int start = 0;
    bool scanning = true;
    while (start < s.len && scanning) {
        int c = s[start];
        if (c == 32 || c == 9 || c == 13 || c == 10) start = start + 1;
        else scanning = false;
    }
    int end = s.len;
    scanning = true;
    while (end > start && scanning) {
        int c = s[end - 1];
        if (c == 32 || c == 9 || c == 13 || c == 10) end = end - 1;
        else scanning = false;
    }
    int len = end - start;
    if (len <= 0) return "";
    if (start == 0 && end == s.len) return s;
    byte[] b = new byte[len];
    int i = 0;
    while (i < len) { b[i] = s[start + i]; i = i + 1; }
    return str_from(b, len);
}

fn string substr_s(string s, int start, int len) {
    if (len <= 0) return "";
    if (start < 0) start = 0;
    if (start + len > s.len) len = s.len - start;
    if (len <= 0) return "";
    byte[] b = new byte[len];
    int i = 0;
    while (i < len) { b[i] = s[start + i]; i = i + 1; }
    return str_from(b, len);
}

fn bool starts_with(string s, string pfx) {
    if (pfx.len > s.len) return false;
    int i = 0;
    while (i < pfx.len) {
        if (s[i] != pfx[i]) return false;
        i = i + 1;
    }
    return true;
}

fn string concat2(string a, string b) {
    int n = a.len + b.len;
    byte[] buf = new byte[n];
    int i = 0;
    while (i < a.len) { buf[i] = a[i]; i = i + 1; }
    int j = 0;
    while (j < b.len) { buf[a.len + j] = b[j]; j = j + 1; }
    return str_from(buf, n);
}

fn string concat3(string a, string b, string c) {
    return concat2(concat2(a, b), c);
}

fn string line_at(string s, int idx) {
    int line = 0;
    int start = 0;
    int i = 0;
    int n = s.len;
    while (i <= n) {
        bool eol = false;
        if (i == n) eol = true;
        else if (s[i] == 10) eol = true;
        if (eol) {
            if (line == idx) {
                int end = i;
                if (end > start && s[end - 1] == 13) end = end - 1;
                int len = end - start;
                if (len <= 0) return "";
                byte[] b = new byte[len];
                int j = 0;
                while (j < len) {
                    b[j] = s[start + j];
                    j = j + 1;
                }
                return str_from(b, len);
            }
            line = line + 1;
            start = i + 1;
        }
        i = i + 1;
    }
    return "";
}

fn int count_lines(string s) {
    if (s.len == 0) return 0;
    int n = 1;
    int i = 0;
    while (i < s.len) {
        if (s[i] == 10) n = n + 1;
        i = i + 1;
    }
    return n;
}

fn string default_out(string inpath, bool pe) {
    int n = inpath.len;
    int dot = -1;
    int slash = -1;
    int i = 0;
    while (i < n) {
        int c = inpath[i];
        if (c == 46) dot = i;
        if (c == 47 || c == 92) slash = i;
        i = i + 1;
    }
    int base_end = n;
    if (dot > slash) base_end = dot;
    if (base_end <= 0) base_end = n;
    string base = substr_s(inpath, 0, base_end);
    if (pe) return concat2(base, ".exe");
    return concat2(base, ".elf");
}

fn void compile_input(string inpath, string outpath, string tgt) {
    if (inpath.len == 0) panic("mkji: input path is empty");
    bool pe = true;
    if (streq(tgt, "elf") || streq(tgt, "linux")) pe = false;
    if (outpath.len == 0) outpath = default_out(inpath, pe);

    Prog prog = new Prog();
    prog.setup();
    Parser par = new Parser();
    par.setup(prog);
    par.parse_all(inpath);

    int target = 2;
    if (pe) target = 1;

    Image img = new Image();
    img.setup(target);

    Runtime rt = new Runtime();
    rt.emit_all(img);

    Codegen cg = new Codegen();
    cg.setup(img, prog);
    cg.emit_program();
    cg.build_data();

    if (pe) {
        img.compute_pe_layout();
        img_prepare_pe(img);
        img.resolve();
        write_pe(img, outpath);
    } else {
        img.compute_elf_layout();
        img.resolve();
        write_elf(img, outpath);
    }

    print(inpath);
    print(" -> ");
    print(outpath);
    print("\n");
}

fn void compile_legacy() {
    string args = read_file("mkji_build.txt");
    if (args == null) panic("mkji: missing build instructions");
    string inpath = trim_line(line_at(args, 0));
    string outpath = trim_line(line_at(args, 1));
    string tgt = trim_line(line_at(args, 2));
    compile_input(inpath, outpath, tgt);
    print("mkji: done\n");
}

fn void usage() {
    print("mkji 1.0\n");
    print("usage:\n");
    print("  mkji                       build via mkji_build.txt (legacy)\n");
    print("  mkji <file.mk> [-o out] [--target pe|elf]\n");
    print("  mkji build [file.mk]\n");
    print("  mkji new <Name>\n");
}

fn void cmd_new(string name) {
    if (name.len == 0) panic("mkji: project name is empty");
    string proj = concat2(name, "Projects.mk");
    string mainf = concat2(name, ".mk");
    string outpe = concat2(name, ".exe");

    string m1 = concat3("main: ", mainf, "\n");
    string m2 = "target: pe\n";
    string m3 = concat3("output: ", outpe, "\n");
    string manifest = concat3(m1, m2, m3);

    string code = concat3("print(\"hello from ", name, "\");\n");
    byte[] mb = bytes(manifest);
    bool ok1 = write_file(proj, mb);
    byte[] cb = bytes(code);
    bool ok2 = write_file(mainf, cb);
    if (!ok1 || !ok2) panic("mkji: failed to create project files");
    print("created ");
    print(proj);
    print("\ncreated ");
    print(mainf);
    print("\n");
}

fn string get_manifest_value(string content, string key) {
    int nlines = count_lines(content);
    int i = 0;
    while (i < nlines) {
        string line = trim_line(line_at(content, i));
        if (starts_with(line, key)) {
            string rest = substr_s(line, key.len, line.len - key.len);
            return trim_line(rest);
        }
        i = i + 1;
    }
    return "";
}

fn int count_manifest_key(string content, string key) {
    int nlines = count_lines(content);
    int i = 0;
    int n = 0;
    while (i < nlines) {
        string line = trim_line(line_at(content, i));
        if (starts_with(line, key)) n = n + 1;
        i = i + 1;
    }
    return n;
}

fn void compile_project(string projpath) {
    string content = read_file(projpath);
    if (content == null) panic("mkji: cannot read project file");
    string mainp = get_manifest_value(content, "main:");
    string tgt = get_manifest_value(content, "target:");
    string outp = get_manifest_value(content, "output:");
    if (mainp.len == 0) panic("mkji: project has no main");
    if (tgt.len == 0) tgt = "pe";

    bool pe = true;
    if (streq(tgt, "elf") || streq(tgt, "linux")) pe = false;
    if (outp.len == 0) outp = default_out(mainp, pe);

    int nlibs = count_manifest_key(content, "lib:");
    string[] libs = new string[nlibs];
    int li = 0;
    int nlines = count_lines(content);
    int i = 0;
    while (i < nlines) {
        string line = trim_line(line_at(content, i));
        if (starts_with(line, "lib:")) {
            string rest = substr_s(line, 4, line.len - 4);
            libs[li] = trim_line(rest);
            li = li + 1;
        }
        i = i + 1;
    }

    Prog prog = new Prog();
    prog.setup();
    Parser par = new Parser();
    par.setup(prog);

    int k = 0;
    while (k < nlibs) {
        if (libs[k].len > 0) par.parse_all(libs[k]);
        k = k + 1;
    }
    par.parse_all(mainp);

    int target = 2;
    if (pe) target = 1;

    Image img = new Image();
    img.setup(target);

    Runtime rt = new Runtime();
    rt.emit_all(img);

    Codegen cg = new Codegen();
    cg.setup(img, prog);
    cg.emit_program();
    cg.build_data();

    if (pe) {
        img.compute_pe_layout();
        img_prepare_pe(img);
        img.resolve();
        write_pe(img, outp);
    } else {
        img.compute_elf_layout();
        img.resolve();
        write_elf(img, outp);
    }

    print(projpath);
    print(" -> ");
    print(outp);
    print("\n");
    print("mkji: project built\n");
}

fn void cmd_build_project(string projpath) {
    compile_project(projpath);
}

int ac = arg_count();
if (ac <= 1) {
    compile_legacy();
} else {
    string a1 = get_arg(1);
    if (streq(a1, "new")) {
        if (ac < 3) panic("mkji: new expects a project name");
        cmd_new(get_arg(2));
    } else if (streq(a1, "build")) {
        string pf = "";
        if (ac >= 3) pf = get_arg(2);
        if (pf.len == 0) {
            // try default: first arg as project? or require name
            // simple: expect explicit project file
            panic("mkji: build expects <Project.mk>");
        }
        cmd_build_project(pf);
    } else if (streq(a1, "help") || streq(a1, "--help") || streq(a1, "-h")) {
        usage();
    } else {
        // direct compile: mkji <file.mk> [-o out] [--target pe|elf]
        string inpath = a1;
        string outpath = "";
        string tgt = "pe";
        int i = 2;
        while (i < ac) {
            string a = get_arg(i);
            if (streq(a, "-o") && i + 1 < ac) {
                outpath = get_arg(i + 1);
                i = i + 2;
            } else if (streq(a, "--target") && i + 1 < ac) {
                tgt = get_arg(i + 1);
                i = i + 2;
            } else if (streq(a, "--target=pe")) {
                tgt = "pe";
                i = i + 1;
            } else if (streq(a, "--target=elf")) {
                tgt = "elf";
                i = i + 1;
            } else {
                i = i + 1;
            }
        }
        compile_input(inpath, outpath, tgt);
        print("mkji: done\n");
    }
}
