// MKJI 1.0 — низкоуровневый эмиттер x86-64 и управление метками/фиксациями.
use "core.mk";

// секции
// SEC_CODE=0 SEC_DATA=1 SEC_IDAT=2
// типы фиксаций: 1=rel32 2=abs64 3=ripiat
// условия: 0=e 1=ne 2=l 3=le 4=g 5=ge

class Image {
    Buf code;
    Buf data;
    Buf idata;
    int target;        // 1=PE 2=ELF
    int base_lo;
    int base_hi;
    int[] sec_rva;

    Label[] labels;
    int nlabels;
    Fixup[] fixups;
    int nfixups;

    string[] sym_names;
    int[] sym_ids;
    int nsyms;

    // ELF dynamic linking info (file offsets / sizes), 0 if not dynamic
    int dyn_off;
    int dyn_size;

    fn void setup(int target) {
        this.code = new Buf();
        this.data = new Buf();
        this.idata = new Buf();
        this.code.setup(1 << 20);
        this.data.setup(1 << 16);
        this.idata.setup(4096);
        this.target = target;
        if (target == 1) {
            this.base_lo = 0;
            this.base_hi = 5;      // 0x140000000 >> 32
        } else {
            this.base_lo = 0x400000;
            this.base_hi = 0;
        }
        this.sec_rva = new int[3];
        this.sec_rva[0] = 0x1000;
        this.sec_rva[1] = 0x2000;
        this.sec_rva[2] = 0x3000;

        this.labels = new Label[65536];
        this.nlabels = 0;
        this.fixups = new Fixup[131072];
        this.nfixups = 0;
        this.sym_names = new string[8192];
        this.sym_ids = new int[8192];
        this.nsyms = 0;

        this.dyn_off = 0;
        this.dyn_size = 0;
    }

    fn int new_label() {
        int id = this.nlabels;
        Label l = new Label();
        l.setup(-1, 0);
        this.labels[id] = l;
        this.nlabels = id + 1;
        return id;
    }

    fn int tmp() { return this.new_label(); }

    fn int sym(string s) {
        int i = 0;
        while (i < this.nsyms) {
            if (this.sym_names[i] == s) return this.sym_ids[i];
            i = i + 1;
        }
        int id = this.new_label();
        this.sym_names[this.nsyms] = s;
        this.sym_ids[this.nsyms] = id;
        this.nsyms = this.nsyms + 1;
        return id;
    }

    fn void mark_id(int id, int sec, int off) {
        this.labels[id].sec = sec;
        this.labels[id].off = off;
    }

    fn void mark(string s, int sec, int off) {
        this.mark_id(this.sym(s), sec, off);
    }

    fn void fix_id(int id, int kind, int sec, int off) {
        Fixup f = new Fixup();
        f.setup(id, kind, sec, off);
        this.fixups[this.nfixups] = f;
        this.nfixups = this.nfixups + 1;
    }

    fn void fix(string s, int kind, int sec, int off) {
        this.fix_id(this.sym(s), kind, sec, off);
    }

    fn Buf secbuf(int sec) {
        if (sec == 0) return this.code;
        if (sec == 1) return this.data;
        return this.idata;
    }

    fn void compute_pe_layout() {
        int align = 4096;
        int code_raw = this.code.len;
        int rem = code_raw % align;
        if (rem != 0) code_raw = code_raw + (align - rem);
        int data_raw = this.data.len;
        rem = data_raw % align;
        if (rem != 0) data_raw = data_raw + (align - rem);
        this.sec_rva[0] = 0x1000;
        this.sec_rva[1] = 0x1000 + code_raw;
        this.sec_rva[2] = this.sec_rva[1] + data_raw;
    }

    fn void compute_elf_layout() {
        int align = 4096;
        int code_raw = this.code.len;
        int rem = code_raw % align;
        if (rem != 0) code_raw = code_raw + (align - rem);
        this.sec_rva[0] = 0x1000;
        this.sec_rva[1] = 0x1000 + code_raw;
        this.sec_rva[2] = this.sec_rva[1];
    }

