// MKJI 1.0 — генерация кода (на MKJI).
use "core.mk";
use "emit.mk";

// regs: RAX=0 RCX=1 RDX=2 RBX=3 RSP=4 RBP=5 RSI=6 RDI=7 R8=8 R9=9 R10=10 R11=11
// cc: 0=e 1=ne 2=l 3=le 4=g 5=ge
// expr: 1 INT 2 STR 3 BOOL 4 NULL 5 VAR 6 THIS 7 BIN 8 UN 9 CALL
//       10 FIELD 11 INDEX 12 ASSIGN 13 NEW 14 LEN
// stmt: 0 EMPTY 1 EXPR 2 VAR 3 IF 4 WHILE 5 RETURN 6 BLOCK 7 FN 8 CLASS
// binop: 1+ 2- 3* 4/ 5% 6== 7!= 8< 9<= 10> 11>= 12&& 13|| 14& 15| 16^ 17<< 18>>
// ty: 0 void 1 int 2 bool 3 string 4 byte[] 5 int[] 6 class 7 class[]

class Codegen {
    Image img;
    Prog prog;

    SlotEntry[] slots;
    int nslots;
    int slot_count;

    fn void setup(Image img, Prog prog) {
        this.img = img;
        this.prog = prog;
    }

    fn int tmp() { return this.img.new_label(); }

    fn void reset_slots() {
        this.slots = new SlotEntry[512];
        this.nslots = 0;
        this.slot_count = 0;
    }

    fn int slot_of(byte[] name, int nlen) {
        int i = 0;
        while (i < this.nslots) {
            if (names_eq(this.slots[i].name, this.slots[i].nlen, name, nlen))
                return this.slots[i].slot;
            i = i + 1;
        }
        int slot = this.slot_count;
        SlotEntry se = new SlotEntry();
        se.setup(name, nlen, slot);
        this.slots[this.nslots] = se;
        this.nslots = this.nslots + 1;
        this.slot_count = slot + 1;
        return slot;
    }

    fn void load_slot(int slot) { this.img.mov_r_mem(0, 5, -8 * (slot + 1)); }
    fn void store_slot(int slot) { this.img.mov_mem_r(5, -8 * (slot + 1), 0); }

    fn void setcc_bool(int cc) {
        this.img.setcc(0, cc);
        this.img.movzx_r8_r(0, 0);
    }

    fn string fn_name(int id) {
        byte[] b = new byte[20];
        b[0] = 102; b[1] = 110; b[2] = 95;
        int n = 3;
        if (id == 0) { b[n] = 48; n = n + 1; }
        else {
            byte[] tmp = new byte[12];
            int t = 0;
            int v = id;
            while (v > 0) { tmp[t] = 48 + (v % 10); t = t + 1; v = v / 10; }
            int k = t - 1;
            while (k >= 0) { b[n] = tmp[k]; n = n + 1; k = k - 1; }
        }
        return str_from(b, n);
    }

    fn string vt_name(int cid) {
        byte[] b = new byte[20];
        b[0] = 118; b[1] = 116; b[2] = 95;
        int n = 3;
        if (cid == 0) { b[n] = 48; n = n + 1; }
        else {
            byte[] tmp = new byte[12];
            int t = 0;
            int v = cid;
            while (v > 0) { tmp[t] = 48 + (v % 10); t = t + 1; v = v / 10; }
            int k = t - 1;
            while (k >= 0) { b[n] = tmp[k]; n = n + 1; k = k - 1; }
        }
        return str_from(b, n);
    }

    fn string cname_label(int cid) {
        byte[] b = new byte[20];
        b[0] = 99; b[1] = 110; b[2] = 97; b[3] = 109; b[4] = 101; b[5] = 95;
        int n = 6;
        if (cid == 0) { b[n] = 48; n = n + 1; }
        else {
            byte[] tmp = new byte[12];
            int t = 0;
            int v = cid;
            while (v > 0) { tmp[t] = 48 + (v % 10); t = t + 1; v = v / 10; }
            int k = t - 1;
            while (k >= 0) { b[n] = tmp[k]; n = n + 1; k = k - 1; }
        }
        return str_from(b, n);
    }

