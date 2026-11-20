// MKJI 1.0 — общие структуры компилятора, написанного на MKJI.
//
// Коды типов: 0=void 1=int 2=bool 3=string 4=byte[] 5=int[] 6=class
// Имена хранятся как byte[] + явная длина: в MKJI нет конкатенации строк,
// поэтому метки тоже целочисленные (индексы в таблицах).

class Tok {
    int kind;          // 1=IDENT 2=INT 3=STR 4=PUNCT 5=EOF
    byte[] text;
    int tlen;
    int ival;
    int line;
    int col;

    fn void setup(int k, byte[] t, int tl, int v) {
        this.kind = k;
        this.text = t;
        this.tlen = tl;
        this.ival = v;
    }

    fn void setpos(int l, int c) {
        this.line = l;
        this.col = c;
    }
}

class Expr {
    int kind;          // 1 INT 2 STR 3 BOOL 4 NULL 5 VAR 6 THIS 7 BIN 8 UN
                       // 9 CALL 10 FIELD 11 INDEX 12 ASSIGN 13 NEWARR 14 LEN
    int ival;
    int op;
    byte[] sval;
    int slen;
    Expr a;
    Expr b;
    Expr[] args;
    int nargs;
    int id;            // -2 print, -3 read_file, -4 write_file, >=0 функция
    bool method;
    int ty;
    int slot;

    fn void setup(int k) {
        this.kind = k;
        this.id = 0;
        this.slot = -1;
        this.ty = 1;
    }
}

class Stmt {
    int kind;          // 1 EXPR 2 VAR 3 IF 4 WHILE 5 RETURN 6 BLOCK 7 FN
    Expr e;
    Expr cond;
    byte[] name;
    int namelen;
    int ty;
    int slot;
    Stmt then_b;
    Stmt else_b;
    Stmt body;
    Stmt[] list;
    int n;
    int fnid;
    int id;
    int line;
    int col;

    fn void setup(int k) {
        this.kind = k;
        this.slot = -1;
    }
}

class Param {
    byte[] name;
    int namelen;
    fn void setup(byte[] n, int nl) { this.name = n; this.namelen = nl; }
}

class VarEnt {
    byte[] name;
    int namelen;
    int ty;
    int slot;
    fn void setup(byte[] n, int nl, int t) {
        this.name = n; this.namelen = nl; this.ty = t; this.slot = -1;
    }
}

class Func {
    byte[] name;
    int namelen;
    int ret;
    Param[] params;
    int[] ptypes;
    int nparams;
    Stmt body;
    int nlocals;
    bool is_method;
    int class_id;
    VarEnt[] locals;
    int nlocal_decls;

    fn void setup(byte[] n, int nl, int r) {
        this.name = n;
        this.namelen = nl;
        this.ret = r;
        this.params = new Param[8];
        this.ptypes = new int[8];
        this.nparams = 0;
        this.nlocals = 0;
        this.is_method = false;
        this.class_id = -1;
        this.locals = new VarEnt[256];
        this.nlocal_decls = 0;
    }

    fn int local_type(byte[] n, int nl) {
        int i = 0;
        while (i < this.nlocal_decls) {
            if (names_eq(this.locals[i].name, this.locals[i].namelen, n, nl))
                return this.locals[i].ty;
            i = i + 1;
        }
        return -1;
    }

    fn void add_local(byte[] n, int nl, int t) {
        VarEnt v = new VarEnt();
        v.setup(n, nl, t);
        this.locals[this.nlocal_decls] = v;
        this.nlocal_decls = this.nlocal_decls + 1;
    }
}

class StrEnt {
    byte[] value;
    int vlen;
    int label;
    fn void setup(byte[] v, int vl, int l) {
        this.value = v; this.vlen = vl; this.label = l;
    }
}

class Buf {
    byte[] p;
    int len;

    fn void setup(int cap) {
        this.p = new byte[cap];
        this.len = 0;
    }

    fn void put(int v) {
        this.p[this.len] = v;
        this.len = this.len + 1;
    }

    fn void u16(int v) {
        this.put(v & 255);
        this.put((v >> 8) & 255);
    }

    fn void u32(int v) {
        this.put(v & 255);
        this.put((v >> 8) & 255);
        this.put((v >> 16) & 255);
        this.put((v >> 24) & 255);
    }

    fn void u64(int v) {
        this.u32(v & 0xFFFFFFFF);
        this.u32((v >> 32) & 0xFFFFFFFF);
    }