    fn void resolve() {
        int k = 0;
        while (k < this.nfixups) {
            Fixup f = this.fixups[k];
            Label l = this.labels[f.id];
            if (l.sec < 0) die("undefined label");
            Buf b = this.secbuf(f.sec);
            if (f.kind == 1) {
                int d = l.off - (f.off + 4);
                b.patch32(f.off, d);
            } else if (f.kind == 2) {
                int lo = this.base_lo + this.sec_rva[l.sec] + l.off;
                int hi = this.base_hi;
                b.patch32(f.off, lo);
                b.patch32(f.off + 4, hi);
            } else if (f.kind == 3) {
                int here = this.sec_rva[f.sec] + f.off + 4;
                int target = this.sec_rva[l.sec] + l.off;
                b.patch32(f.off, target - here);
            } else {
                die("bad fixup kind");
            }
            k = k + 1;
        }
    }

    // ---------------- low level ----------------
    fn void e8(int v) { this.code.put(v & 255); }
    fn void e16(int v) { this.code.u16(v); }
    fn void e32(int v) { this.code.u32(v); }
    fn void e64(int v) { this.code.u64(v); }

    fn void rex(int w, int reg, int rm) {
        int v = 64;
        if (w != 0) v = v | 8;
        if ((reg & 8) != 0) v = v | 4;
        if ((rm & 8) != 0) v = v | 1;
        this.code.put(v);
    }

    fn void modrm_rr(int reg, int rm) {
        this.code.put(192 | ((reg & 7) << 3) | (rm & 7));
    }

    fn void modrm_mem(int reg, int base, int disp) {
        int b = base & 7;
        int mod = 2;
        if (disp >= -128 && disp <= 127) mod = 1;
        this.code.put((mod << 6) | ((reg & 7) << 3) | b);
        if (b == 4) this.code.put(0x24);
        if (mod == 1) this.code.put(disp & 255);
        else this.code.u32(disp);
    }

    fn void mov_rr(int dst, int src) {
        this.rex(1, dst, src);
        this.e8(0x8B);
        this.modrm_rr(dst, src);
    }

    fn void mov_ri(int reg, int imm) {
        this.rex(1, 0, reg);
        this.e8(0xB8 + (reg & 7));
        this.e64(imm);
    }

    fn void lea_rip(int reg, string lbl) {
        this.rex(1, reg, 5);
        this.e8(0x8D);
        this.e8(0x05 | ((reg & 7) << 3));
        int off = this.code.len;
        this.e32(0);
        this.fix(lbl, 3, 0, off);
    }

    fn void mov_rip(int reg, string lbl) {
        this.rex(1, reg, 5);
        this.e8(0x8B);
        this.e8(0x05 | ((reg & 7) << 3));
        int off = this.code.len;
        this.e32(0);
        this.fix(lbl, 3, 0, off);
    }

    fn void mov_mem_r(int base, int disp, int src) {
        this.rex(1, src, base);
        this.e8(0x89);
        this.modrm_mem(src, base, disp);
    }

    fn void mov_r_mem(int dst, int base, int disp) {
        this.rex(1, dst, base);
        this.e8(0x8B);
        this.modrm_mem(dst, base, disp);
    }

    fn void mov_mem8_r(int base, int disp, int src) {
        this.rex(0, src, base);
        this.e8(0x88);
        this.modrm_mem(src, base, disp);
    }

    fn void mov_r8_mem(int base, int disp, int dst) {
        this.rex(0, dst, base);
        this.e8(0x8A);
        this.modrm_mem(dst, base, disp);
    }

    fn void movzx_r8_mem(int base, int disp, int dst) {
        this.rex(1, dst, base);
        this.e8(0x0F);
        this.e8(0xB6);
        this.modrm_mem(dst, base, disp);
    }

