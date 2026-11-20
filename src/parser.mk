// MKJI 1.0 — парсер. Строит AST и таблицы программы.
use "core.mk";
use "lexer.mk";

// коды типов
// 0 void 1 int 2 bool 3 string 4 byte[] 5 int[] 6 class 7 class[]
// коды бинарных операций
// 1+ 2- 3* 4/ 5% 6== 7!= 8< 9<= 10> 11>= 12&& 13||
// 14& 15| 16^ 17<< 18>>
// кодыkind выражений
// 1 INT 2 STR 3 BOOL 4 NULL 5 VAR 6 THIS 7 BIN 8 UN 9 CALL
// 10 FIELD 11 INDEX 12 ASSIGN 13 NEW 14 LEN

fn Expr newexpr(int k) {
    Expr e = new Expr();
    e.setup(k);
    return e;
}

fn Stmt newstmt(int k) {
    Stmt s = new Stmt();
    s.setup(k);
    return s;
}

class Parser {
    Lexer lx;
    Prog prog;
    string[] included;
    int nincluded;
    Func curfunc;
    int curclass;
    string cur_path;

    fn void setup(Prog p) {
        this.prog = p;
        this.included = new string[64];
        this.nincluded = 0;
        this.curfunc = null;
        this.curclass = -1;
        this.cur_path = "";
        this.lx = new Lexer();
    }

    fn string path_dir(string path) {
        int i = path.len - 1;
        while (i >= 0) {
            int c = path[i];
            if (c == 47 || c == 92) {
                if (i <= 0) return "";
                byte[] b = new byte[i + 1];
                int j = 0;
                while (j <= i) { b[j] = path[j]; j = j + 1; }
                return str_from(b, i + 1);
            }
            i = i - 1;
        }
        return "";
    }

    fn bool is_abs_path(string path) {
        if (path.len <= 0) return false;
        int c0 = path[0];
        if (c0 == 47 || c0 == 92) return true;
        if (path.len >= 2 && path[1] == 58) return true;
        return false;
    }

    fn string resolve_include(string rel) {
        if (this.is_abs_path(rel)) return rel;
        string dir = this.path_dir(this.cur_path);
        if (dir.len == 0) return rel;
        int total = dir.len + rel.len;
        byte[] b = new byte[total];
        int i = 0;
        while (i < dir.len) { b[i] = dir[i]; i = i + 1; }
        int j = 0;
        while (j < rel.len) { b[i] = rel[j]; i = i + 1; j = j + 1; }
        return str_from(b, total);
    }

    fn bool kw(string s) { return this.lx.is_s(s); }
    fn bool p(int c) { return this.lx.is_p(c); }
    fn void eat(string s) { this.lx.expect_s(s); }
    fn void eatp(int c) { this.lx.expect_p(c); }
    fn void adv() { this.lx.next(); }

    fn bool is_type_start() {
        int k = this.lx.cur.kind;
        if (this.kw("int") || this.kw("bool") || this.kw("byte") ||
            this.kw("string") || this.kw("void")) return true;
        if (k == 1) return this.lx.next_is_ident();
        return false;
    }

    fn int parse_base_type() {
        int t = 1;
        if (this.kw("void")) { this.adv(); t = 0; }
        else if (this.kw("int")) { this.adv(); t = 1; }
        else if (this.kw("bool")) { this.adv(); t = 2; }
        else if (this.kw("byte")) { this.adv(); t = 4; }
        else if (this.kw("string")) { this.adv(); t = 3; }
        else {
            if (this.lx.cur.kind != 1) die("expected type name");
            this.adv();
            t = 6;
        }
        return t;
    }

    fn int parse_type() {
        int t = this.parse_base_type();
        while (this.p(91)) {
            this.eatp(91);
            this.eatp(93);
            if (t == 4) t = 4;
            else if (t == 6) t = 7;
            else if (t == 3) t = 8;
            else t = 5;
        }
        return t;
    }