    fn string str_label(int id) {
        byte[] b = new byte[20];
        b[0] = 115; b[1] = 116; b[2] = 114; b[3] = 95;
        int n = 4;
        if (id == 0) { b[n] = 48; n = n + 1; }
        else {
            byte[] tmp = new byte[12];
            int t = 0;
            int v = id;
            while (v > 0) { tmp[t] = 48 + (v % 10); t = t + 1; v = v / 10; }
            int k = t - 1;
            while (k >= 0) { b[n] = tmp[k]; n = n + 1; k = k - 1; }
        }
        return str_from(b, n);
    }

    // ---- slot assignment ----
    fn void assign_expr(Expr e) {
        if (e == null) return;
        if (e.kind == 5) {
            e.slot = this.slot_of(e.sval, e.slen);
        } else if (e.kind == 7) {
            this.assign_expr(e.a); this.assign_expr(e.b);
        } else if (e.kind == 8) {
            this.assign_expr(e.a);
        } else if (e.kind == 9) {
            if (e.a != null) this.assign_expr(e.a);
            int k = 0;
            while (k < e.nargs) { this.assign_expr(e.args[k]); k = k + 1; }
        } else if (e.kind == 10) {
            this.assign_expr(e.a);
        } else if (e.kind == 11) {
            this.assign_expr(e.a); this.assign_expr(e.b);
        } else if (e.kind == 12) {
            this.assign_expr(e.a); this.assign_expr(e.b);
        } else if (e.kind == 13) {
            if (e.ival == 1) { this.assign_expr(e.a); }
            else {
                int k = 0;
                while (k < e.nargs) { this.assign_expr(e.args[k]); k = k + 1; }
            }
        } else if (e.kind == 14) {
            this.assign_expr(e.a);
        }
    }

    fn void assign_stmt(Stmt s) {
        if (s == null) return;
        if (s.kind == 1) {
            this.assign_expr(s.e);
        } else if (s.kind == 2) {
            s.slot = this.slot_of(s.name, s.namelen);
            this.assign_expr(s.e);
        } else if (s.kind == 3) {
            this.assign_expr(s.cond);
            this.assign_stmt(s.then_b);
            this.assign_stmt(s.else_b);
        } else if (s.kind == 4) {
            this.assign_expr(s.cond);
            this.assign_stmt(s.body);
        } else if (s.kind == 5) {
            this.assign_expr(s.e);
        } else if (s.kind == 6) {
            int k = 0;
            while (k < s.n) { this.assign_stmt(s.list[k]); k = k + 1; }
        }
    }

    fn void emit_check_ptr() {
        int ok = this.tmp();
        this.img.test_rr(0, 0);
        this.img.jcc_id(1, ok);
        this.img.lea_rip(0, "msg_null_deref");
        this.img.mov_ri(1, 17);
        this.img.call("_panic");
        this.img.mark_id(ok, 0, this.img.code.len);
    }

    fn void emit_short_circuit(Expr l, Expr r, int op) {
        int short_lbl = this.tmp();
        int end_lbl = this.tmp();
        this.emit_expr(l);
        this.img.test_rr(0, 0);
        if (op == 12) this.img.jcc_id(0, short_lbl); else this.img.jcc_id(1, short_lbl);
        this.emit_expr(r);
        this.img.test_rr(0, 0);
        if (op == 12) this.img.jcc_id(0, short_lbl); else this.img.jcc_id(1, short_lbl);
        if (op == 12) this.img.mov_ri(0, 1); else this.img.mov_ri(0, 0);
        this.img.jmp_id(end_lbl);
        this.img.mark_id(short_lbl, 0, this.img.code.len);
        if (op == 12) this.img.mov_ri(0, 0); else this.img.mov_ri(0, 1);
        this.img.mark_id(end_lbl, 0, this.img.code.len);
    }