    fn void movzx_r8_r(int dst, int src) {
        this.rex(1, dst, src);
        this.e8(0x0F);
        this.e8(0xB6);
        this.modrm_rr(dst, src);
    }

    fn void lea(int reg, int base, int disp) {
        this.rex(1, reg, base);
        this.e8(0x8D);
        this.modrm_mem(reg, base, disp);
    }

    fn void mov_abs(int reg, string lbl) {
        this.rex(1, 0, reg);
        this.e8(0xB8 + (reg & 7));
        int off = this.code.len;
        this.e64(0);
        this.fix(lbl, 2, 0, off);
    }

    fn void arith_ri(int reg, int imm, int ext) {
        this.rex(1, 0, reg);
        if (imm >= -128 && imm <= 127) this.e8(0x83);
        else this.e8(0x81);
        this.modrm_rr(ext, reg);
        if (imm >= -128 && imm <= 127) this.e8(imm & 255);
        else this.e32(imm);
    }

    fn void add_ri(int reg, int imm) { this.arith_ri(reg, imm, 0); }
    fn void sub_ri(int reg, int imm) { this.arith_ri(reg, imm, 5); }
    fn void and_ri(int reg, int imm) { this.arith_ri(reg, imm, 4); }
    fn void xor_ri(int reg, int imm) { this.arith_ri(reg, imm, 6); }
    fn void or_imm(int reg, int imm) { this.arith_ri(reg, imm, 1); }
    fn void cmp_ri(int reg, int imm) { this.arith_ri(reg, imm, 7); }

    fn void cmp_rr(int a, int b) {
        this.rex(1, a, b);
        this.e8(0x3B);
        this.modrm_rr(a, b);
    }

    fn void shift_imm(int reg, int n, int ext) {
        this.rex(1, 0, reg);
        this.e8(0xC1);
        this.modrm_rr(ext, reg);
        this.e8(n & 255);
    }

    fn void shl_ri(int reg, int n) { this.shift_imm(reg, n, 4); }
    fn void sar_ri(int reg, int n) { this.shift_imm(reg, n, 7); }

    fn void shift_cl(int reg, int ext) {
        this.rex(1, 0, reg);
        this.e8(0xD3);
        this.modrm_rr(ext, reg);
    }
    fn void shl_cl(int reg) { this.shift_cl(reg, 4); }
    fn void sar_cl(int reg) { this.shift_cl(reg, 7); }

    fn void push(int reg) {
        if ((reg & 8) != 0) this.e8(0x41);
        this.e8(0x50 + (reg & 7));
    }
    fn void pop(int reg) {
        if ((reg & 8) != 0) this.e8(0x41);
        this.e8(0x58 + (reg & 7));
    }

    fn void jmp(string lbl) {
        this.e8(0xE9);
        int off = this.code.len;
        this.e32(0);
        this.fix(lbl, 1, 0, off);
    }
    fn void jmp_id(int id) {
        this.e8(0xE9);
        int off = this.code.len;
        this.e32(0);
        this.fix_id(id, 1, 0, off);
    }

    fn void jcc(int cc, string lbl) {
        int codes = 0x84;
        if (cc == 1) codes = 0x85;
        if (cc == 2) codes = 0x8C;
        if (cc == 3) codes = 0x8E;
        if (cc == 4) codes = 0x8F;
        if (cc == 5) codes = 0x8D;
        this.e8(0x0F);
        this.e8(codes);
        int off = this.code.len;
        this.e32(0);
        this.fix(lbl, 1, 0, off);
    }
    fn void jcc_id(int cc, int id) {
        int codes = 0x84;
        if (cc == 1) codes = 0x85;
        if (cc == 2) codes = 0x8C;
        if (cc == 3) codes = 0x8E;
        if (cc == 4) codes = 0x8F;
        if (cc == 5) codes = 0x8D;
        this.e8(0x0F);
        this.e8(codes);
        int off = this.code.len;
        this.e32(0);
        this.fix_id(id, 1, 0, off);
    }