    // ---------------- expressions ----------------
    fn Expr parse_primary() {
        if (this.lx.cur.kind == 2) {
            Expr e = newexpr(1);
            e.ival = this.lx.cur.ival;
            e.ty = 1;
            this.adv();
            return e;
        }
        if (this.lx.cur.kind == 3) {
            Expr e = newexpr(2);
            byte[] b = this.lx.cur.text;
            int n = this.lx.cur.ival;
            e.ival = this.prog.add_string(b, n);
            e.sval = b;
            e.slen = n;
            e.ty = 3;
            this.adv();
            return e;
        }
        if (this.kw("true") || this.kw("false")) {
            Expr e = newexpr(3);
            e.ival = 0;
            if (this.kw("true")) e.ival = 1;
            e.ty = 2;
            this.adv();
            return e;
        }
        if (this.kw("null")) {
            Expr e = newexpr(4);
            e.ty = 6;
            this.adv();
            return e;
        }
        if (this.kw("this")) {
            Expr e = newexpr(6);
            e.ty = 6;
            this.adv();
            return e;
        }
        if (this.kw("var")) die("typed declarations only");

        if (this.kw("print") || this.kw("panic") ||
            this.kw("read_file") || this.kw("write_file") ||
            this.kw("str_from") || this.kw("arg_count") || this.kw("get_arg")) {
            int id = -2;
            if (this.kw("panic")) id = -5;
            if (this.kw("read_file")) id = -3;
            if (this.kw("write_file")) id = -4;
            if (this.kw("str_from")) id = -6;
            if (this.kw("arg_count")) id = -7;
            if (this.kw("get_arg")) id = -8;
            this.adv();
            this.eatp(40);
            Expr e = newexpr(9);
            e.id = id;
            e.args = new Expr[16];
            e.nargs = 0;
            if (!this.p(41)) {
                bool more = true;
                while (more) {
                    e.args[e.nargs] = this.parse_expr();
                    e.nargs = e.nargs + 1;
                    if (this.p(44)) this.adv(); else more = false;
                }
            }
            this.eatp(41);
            if (id == -3) e.ty = 3;
            else if (id == -4) e.ty = 2;
            else if (id == -6) e.ty = 3;
            else if (id == -7) e.ty = 1;
            else if (id == -8) e.ty = 3;
            else e.ty = 0;
            return e;
        }

        if (this.lx.cur.kind == 1) {
            Expr e = newexpr(5);
            e.sval = this.lx.cur.text;
            e.slen = this.lx.cur.tlen;
            e.ty = 1;
            if (this.curfunc != null) {
                int lt = this.curfunc.local_type(e.sval, e.slen);
                if (lt >= 0) e.ty = lt;
                else {
                    int tt = this.prog.tvar_type(e.sval, e.slen);
                    if (tt >= 0) e.ty = tt;
                }
            } else {
                int tt = this.prog.tvar_type(e.sval, e.slen);
                if (tt >= 0) e.ty = tt;
            }
            this.adv();
            return e;
        }

        if (this.p(40)) {
            this.adv();
            Expr e = this.parse_expr();
            this.eatp(41);
            return e;
        }

        die("expected expression");
        return newexpr(1);
    }

    fn Expr parse_postfix() {
        Expr e = this.parse_primary();
        bool again = true;
        while (again) {
            if (this.p(46)) { // .
                this.adv();
                if (this.lx.cur.kind != 1) die("expected member name");
                byte[] nm = this.lx.cur.text;
                int nl = this.lx.cur.tlen;
                this.adv();
                if (this.p(40)) {
                    this.adv();
                    Expr c = newexpr(9);
                    c.a = e;
                    c.method = true;
                    c.id = this.prog.add_method(nm, nl);
                    c.args = new Expr[16];
                    c.nargs = 0;
                    if (!this.p(41)) {
                        bool more = true;
                        while (more) {
                            c.args[c.nargs] = this.parse_expr();
                            c.nargs = c.nargs + 1;
                            if (this.p(44)) this.adv(); else more = false;
                        }
                    }
                    this.eatp(41);
                    c.ty = this.prog.method_ret(nm, nl);
                    e = c;
                } else {
                    bool is_len = name_eq(nm, nl, "len");
                    if (is_len && (e.ty == 3 || e.ty == 4 || e.ty == 5 || e.ty == 7 || e.ty == 8)) {
                        Expr f = newexpr(14);
                        f.a = e;
                        f.ival = 1;
                        f.ty = 1;
                        e = f;
                    } else {
                        Expr f = newexpr(10);
                        f.a = e;
                        f.sval = nm;
                        f.slen = nl;
                        f.ival = this.prog.add_field(nm, nl, 1);
                        f.ty = this.prog.fields[f.ival].ty;
                        e = f;
                    }
                }
            } else if (this.p(40)) {
                this.adv();
                Expr c = newexpr(9);
                c.method = false;
                c.args = new Expr[16];
                c.nargs = 0;
                if (!this.p(41)) {
                    bool more = true;
                    while (more) {
                        c.args[c.nargs] = this.parse_expr();
                        c.nargs = c.nargs + 1;
                        if (this.p(44)) this.adv(); else more = false;
                    }
                }
                this.eatp(41);
                if (e.kind == 5) {
                    c.id = this.prog.find_func(e.sval, e.slen);
                    c.sval = e.sval;
                    c.slen = e.slen;
                    if (c.id >= 0) c.ty = this.prog.funcs[c.id].ret;
                    else c.ty = 1;
                } else {
                    c.id = -1;
                    c.ty = 1;
                }
                e = c;
            } else if (this.p(91)) { // [
                this.adv();
                Expr idx = this.parse_expr();
                this.eatp(93);
                Expr n = newexpr(11);
                n.a = e;
                n.b = idx;
                if (e.ty == 3 || e.ty == 4) n.ty = 1;
                else if (e.ty == 5) n.ty = 1;
                else if (e.ty == 7) n.ty = 6;
                else if (e.ty == 8) n.ty = 3;
                else n.ty = 1;
                e = n;
            } else {
                again = false;
            }
        }
        return e;
    }