    fn void emit_push_args(Expr[] args, int n) {
        int k = 0;
        while (k < n) { this.emit_expr(args[k]); this.img.push(0); k = k + 1; }
    }

    fn void emit_pop_meth(int n) {
        if (n >= 4) this.img.pop(9);
        if (n >= 3) this.img.pop(8);
        if (n >= 2) this.img.pop(2);
        if (n >= 1) this.img.pop(1);
    }

    fn void emit_pop_free(int n) {
        if (n >= 4) this.img.pop(8);
        if (n >= 3) this.img.pop(2);
        if (n >= 2) this.img.pop(1);
        if (n >= 1) this.img.pop(0);
    }

    fn void emit_new_expr(Expr e) {
        if (e.ival == 1) {
            this.emit_expr(e.a);
            this.img.push(0);
            this.img.mov_rr(1, 0);
            if (e.ty == 4) { this.img.add_ri(1, 8); }
            else { this.img.shl_ri(1, 3); this.img.add_ri(1, 8); }
            this.img.mov_rr(0, 1);
            this.img.call("_alloc");
            this.img.pop(1);
            this.img.mov_mem_r(0, 0, 1);
            return;
        }
        int cid = e.id;
        int nf = this.prog.nfields;
        int size = 8 + 8 * nf;
        this.img.mov_ri(0, size);
        this.img.call("_alloc");
        string vt = this.vt_name(cid);
        this.img.mov_abs(11, vt);
        this.img.mov_mem_r(0, 0, 11);
        this.img.mov_ri(11, 0);
        int k = 0;
        while (k < nf) { this.img.mov_mem_r(0, 8 + 8 * k, 11); k = k + 1; }
        this.img.push(0);
        this.emit_push_args(e.args, e.nargs);
        this.emit_pop_meth(e.nargs);
        this.img.pop(0);
        this.img.push(0);
        int init_f = this.find_init(cid);
        if (init_f >= 0) {
            this.img.e8(0xE8);
            int off = this.img.code.len;
            this.img.e32(0);
            this.img.fix_id(this.img.sym(this.fn_name(init_f)), 1, 0, off);
        }
        this.img.pop(0);
    }

    fn int find_init(int cid) {
        int k = 0;
        while (k < this.prog.nfuncs) {
            Func f = this.prog.funcs[k];
            if (f.is_method && f.class_id == cid && name_eq(f.name, f.namelen, "init"))
                return k;
            k = k + 1;
        }
        return -1;
    }

    fn void emit_call_expr(Expr e) {
        int n = e.nargs;
        if (e.id == -3) {
            this.emit_expr(e.args[0]);
            this.img.call("_read_file");
            return;
        }
        if (e.id == -4) {
            this.emit_expr(e.args[0]);
            this.img.push(0);
            this.emit_expr(e.args[1]);
            this.img.mov_rr(1, 0);
            this.img.pop(0);
            this.img.call("_write_file");
            return;
        }
        if (e.id == -6) {
            this.emit_expr(e.args[0]);
            this.img.push(0);
            this.emit_expr(e.args[1]);
            this.img.mov_rr(1, 0);
            this.img.pop(0);
            this.img.call("_str_from");
            return;
        }
        if (e.id == -5) {
            this.emit_expr(e.args[0]);
            this.img.mov_r_mem(1, 0, 8);
            this.img.add_ri(0, 16);
            this.img.call("_panic");
            return;
        }
        if (e.id == -2) {
            this.emit_expr(e.args[0]);
            int aty = e.args[0].ty;
            if (aty == 2) this.img.call("_print_bool");
            else if (aty == 3) this.img.call("_print_string");
            else if (aty == 6 || aty == 7 || aty == 8) this.img.call("_print_object");
            else this.img.call("_print_int");
            return;
        }
        if (e.id == -7) {
            this.img.call("_arg_count");
            return;
        }
        if (e.id == -8) {
            this.emit_expr(e.args[0]);
            this.img.call("_get_arg");
            return;
        }
        if (e.method) {
            this.emit_expr(e.a);
            this.img.push(0);
            this.emit_check_ptr();
            this.img.mov_r_mem(11, 0, 0);
            this.img.mov_r_mem(10, 11, 24 + 8 * e.id);
            this.img.test_rr(10, 10);
            int have = this.tmp();
            this.img.jcc_id(1, have);
            this.img.lea_rip(0, "msg_no_method");
            this.img.mov_ri(1, 15);
            this.img.call("_panic");
            this.img.mark_id(have, 0, this.img.code.len);
            this.img.push(10);
            this.emit_push_args(e.args, n);
            this.emit_pop_meth(n);
            this.img.pop(11);
            this.img.pop(0);
            this.img.call_reg(11);
            return;
        }
        int fid = e.id;
        if (fid < 0) {
            fid = this.prog.find_func(e.sval, e.slen);
            if (fid < 0) die("unknown function");
            e.id = fid;
            e.ty = this.prog.funcs[fid].ret;
        }
        this.emit_push_args(e.args, n);
        this.emit_pop_free(n);
        this.img.e8(0xE8);
        int off = this.img.code.len;
        this.img.e32(0);
        this.img.fix_id(this.img.sym(this.fn_name(fid)), 1, 0, off);
    }