    fn void call_rip(string lbl) {
        // call [rip+disp32] - used for ELF PLT/GOT slots (kind 3)
        this.e16(0x15FF);
        int off = this.code.len;
        this.e32(0);
        this.fix(lbl, 3, 0, off);
    }

    fn void call(string lbl) {
        this.e8(0xE8);
        int off = this.code.len;
        this.e32(0);
        this.fix(lbl, 1, 0, off);
    }
    fn void call_id(int id) {
        this.e8(0xE8);
        int off = this.code.len;
        this.e32(0);
        this.fix_id(id, 1, 0, off);
    }
    fn void call_iat(string lbl) {
        this.e16(0x15FF);
        int off = this.code.len;
        this.e32(0);
        this.fix(lbl, 3, 0, off);
    }

    fn void ret() { this.e8(0xC3); }
    fn void cqo() { this.e8(0x48); this.e8(0x99); }
    fn void idiv(int reg) {
        this.rex(1, 0, reg);
        this.e8(0xF7);
        this.modrm_rr(7, reg);
    }
    fn void imul_rr(int dst, int src) {
        this.rex(1, dst, src);
        this.e8(0x0F);
        this.e8(0xAF);
        this.modrm_rr(dst, src);
    }
    fn void xor_rr(int a, int b) {
        this.rex(1, a, b);
        this.e8(0x33);
        this.modrm_rr(a, b);
    }
    fn void bor_rr(int dst, int src) {
        this.rex(1, src, dst);
        this.e8(0x09);            // OR r/m, r
        this.modrm_rr(src, dst);
    }
    fn void bxor_rr(int dst, int src) {
        this.rex(1, src, dst);
        this.e8(0x31);            // XOR r/m, r
        this.modrm_rr(src, dst);
    }
    fn void add_rr(int dst, int src) {
        this.rex(1, src, dst);
        this.e8(0x01);
        this.modrm_rr(src, dst);
    }
    fn void sub_rr(int dst, int src) {
        this.rex(1, src, dst);
        this.e8(0x29);
        this.modrm_rr(src, dst);
    }
    fn void and_rr(int dst, int src) {
        this.rex(1, src, dst);
        this.e8(0x21);
        this.modrm_rr(src, dst);
    }
    fn void setcc(int reg, int cc) {
        int codes = 0x94;
        if (cc == 1) codes = 0x95;
        if (cc == 2) codes = 0x9C;
        if (cc == 3) codes = 0x9E;
        if (cc == 4) codes = 0x9F;
        if (cc == 5) codes = 0x9D;
        this.rex(0, 0, reg);
        this.e8(0x0F);
        this.e8(codes);
        this.e8(192 | (reg & 7));
    }
    fn void call_reg(int reg) {
        this.rex(0, 0, reg);
        this.e8(0xFF);
        this.modrm_rr(2, reg);
    }
    fn void test_rr(int a, int b) {
        this.rex(1, a, b);
        this.e8(0x85);
        this.modrm_rr(a, b);
    }
    fn void neg(int reg) {
        this.rex(1, 0, reg);
        this.e8(0xF7);
        this.modrm_rr(3, reg);
    }
    fn void syscall() { this.e8(0x0F); this.e8(0x05); }

    // ---------------- data section helpers ----------------
    fn void data_bytes(byte[] b, int n) { this.data.write(b, n); }
    fn void data_str(string s) {
        byte[] b = bytes(s);
        this.data.write(b, s.len);
        this.data.put(0);
    }
    fn void data_u64(int v) { this.data.u64(v); }
    fn void data_abs(string lbl) {
        int off = this.data.len;
        this.data.u64(0);
        this.fix(lbl, 2, 1, off);
    }
    fn void data_align(int a) { this.data.align(a); }
}