    fn void write(byte[] src, int n) {
        int i = 0;
        while (i < n) {
            this.p[this.len] = src[i];
            this.len = this.len + 1;
            i = i + 1;
        }
    }

    fn void zeroes(int n) {
        int i = 0;
        while (i < n) {
            this.put(0);
            i = i + 1;
        }
    }

    fn void align(int a) {
        while ((this.len % a) != 0) this.put(0);
    }

    fn void patch32(int at, int v) {
        this.p[at] = v & 255;
        this.p[at + 1] = (v >> 8) & 255;
        this.p[at + 2] = (v >> 16) & 255;
        this.p[at + 3] = (v >> 24) & 255;
    }

    fn void patch64(int at, int v) {
        this.patch32(at, v & 0xFFFFFFFF);
        this.patch32(at + 4, (v >> 32) & 0xFFFFFFFF);
    }
}

// Фатальная ошибка: печатает сообщение и завершает процесс.
fn void die(string msg) { panic(msg); }

// name_eq(byte[], byte[] length, string literal)
fn bool name_eq(byte[] a, int alen, string b) {
    if (alen != b.len) return false;
    int i = 0;
    while (i < alen) {
        if (a[i] != b[i]) return false;
        i = i + 1;
    }
    return true;
}

fn bool names_eq(byte[] a, int alen, byte[] b, int blen) {
    if (alen != blen) return false;
    int i = 0;
    while (i < alen) {
        if (a[i] != b[i]) return false;
        i = i + 1;
    }
    return true;
}

// Копирует строку в byte[] точной длины.
fn byte[] bytes(string s) {
    byte[] b = new byte[s.len];
    int i = 0;
    while (i < s.len) {
        b[i] = s[i];
        i = i + 1;
    }
    return b;
}

class FieldInfo {
    byte[] name;
    int namelen;
    int ty;
    fn void setup(byte[] n, int nl, int t) {
        this.name = n; this.namelen = nl; this.ty = t;
    }
}

class MethodInfo {
    byte[] name;
    int namelen;
    fn void setup(byte[] n, int nl) { this.name = n; this.namelen = nl; }
}

class ClassInfo {
    byte[] name;
    int namelen;
    int[] field_ids;
    int nfields;
    int[] method_ids;
    int nmethods;

    fn void setup(byte[] n, int nl) {
        this.name = n;
        this.namelen = nl;
        this.field_ids = new int[64];
        this.nfields = 0;
        this.method_ids = new int[64];
        this.nmethods = 0;
    }
}

class ExternLib {
    byte[] name;
    int namelen;

    fn void setup(byte[] n, int nl) {
        this.name = n;
        this.namelen = nl;
    }
}

class ExternFunc {
    byte[] name;      // MKJI-visible name
    int namelen;
    byte[] cname;     // symbol name in library
    int cnlen;
    int lib;          // index in Prog.extlibs
    int ret;
    int[] ptypes;
    int nparams;

    fn void setup(byte[] n, int nl, byte[] cn, int cnl, int lib, int retv) {
        this.nparams = 0;
    }
}

class Prog {
    Func[] funcs;
    int nfuncs;
    ClassInfo[] classes;
    int nclasses;
    FieldInfo[] fields;
    int nfields;
    MethodInfo[] methods;
    int nmethods;
    StrEnt[] strings;
    int nstrings;
    Stmt[] top;
    int ntop;
    VarEnt[] tvars;
    int ntvars;
    ExternLib[] extlibs;
    int nextlibs;
    ExternFunc[] externs;
    int nexterns;

    fn void setup() {
        this.funcs = new Func[256];
        this.nfuncs = 0;
        this.classes = new ClassInfo[128];
        this.nclasses = 0;
        this.fields = new FieldInfo[256];
        this.nfields = 0;
        this.methods = new MethodInfo[256];
        this.nmethods = 0;
        this.strings = new StrEnt[512];
        this.nstrings = 0;
        this.top = new Stmt[4096];
        this.ntop = 0;
        this.tvars = new VarEnt[256];
        this.ntvars = 0;
        this.extlibs = new ExternLib[64];
        this.nextlibs = 0;
        this.externs = new ExternFunc[256];
        this.nexterns = 0;
    }

    fn int find_extlib(byte[] n, int nl) {
        int i = 0;
        while (i < this.nextlibs) {
            if (names_eq(this.extlibs[i].name, this.extlibs[i].namelen, n, nl))
                return i;
            i = i + 1;
        }
        return -1;
    }