    fn void emit_expr(Expr e) {
        if (e == null) return;
        if (e.kind == 1) { // INT
            this.img.mov_ri(0, e.ival);
        } else if (e.kind == 2) { // STR
            this.img.mov_abs(0, this.str_label(e.ival));
        } else if (e.kind == 3) { // BOOL
            int v = 0;
            if (e.ival != 0) v = 1;
            this.img.mov_ri(0, v);
        } else if (e.kind == 4) { // NULL
            this.img.mov_ri(0, 0);
        } else if (e.kind == 5) { // VAR
            this.load_slot(e.slot);
        } else if (e.kind == 6) { // THIS
            this.load_slot(0);
        } else if (e.kind == 10) { // FIELD (global field id in e.ival)
            this.emit_expr(e.a);
            this.emit_check_ptr();
            this.img.mov_r_mem(0, 0, 8 + 8 * e.ival);
        } else if (e.kind == 14) { // LEN
            this.emit_expr(e.a);
            int bty = e.a.ty;
            if (bty == 3) this.img.mov_r_mem(0, 0, 8); // string
            else this.img.mov_r_mem(0, 0, 0); // array
        } else if (e.kind == 11) { // INDEX
            this.emit_expr(e.a);
            this.img.push(0);
            this.emit_expr(e.b); // index in RAX
            this.img.pop(1);     // base in RCX
            int bty = e.a.ty;
            if (bty == 3) {
                this.img.add_rr(0, 1);
                this.img.add_ri(0, 16);
                this.img.movzx_r8_mem(0, 0, 0);
            } else if (bty == 4) {
                this.img.add_rr(0, 1);
                this.img.add_ri(0, 8);
                this.img.movzx_r8_mem(0, 0, 0);
            } else {
                this.img.shl_ri(0, 3);
                this.img.add_rr(0, 1);
                this.img.add_ri(0, 8);
                this.img.mov_r_mem(0, 0, 0);
            }
        } else if (e.kind == 12) { // ASSIGN
            Expr l = e.a;
            this.emit_expr(e.b); // value in RAX
            if (l.kind == 5) {
                this.store_slot(l.slot);
            } else if (l.kind == 10) {
                this.img.push(0);
                this.emit_expr(l.a);
                this.img.pop(2); // value in RDX
                this.emit_check_ptr();
                this.img.mov_mem_r(0, 8 + 8 * l.ival, 2);
                this.img.mov_rr(0, 2);
            } else if (l.kind == 11) {
                this.img.push(0); // value
                this.emit_expr(l.a);
                this.img.push(0); // base
                this.emit_expr(l.b);
                this.img.pop(11); // base
                this.img.pop(2);  // value
                int bty = l.a.ty;
                if (bty == 3 || bty == 4) {
                    this.img.add_rr(0, 11);
                    if (bty == 3) this.img.add_ri(0, 16); else this.img.add_ri(0, 8);
                    this.img.mov_mem8_r(0, 0, 2);
                } else {
                    this.img.shl_ri(0, 3);
                    this.img.add_rr(0, 11);
                    this.img.add_ri(0, 8);
                    this.img.mov_mem_r(0, 0, 2);
                }
                this.img.mov_rr(0, 2);
            } else {
                die("invalid assignment target");
            }
        } else if (e.kind == 13) { // NEW
            this.emit_new_expr(e);
        } else if (e.kind == 9) { // CALL
            this.emit_call_expr(e);
        } else if (e.kind == 8) { // UN
            this.emit_expr(e.a);
            if (e.op == 1) { // NEG
                this.img.neg(0);
            } else { // NOT bool
                this.img.xor_ri(0, 1);
            }
        } else if (e.kind == 7) { // BIN
            int op = e.op;
            if (op == 12 || op == 13) {
                this.emit_short_circuit(e.a, e.b, op);
                return;
            }
            this.emit_expr(e.a);
            this.img.push(0);
            this.emit_expr(e.b);
            this.img.pop(1); // RCX = left, RAX = right
            if (op >= 6 && op <= 11) {
                if (op == 6 || op == 7) {
                    if (e.a.ty == 3) {
                        this.img.mov_rr(8, 0);
                        this.img.mov_rr(0, 1);
                        this.img.mov_rr(1, 8);
                        this.img.call("_str_eq");
                        if (op == 7) this.img.xor_ri(0, 1);
                    } else {
                        this.img.mov_rr(8, 0);
                        this.img.mov_rr(0, 1);
                        this.img.cmp_rr(0, 8);
                        if (op == 6) this.setcc_bool(0); else this.setcc_bool(1);
                    }
                } else {
                    this.img.mov_rr(8, 0);
                    this.img.mov_rr(0, 1);
                    this.img.cmp_rr(0, 8);
                    if (op == 8) this.setcc_bool(2);
                    else if (op == 9) this.setcc_bool(3);
                    else if (op == 10) this.setcc_bool(4);
                    else this.setcc_bool(5);
                }
            } else {
                this.img.mov_rr(8, 0); // right
                this.img.mov_rr(0, 1); // left
                if (op == 1) this.img.add_rr(0, 8);
                else if (op == 2) this.img.sub_rr(0, 8);
                else if (op == 3) this.img.imul_rr(0, 8);
                else if (op == 4) { this.img.cqo(); this.img.idiv(8); }
                else if (op == 5) { this.img.cqo(); this.img.idiv(8); this.img.mov_rr(0, 2); }
                else if (op == 14) this.img.and_rr(0, 8);
                else if (op == 15) this.img.bor_rr(0, 8);
                else if (op == 16) this.img.bxor_rr(0, 8);
                else if (op == 17) { this.img.mov_rr(1, 8); this.img.and_ri(1, 63); this.img.shl_cl(0); }
                else if (op == 18) { this.img.mov_rr(1, 8); this.img.and_ri(1, 63); this.img.sar_cl(0); }
            }
        }
    }