    fn Expr parse_unary() {
        if (this.p(45) || this.p(33) || this.p(38) || this.p(124) || this.p(94)) {
            int ch = this.lx.cur.text[0];
            int op = 1;
            if (ch == 45) op = 1;
            if (ch == 33) op = 2;
            if (ch == 38) op = 14;
            if (ch == 124) op = 15;
            if (ch == 94) op = 16;
            this.adv();
            Expr e = newexpr(8);
            e.op = op;
            e.a = this.parse_unary();
            e.ty = e.a.ty;
            return e;
        }
        if (this.kw("new")) {
            this.adv();
            // base type: may be class name
            byte[] cname = null;
            int cnlen = 0;
            int base = 1;
            if (this.kw("void")) { this.adv(); base = 0; }
            else if (this.kw("int")) { this.adv(); base = 1; }
            else if (this.kw("bool")) { this.adv(); base = 2; }
            else if (this.kw("byte")) { this.adv(); base = 4; }
            else if (this.kw("string")) { this.adv(); base = 3; }
            else {
                if (this.lx.cur.kind != 1) die("expected type name after new");
                cname = this.lx.cur.text;
                cnlen = this.lx.cur.tlen;
                this.adv();
                base = 6;
            }
            if (this.p(91)) {
                this.adv();
                Expr len = this.parse_expr();
                this.eatp(93);
                Expr e = newexpr(13);
                e.a = len;
                e.ival = 1; // is_array
                int aty = 5;
                if (base == 4) aty = 4;
                else if (base == 6) aty = 7;
                else if (base == 3) aty = 8;
                else aty = 5;
                e.ty = aty;
                e.id = -1;
                return e;
            }
            if (base != 6) die("new expects class or array type");
            Expr e = newexpr(13);
            e.ival = 0; // class instance
            int cid = this.prog.find_class(cname, cnlen);
            e.id = cid;
            e.sval = cname;
            e.slen = cnlen;
            e.ty = 6;
            e.args = new Expr[16];
            e.nargs = 0;
            if (this.p(40)) {
                this.adv();
                if (!this.p(41)) {
                    bool more = true;
                    while (more) {
                        e.args[e.nargs] = this.parse_expr();
                        e.nargs = e.nargs + 1;
                        if (this.p(44)) this.adv(); else more = false;
                    }
                }
                this.eatp(41);
            }
            return e;
        }
        return this.parse_postfix();
    }