    fn int add_extlib(byte[] n, int nl) {
        int id = this.find_extlib(n, nl);
        if (id >= 0) return id;
        ExternLib e = new ExternLib();
        e.setup(n, nl);
        int idx = this.nextlibs;
        this.extlibs[idx] = e;
        this.nextlibs = idx + 1;
        return idx;
    }

    fn int find_extern(byte[] n, int nl) {
        int i = 0;
        while (i < this.nexterns) {
            if (names_eq(this.externs[i].name, this.externs[i].namelen, n, nl))
                return i;
            i = i + 1;
        }
        return -1;
    }

    fn int add_extern(ExternFunc f) {
        int id = this.nexterns;
        this.externs[id] = f;
        this.nexterns = id + 1;
        return id;
    }

    fn void add_tvar(byte[] n, int nl, int t) {
        VarEnt v = new VarEnt();
        v.setup(n, nl, t);
        this.tvars[this.ntvars] = v;
        this.ntvars = this.ntvars + 1;
    }

    fn int tvar_type(byte[] n, int nl) {
        int i = 0;
        while (i < this.ntvars) {
            if (names_eq(this.tvars[i].name, this.tvars[i].namelen, n, nl))
                return this.tvars[i].ty;
            i = i + 1;
        }
        return -1;
    }

    fn int find_func(byte[] n, int nl) {
        int i = 0;
        while (i < this.nfuncs) {
            if (names_eq(this.funcs[i].name, this.funcs[i].namelen, n, nl))
                return i;
            i = i + 1;
        }
        return -1;
    }

    fn int add_func(Func f) {
        int id = this.nfuncs;
        this.funcs[id] = f;
        this.nfuncs = id + 1;
        return id;
    }

    fn int find_class(byte[] n, int nl) {
        int i = 0;
        while (i < this.nclasses) {
            if (names_eq(this.classes[i].name, this.classes[i].namelen, n, nl))
                return i;
            i = i + 1;
        }
        return -1;
    }

    fn int add_field(byte[] n, int nl, int ty) {
        int i = 0;
        while (i < this.nfields) {
            if (names_eq(this.fields[i].name, this.fields[i].namelen, n, nl))
                return i;
            i = i + 1;
        }
        int id = this.nfields;
        FieldInfo fi = new FieldInfo();
        fi.setup(n, nl, ty);
        this.fields[id] = fi;
        this.nfields = id + 1;
        return id;
    }

    fn int field_type(int id) {
        if (id >= 0 && id < this.nfields) return this.fields[id].ty;
        return 1;
    }

    fn int add_method(byte[] n, int nl) {
        int i = 0;
        while (i < this.nmethods) {
            if (names_eq(this.methods[i].name, this.methods[i].namelen, n, nl))
                return i;
            i = i + 1;
        }
        int id = this.nmethods;
        MethodInfo mi = new MethodInfo();
        mi.setup(n, nl);
        this.methods[id] = mi;
        this.nmethods = id + 1;
        return id;
    }

    fn int method_ret(byte[] n, int nl) {
        int i = 0;
        while (i < this.nfuncs) {
            Func f = this.funcs[i];
            if (f.is_method && names_eq(f.name, f.namelen, n, nl))
                return f.ret;
            i = i + 1;
        }
        return 1;
    }

    fn int add_string(byte[] b, int nl) {
        int i = 0;
        while (i < this.nstrings) {
            if (this.strings[i].vlen == nl && names_eq(this.strings[i].value, this.strings[i].vlen, b, nl))
                return i;
            i = i + 1;
        }
        int id = this.nstrings;
        StrEnt se = new StrEnt();
        se.setup(b, nl, id);
        this.strings[id] = se;
        this.nstrings = id + 1;
        return id;
    }
}

class SlotEntry {
    byte[] name;
    int nlen;
    int slot;
    fn void setup(byte[] n, int nl, int s) {
        this.name = n; this.nlen = nl; this.slot = s;
    }
}

class Label {
    int sec;           // -1 = undefined
    int off;
    fn void setup(int s, int o) { this.sec = s; this.off = o; }
}

class Fixup {
    int id;            // label id
    int kind;          // 1 rel32, 2 abs64, 3 rip-relative
    int sec;
    int off;
    fn void setup(int i, int k, int s, int o) {
        this.id = i; this.kind = k; this.sec = s; this.off = o;
    }
}