    fn void emit_stmt(Stmt s) {
        if (s == null) return;
        if (s.kind == 0) return;
        if (s.kind == 1) {
            this.emit_expr(s.e);
        } else if (s.kind == 2) {
            if (s.e != null) { this.emit_expr(s.e); this.store_slot(s.slot); }
        } else if (s.kind == 5) {
            if (s.e != null) this.emit_expr(s.e); else this.img.mov_ri(0, 0);
            this.img.mov_rr(4, 5); this.img.pop(5); this.img.ret();
        } else if (s.kind == 6) {
            int k = 0;
            while (k < s.n) { this.emit_stmt(s.list[k]); k = k + 1; }
        } else if (s.kind == 3) {
            this.emit_expr(s.cond);
            this.img.test_rr(0, 0);
            int els = this.tmp();
            int end = this.tmp();
            if (s.else_b != null) this.img.jcc_id(0, els); else this.img.jcc_id(0, end);
            this.emit_stmt(s.then_b);
            if (s.else_b != null) {
                this.img.jmp_id(end);
                this.img.mark_id(els, 0, this.img.code.len);
                this.emit_stmt(s.else_b);
            }
            this.img.mark_id(end, 0, this.img.code.len);
        } else if (s.kind == 4) {
            int cond = this.tmp();
            int end = this.tmp();
            this.img.mark_id(cond, 0, this.img.code.len);
            this.emit_expr(s.cond);
            this.img.test_rr(0, 0);
            this.img.jcc_id(0, end);
            this.emit_stmt(s.body);
            this.img.jmp_id(cond);
            this.img.mark_id(end, 0, this.img.code.len);
        }
    }