    fn Expr parse_bin_left(int minprec) {
        Expr l = this.parse_unary();
        bool again = true;
        while (again) {
            int op = 0;
            int prec = 0;
            Tok t = this.lx.cur;
            if (t.kind == 4 && t.tlen == 1) {
                int c = t.text[0];
                if (c == 42) { op = 3; prec = 7; }
                if (c == 47) { op = 4; prec = 7; }
                if (c == 37) { op = 5; prec = 7; }
                if (c == 43) { op = 1; prec = 6; }
                if (c == 45) { op = 2; prec = 6; }
                if (c == 60) { op = 8; prec = 4; }
                if (c == 62) { op = 10; prec = 4; }
                if (c == 38) { op = 14; prec = 5; }
                if (c == 124) { op = 15; prec = 3; }
                if (c == 94) { op = 16; prec = 2; }
            } else if (t.kind == 4 && t.tlen == 2) {
                int a = t.text[0];
                int b = t.text[1];
                if (a == 60 && b == 60) { op = 17; prec = 6; }
                if (a == 62 && b == 62) { op = 18; prec = 6; }
                if (a == 61 && b == 61) { op = 6; prec = 4; }
                if (a == 33 && b == 61) { op = 7; prec = 4; }
                if (a == 60 && b == 61) { op = 9; prec = 4; }
                if (a == 62 && b == 61) { op = 11; prec = 4; }
                if (a == 38 && b == 38) { op = 12; prec = 1; }
                if (a == 124 && b == 124) { op = 13; prec = 1; }
            }
            if (op == 0 || prec < minprec) {
                again = false;
            } else {
                this.adv();
                Expr r = this.parse_bin_left(prec + 1);
                Expr n = newexpr(7);
                n.op = op;
                n.a = l;
                n.b = r;
                if (op >= 6 && op <= 13) n.ty = 2;
                else n.ty = l.ty;
                l = n;
            }
        }
        return l;
    }

    fn Expr parse_expr() {
        Expr e = this.parse_bin_left(1);
        if (this.p(61)) { // =
            this.adv();
            Expr r = this.parse_expr();
            if (e.kind != 5 && e.kind != 10 && e.kind != 11)
                die("invalid assignment target");
            Expr n = newexpr(12);
            n.a = e;
            n.b = r;
            n.ty = e.ty;
            return n;
        }
        return e;
    }

    // ---------------- statements ----------------
    fn Stmt parse_block() {
        this.eatp(123);
        Stmt b = newstmt(6);
        b.list = new Stmt[1024];
        b.n = 0;
        while (!this.p(125) && this.lx.cur.kind != 5) {
            b.list[b.n] = this.parse_stmt();
            b.n = b.n + 1;
        }
        this.eatp(125);
        return b;
    }

    fn Stmt parse_fn(int class_id, bool method) {
        int line = this.lx.cur.line;
        int col = this.lx.cur.col;
        this.eat("fn");
        int ret = this.parse_type();
        if (this.lx.cur.kind != 1) die("expected function name");
        byte[] nm = this.lx.cur.text;
        int nl = this.lx.cur.tlen;
        this.adv();
        this.eatp(40);
        Func f = new Func();
        f.setup(nm, nl, ret);
        f.is_method = method;
        f.class_id = class_id;
        if (!this.p(41)) {
            bool more = true;
            while (more) {
                int pt = this.parse_type();
                if (this.lx.cur.kind != 1) die("expected parameter name");
                Param pm = new Param();
                pm.setup(this.lx.cur.text, this.lx.cur.tlen);
                f.params[f.nparams] = pm;
                f.ptypes[f.nparams] = pt;
                f.nparams = f.nparams + 1;
                this.adv();
                f.add_local(pm.name, pm.namelen, pt);
                if (this.p(44)) this.adv(); else more = false;
            }
        }
        this.eatp(41);
        int fid = this.prog.add_func(f);
        Func saved = this.curfunc;
        this.curfunc = f;
        f.body = this.parse_block();
        this.curfunc = saved;
        Stmt s = newstmt(7);
        s.fnid = fid;
        s.id = fid;
        s.line = line;
        s.col = col;
        return s;
    }

    fn Stmt parse_class() {
        int line = this.lx.cur.line;
        this.eat("class");
        if (this.lx.cur.kind != 1) die("expected class name");
        byte[] nm = this.lx.cur.text;
        int nl = this.lx.cur.tlen;
        this.adv();
        if (this.prog.find_class(nm, nl) >= 0) die("duplicate class");
        ClassInfo ci = new ClassInfo();
        ci.setup(nm, nl);
        int cid = this.prog.nclasses;
        this.prog.classes[cid] = ci;
        this.prog.nclasses = cid + 1;
        int saved_class = this.curclass;
        this.curclass = cid;
        Stmt b = newstmt(6);
        b.list = new Stmt[256];
        b.n = 0;
        this.eatp(123);
        while (!this.p(125) && this.lx.cur.kind != 5) {
            if (this.kw("fn")) {
                Stmt fstmt = this.parse_fn(cid, true);
                int fid = fstmt.fnid;
                int mid = this.prog.add_method(this.prog.funcs[fid].name,
                                               this.prog.funcs[fid].namelen);
                ci.method_ids[ci.nmethods] = mid;
                ci.nmethods = ci.nmethods + 1;
                b.list[b.n] = fstmt;
                b.n = b.n + 1;
            } else if (this.is_type_start()) {
                int ft = this.parse_type();
                if (this.lx.cur.kind != 1) die("expected field name");
                byte[] fnm = this.lx.cur.text;
                int fnl = this.lx.cur.tlen;
                this.adv();
                int fid = this.prog.add_field(fnm, fnl, ft);
                ci.field_ids[ci.nfields] = fid;
                ci.nfields = ci.nfields + 1;
                this.eatp(59);
            } else {
                die("only fields and fn allowed in class");
            }
        }
        this.eatp(125);
        this.curclass = saved_class;
        Stmt s = newstmt(8);
        s.id = cid;
        s.line = line;
        return s;
    }

    fn void parse_file(string path) {
        int i = 0;
        while (i < this.nincluded) {
            if (this.included[i] == path) return;
            i = i + 1;
        }
        this.included[this.nincluded] = path;
        this.nincluded = this.nincluded + 1;
        string text = read_file(path);
        if (text == null) die("cannot open included file");
        Lexer saved_lx = this.lx;
        string saved_path = this.cur_path;
        this.cur_path = path;
        this.lx = new Lexer();
        this.lx.setup(text);
        while (this.lx.cur.kind != 5) {
            Stmt s = this.parse_stmt();
            this.prog.top[this.prog.ntop] = s;
            this.prog.ntop = this.prog.ntop + 1;
        }
        this.lx = saved_lx;
        this.cur_path = saved_path;
    }

    fn Stmt parse_stmt() {
        int line = this.lx.cur.line;
        int col = this.lx.cur.col;
        if (this.p(123)) return this.parse_block();
        if (this.p(59)) { this.adv(); return newstmt(0); }
        if (this.kw("use")) {
            this.adv();
            if (this.lx.cur.kind != 3) die("use expects a string path");
            string path = str_from(this.lx.cur.text, this.lx.cur.ival);
            this.adv();
            this.eatp(59);
            string rpath = this.resolve_include(path);
            this.parse_file(rpath);
            return newstmt(0);
        }
        if (this.kw("var")) die("typed declarations only");
        if (this.kw("fn")) return this.parse_fn(-1, false);
        if (this.kw("class")) return this.parse_class();
        if (this.kw("if")) {
            this.adv();
            this.eatp(40);
            Expr c = this.parse_expr();
            this.eatp(41);
            Stmt s = newstmt(3);
            s.cond = c;
            s.then_b = this.parse_stmt();
            s.else_b = null;
            if (this.kw("else")) {
                this.adv();
                s.else_b = this.parse_stmt();
            }
            return s;
        }
        if (this.kw("while")) {
            this.adv();
            this.eatp(40);
            Expr c = this.parse_expr();
            this.eatp(41);
            Stmt s = newstmt(4);
            s.cond = c;
            s.body = this.parse_stmt();
            return s;
        }
        if (this.kw("return")) {
            this.adv();
            Stmt s = newstmt(5);
            if (this.p(59)) s.e = null;
            else s.e = this.parse_expr();
            this.eatp(59);
            return s;
        }
        if (this.is_type_start() && !this.kw("void")) {
            int t = this.parse_type();
            if (this.lx.cur.kind != 1) die("expected variable name");
            byte[] nm = this.lx.cur.text;
            int nl = this.lx.cur.tlen;
            Stmt s = newstmt(2);
            s.name = nm;
            s.namelen = nl;
            s.ty = t;
            s.line = line;
            s.col = col;
            this.adv();
            if (this.curfunc != null) this.curfunc.add_local(nm, nl, t);
            else this.prog.add_tvar(nm, nl, t);
            s.e = null;
            if (this.p(61)) {
                this.adv();
                s.e = this.parse_expr();
            }
            this.eatp(59);
            return s;
        }
        Expr e = this.parse_expr();
        this.eatp(59);
        Stmt s = newstmt(1);
        s.e = e;
        s.line = line;
        s.col = col;
        return s;
    }

    fn void parse_all(string path) { this.parse_file(path); }
}