    fn void emit_function(int id, Stmt body) {
        Func f = null;
        if (id >= 0) f = this.prog.funcs[id];
        this.reset_slots();
        if (f != null && f.is_method) {
            byte[] thisnm = bytes("this");
            this.slot_of(thisnm, 4);
        }
        if (f != null) {
            int k = 0;
            while (k < f.nparams) {
                this.slot_of(f.params[k].name, f.params[k].namelen);
                k = k + 1;
            }
        }
        this.assign_stmt(body);
        int slots = this.slot_count;
        int frame = slots * 8;
        int rem = frame % 16;
        if (rem != 0) frame = frame + (16 - rem);
        string lab = "mk_main";
        if (id >= 0) lab = this.fn_name(id);
        this.img.mark(lab, 0, this.img.code.len);
        this.img.push(5);
        this.img.mov_rr(5, 4);
        if (frame > 0) this.img.sub_ri(4, frame);
        if (f != null) {
            if (f.is_method) {
                this.img.mov_mem_r(5, -8, 0); // this
                if (f.nparams >= 1) this.img.mov_mem_r(5, -16, 1);
                if (f.nparams >= 2) this.img.mov_mem_r(5, -24, 2);
                if (f.nparams >= 3) this.img.mov_mem_r(5, -32, 8);
                if (f.nparams >= 4) this.img.mov_mem_r(5, -40, 9);
            } else {
                if (f.nparams >= 1) this.img.mov_mem_r(5, -8, 0);
                if (f.nparams >= 2) this.img.mov_mem_r(5, -16, 1);
                if (f.nparams >= 3) this.img.mov_mem_r(5, -24, 2);
                if (f.nparams >= 4) this.img.mov_mem_r(5, -32, 8);
            }
        }
        this.emit_stmt(body);
        this.img.mov_ri(0, 0);
        this.img.mov_rr(4, 5);
        this.img.pop(5);
        this.img.ret();
    }

    fn void build_main_body() {
        // synthesize top-level statements as mk_main body
        Stmt b = new Stmt();
        b.setup(6);
        b.list = new Stmt[this.prog.ntop];
        b.n = 0;
        int k = 0;
        while (k < this.prog.ntop) {
            Stmt s = this.prog.top[k];
            // skip fn/class declarations at top-level emission time
            if (s.kind != 7 && s.kind != 8) {
                b.list[b.n] = s;
                b.n = b.n + 1;
            }
            k = k + 1;
        }
        this.emit_function(-1, b);
    }

    fn void emit_program() {
        int k = 0;
        while (k < this.prog.nfuncs) {
            this.emit_function(k, this.prog.funcs[k].body);
            k = k + 1;
        }
        this.build_main_body();
    }

    fn void data_strz(string s) {
        byte[] b = bytes(s);
        this.img.data.write(b, s.len);
        this.img.data.put(0);
    }

    fn void data_abs(string lbl) {
        int off = this.img.data.len;
        this.img.data.u64(0);
        this.img.fix(lbl, 2, 1, off);
    }

    fn void build_data() {
        this.img.mark("heap_ptr", 1, this.img.data.len);
        this.img.data.u64(0);
        this.img.mark("heap_end", 1, this.img.data.len);
        this.img.data.u64(0);
        this.img.mark("bytes_written", 1, this.img.data.len);
        this.img.data.u64(0);
        this.img.mark("__argc", 1, this.img.data.len);
        this.img.data.u64(0);
        this.img.mark("__argvp", 1, this.img.data.len);
        this.img.data.u64(0);

        this.img.mark("msg_minus", 1, this.img.data.len); this.data_strz("-");
        this.img.mark("msg_nl", 1, this.img.data.len); this.data_strz("\n");
        this.img.mark("msg_true", 1, this.img.data.len); this.data_strz("true");
        this.img.mark("msg_false", 1, this.img.data.len); this.data_strz("false");
        this.img.mark("msg_null", 1, this.img.data.len); this.data_strz("null");
        this.img.mark("msg_object", 1, this.img.data.len); this.data_strz("<object>");
        this.img.mark("msg_oom", 1, this.img.data.len); this.data_strz("out of memory!\n");
        this.img.mark("msg_not_object", 1, this.img.data.len); this.data_strz("not an object\n");
        this.img.mark("msg_no_method", 1, this.img.data.len); this.data_strz("no such method\n");
        this.img.mark("msg_null_deref", 1, this.img.data.len); this.data_strz("null dereference\n");

        // string vtable
        this.img.data.align(8);
        this.img.mark("cname_string", 1, this.img.data.len);
        this.data_strz("String");
        this.img.mark("vt_string", 1, this.img.data.len);
        this.data_abs("cname_string");
        this.img.data.u64(6);
        this.img.data.u64(0);
        // empty string object
        this.img.data.align(8);
        this.img.mark("str_empty", 1, this.img.data.len);
        this.data_abs("vt_string");
        this.img.data.u64(0);
        this.img.data.put(0);

        // class names
        int c = 0;
        while (c < this.prog.nclasses) {
            this.img.mark(this.cname_label(c), 1, this.img.data.len);
            byte[] nm = this.prog.classes[c].name;
            int nl = this.prog.classes[c].namelen;
            this.img.data.write(nm, nl);
            this.img.data.put(0);
            c = c + 1;
        }

        // class vtables
        c = 0;
        while (c < this.prog.nclasses) {
            this.img.data.align(8);
            this.img.mark(this.vt_name(c), 1, this.img.data.len);
            this.data_abs(this.cname_label(c));
            this.img.data.u64(this.prog.classes[c].namelen);
            this.img.data.u64(this.prog.nmethods);
            int g = 0;
            while (g < this.prog.nmethods) {
                int fid = -1;
                ClassInfo cd = this.prog.classes[c];
                int j = 0;
                while (j < cd.nmethods) {
                    if (cd.method_ids[j] == g) {
                        // find function with this class and method name
                        int k = 0;
                        while (k < this.prog.nfuncs) {
                            Func f = this.prog.funcs[k];
                            if (f.is_method && f.class_id == c &&
                                names_eq(f.name, f.namelen,
                                         this.prog.methods[g].name,
                                         this.prog.methods[g].namelen)) {
                                fid = k;
                            }
                            k = k + 1;
                        }
                    }
                    j = j + 1;
                }
                if (fid >= 0) this.data_abs(this.fn_name(fid));
                else this.img.data.u64(0);
                g = g + 1;
            }
            c = c + 1;
        }

        // string constants
        int k = 0;
        while (k < this.prog.nstrings) {
            this.img.data.align(16);
            this.img.mark(this.str_label(k), 1, this.img.data.len);
            this.data_abs("vt_string");
            this.img.data.u64(this.prog.strings[k].vlen);
            this.img.data.write(this.prog.strings[k].value, this.prog.strings[k].vlen);
            this.img.data.put(0);
            k = k + 1;
        }
    }
}
