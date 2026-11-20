// MKJI 1.0 — генератор рантайма (на MKJI).
use "core.mk";
use "emit.mk";

// регистры: RAX=0 RCX=1 RDX=2 RBX=3 RSP=4 RBP=5 RSI=6 RDI=7 R8=8 R9=9 R10=10 R11=11
// условия: 0=e 1=ne 2=l 3=le 4=g 5=ge

class Runtime {
    fn void frame_push(Image i) {
        i.push(5);
        i.mov_rr(5, 4);
    }
    fn void frame_pop(Image i) {
        i.mov_rr(4, 5);
        i.pop(5);
    }
    fn void win_frame(Image i, int locals) {
        this.frame_push(i);
        i.and_ri(4, -16);
        i.sub_ri(4, locals);
    }

    fn void write(Image i) {
        i.mark("_write", 0, i.code.len);
        if (i.target == 1) {
            this.win_frame(i, 64);
            i.mov_mem_r(5, -8, 0);
            i.mov_mem_r(5, -16, 1);
            i.mov_ri(1, -11);
            i.call_iat("iat_get_std");
            i.mov_mem_r(5, -24, 0);
            i.mov_r_mem(1, 5, -24);
            i.mov_r_mem(2, 5, -8);
            i.mov_r_mem(8, 5, -16);
            i.lea_rip(9, "bytes_written");
            i.mov_ri(10, 0);
            i.mov_mem_r(4, 32, 10);
            i.call_iat("iat_write_file");
            this.frame_pop(i);
        } else {
            i.mov_rr(6, 0);
            i.mov_rr(2, 1);
            i.mov_ri(0, 1);
            i.mov_ri(7, 1);
            i.syscall();
        }
        i.ret();
    }

    fn void newline(Image i) {
        i.lea_rip(0, "msg_nl");
        i.mov_ri(1, 1);
        i.call("_write");
    }

    fn void print_int(Image i) {
        i.mark("_print_int", 0, i.code.len);
        this.frame_push(i);
        i.sub_ri(4, 64);
        i.mov_mem_r(5, -8, 0);
        i.mov_rr(1, 0);
        i.cmp_ri(1, 0);
        i.jcc_id(5, i.sym(".pi_nonneg"));
        i.lea_rip(0, "msg_minus");
        i.mov_ri(1, 1);
        i.call("_write");
        i.mov_r_mem(1, 5, -8);
        i.neg(1);
        i.mark_id(i.sym(".pi_nonneg"), 0, i.code.len);
        i.lea(6, 5, -16);
        i.xor_rr(8, 8);
        i.mov_ri(9, 10);
        int loop = i.sym(".pi_loop");
        i.mark_id(loop, 0, i.code.len);
        i.mov_rr(0, 1);
        i.cqo();
        i.idiv(9);
        i.add_ri(2, 0x30);
        i.sub_ri(6, 1);
        i.mov_mem8_r(6, 0, 2);
        i.add_ri(8, 1);
        i.mov_rr(1, 0);
        i.test_rr(1, 1);
        i.jcc_id(1, loop);
        i.mov_rr(0, 6);
        i.mov_rr(1, 8);
        i.call("_write");
        this.newline(i);
        this.frame_pop(i);
        i.ret();
    }

    fn void print_bool(Image i) {
        i.mark("_print_bool", 0, i.code.len);
        this.frame_push(i);
        i.sub_ri(4, 32);
        i.test_rr(0, 0);
        i.jcc(0, ".pb_false");
        i.lea_rip(0, "msg_true");
        i.mov_ri(1, 4);
        i.call("_write");
        i.jmp(".pb_done");
        i.mark(".pb_false", 0, i.code.len);
        i.lea_rip(0, "msg_false");
        i.mov_ri(1, 5);
        i.call("_write");
        i.mark(".pb_done", 0, i.code.len);
        this.newline(i);
        this.frame_pop(i);
        i.ret();
    }

    fn void print_string(Image i) {
        i.mark("_print_string", 0, i.code.len);
        this.frame_push(i);
        i.sub_ri(4, 32);
        i.test_rr(0, 0);
        i.jcc(0, ".ps_null");
        i.mov_r_mem(1, 0, 8);
        i.add_ri(0, 16);
        i.call("_write");
        this.newline(i);
        this.frame_pop(i);
        i.ret();
        i.mark(".ps_null", 0, i.code.len);
        i.lea_rip(0, "msg_null");
        i.mov_ri(1, 4);
        i.call("_write");
        this.newline(i);
        this.frame_pop(i);
        i.ret();
    }

    fn void print_object(Image i) {
        i.mark("_print_object", 0, i.code.len);
        this.frame_push(i);
        i.sub_ri(4, 32);
        i.test_rr(0, 0);
        i.jcc(0, ".po_null");
        i.mov_r_mem(10, 0, 0);
        i.mov_r_mem(0, 10, 0);
        i.mov_r_mem(1, 10, 8);
        i.call("_write");
        this.newline(i);
        this.frame_pop(i);
        i.ret();
        i.mark(".po_null", 0, i.code.len);
        i.lea_rip(0, "msg_null");
        i.mov_ri(1, 4);
        i.call("_write");
        this.newline(i);
        this.frame_pop(i);
        i.ret();
    }

    fn void print_null(Image i) {
        i.mark("_print_null", 0, i.code.len);
        this.frame_push(i);
        i.sub_ri(4, 32);
        i.lea_rip(0, "msg_null");
        i.mov_ri(1, 4);
        i.call("_write");
        this.newline(i);
        this.frame_pop(i);
        i.ret();
    }

    fn void emit_panic(Image i) {
        i.mark("_panic", 0, i.code.len);
        if (i.target == 1) {
            this.win_frame(i, 32);
            i.call("_write");
            i.mov_ri(1, 1);
            i.call_iat("iat_exit_proc");
        } else {
            i.call("_write");
            i.mov_ri(0, 60);
            i.mov_ri(7, 1);
            i.syscall();
        }
        i.ret();
    }

    fn void str_eq(Image i) {
        i.mark("_str_eq", 0, i.code.len);
        i.test_rr(0, 0);
        i.jcc(0, ".se_left_null");
        i.test_rr(1, 1);
        i.jcc(0, ".se_false");
        i.mov_r_mem(9, 0, 8);
        i.mov_r_mem(11, 1, 8);
        i.cmp_rr(9, 11);
        i.jcc(1, ".se_false");
        i.test_rr(9, 9);
        i.jcc(0, ".se_true");
        i.add_ri(0, 16);
        i.add_ri(1, 16);
        i.mark(".se_loop", 0, i.code.len);
        i.movzx_r8_mem(0, 0, 10);
        i.movzx_r8_mem(1, 0, 11);
        i.cmp_rr(10, 11);
        i.jcc(1, ".se_false");
        i.add_ri(0, 1);
        i.add_ri(1, 1);
        i.sub_ri(9, 1);
        i.test_rr(9, 9);
        i.jcc(1, ".se_loop");
        i.mark(".se_true", 0, i.code.len);
        i.mov_ri(0, 1);
        i.ret();
        i.mark(".se_left_null", 0, i.code.len);
        i.test_rr(1, 1);
        i.jcc(1, ".se_false");
        i.jmp(".se_true");
        i.mark(".se_false", 0, i.code.len);
        i.xor_rr(0, 0);
        i.ret();
    }

    fn void alloc(Image i) {
        i.mark("_alloc", 0, i.code.len);
        i.mov_rr(10, 0);
        i.add_ri(10, 15);
        i.and_ri(10, -16);
        i.mov_abs(11, "heap_ptr");
        i.mov_r_mem(0, 11, 0);
        i.mov_rr(9, 0);
        i.add_rr(9, 10);
        i.mov_abs(11, "heap_end");
        i.mov_r_mem(11, 11, 0);
        i.cmp_rr(9, 11);
        i.jcc(4, ".alloc_oom");
        i.mov_abs(11, "heap_ptr");
        i.mov_mem_r(11, 0, 9);
        i.ret();
        i.mark(".alloc_oom", 0, i.code.len);
        i.lea_rip(0, "msg_oom");
        i.mov_ri(1, 15);
        i.call("_panic");
        i.ret();
    }

    fn void heap_init(Image i) {
        i.mark("_heap_init", 0, i.code.len);
        if (i.target == 1) {
            this.win_frame(i, 32);
            i.xor_rr(1, 1);
            i.mov_ri(2, 0x10000000);
            i.mov_ri(8, 0x3000);
            i.mov_ri(9, 4);
            i.call_iat("iat_virtual_alloc");
            this.frame_pop(i);
        } else {
            i.mov_ri(0, 9);
            i.mov_ri(7, 0);
            i.mov_ri(6, 0x10000000);
            i.mov_ri(2, 3);
            i.mov_ri(10, 0x22);
            i.mov_ri(8, -1);
            i.mov_ri(9, 0);
            i.syscall();
        }
        i.mov_abs(11, "heap_ptr");
        i.mov_mem_r(11, 0, 0);
        i.add_ri(0, 0x10000000);
        i.mov_abs(11, "heap_end");
        i.mov_mem_r(11, 0, 0);
        i.ret();
    }

    fn void read_file_elf(Image i) {
        i.mark("_read_file", 0, i.code.len);
        this.frame_push(i);
        i.sub_ri(4, 64);
        i.mov_mem_r(5, -8, 0);
        i.mov_r_mem(7, 5, -8);
        i.add_ri(7, 16);
        i.mov_ri(6, 0);
        i.mov_ri(2, 0);
        i.mov_ri(0, 2);
        i.syscall();
        i.cmp_ri(0, 0);
        i.jcc(2, ".rf_fail");
        i.mov_mem_r(5, -16, 0);
        i.mov_r_mem(7, 5, -16);
        i.mov_ri(6, 0);
        i.mov_ri(2, 2);
        i.mov_ri(0, 8);
        i.syscall();
        i.mov_mem_r(5, -24, 0);
        i.mov_r_mem(7, 5, -16);
        i.mov_ri(6, 0);
        i.mov_ri(2, 0);
        i.mov_ri(0, 8);
        i.syscall();
        i.mov_r_mem(0, 5, -24);
        i.add_ri(0, 25);
        i.call("_alloc");
        i.mov_mem_r(5, -32, 0);
        i.mov_abs(11, "vt_string");
        i.mov_mem_r(0, 0, 11);
        i.mov_r_mem(11, 5, -24);
        i.mov_mem_r(0, 8, 11);
        i.mov_r_mem(7, 5, -16);
        i.mov_r_mem(6, 5, -32);
        i.add_ri(6, 16);
        i.mov_r_mem(2, 5, -24);
        i.mov_ri(0, 0);
        i.syscall();
        i.mov_r_mem(11, 5, -32);
        i.mov_r_mem(10, 5, -24);
        i.add_ri(11, 16);
        i.add_rr(11, 10);
        i.xor_rr(10, 10);
        i.mov_mem8_r(11, 0, 10);
        i.mov_r_mem(7, 5, -16);
        i.mov_ri(0, 3);
        i.syscall();
        i.mov_r_mem(0, 5, -32);
        this.frame_pop(i);
        i.ret();
        i.mark(".rf_fail", 0, i.code.len);
        i.xor_rr(0, 0);
        this.frame_pop(i);
        i.ret();
    }

    fn void write_file_elf(Image i) {
        i.mark("_write_file", 0, i.code.len);
        this.frame_push(i);
        i.sub_ri(4, 64);
        i.mov_mem_r(5, -8, 0);
        i.mov_mem_r(5, -16, 1);
        i.mov_r_mem(7, 5, -8);
        i.add_ri(7, 16);
        i.mov_ri(6, 577);
        i.mov_ri(2, 438);
        i.mov_ri(0, 2);
        i.syscall();
        i.cmp_ri(0, 0);
        i.jcc(2, ".wf_fail");
        i.mov_mem_r(5, -24, 0);
        i.mov_r_mem(11, 5, -16);
        i.mov_r_mem(2, 11, 0);
        i.mov_ri(0, 1);
        i.mov_r_mem(7, 5, -24);
        i.mov_r_mem(6, 5, -16);
        i.add_ri(6, 8);
        i.syscall();
        i.mov_r_mem(7, 5, -24);
        i.mov_ri(0, 3);
        i.syscall();
        i.mov_ri(0, 1);
        this.frame_pop(i);
        i.ret();
        i.mark(".wf_fail", 0, i.code.len);
        i.xor_rr(0, 0);
        this.frame_pop(i);
        i.ret();
    }

    fn void create_file_win(Image i, int access, int share, int disp) {
        i.mov_ri(2, access);
        i.mov_ri(8, share);
        i.xor_rr(9, 9);
        i.mov_ri(10, disp);
        i.mov_mem_r(4, 32, 10);
        i.mov_ri(10, 0x80);
        i.mov_mem_r(4, 40, 10);
        i.xor_rr(10, 10);
        i.mov_mem_r(4, 48, 10);
        i.call_iat("iat_create_file");
    }

    fn void read_file_win(Image i) {
        i.mark("_read_file", 0, i.code.len);
        this.win_frame(i, 160);
        i.mov_mem_r(5, -8, 0);
        i.mov_r_mem(1, 5, -8);
        i.add_ri(1, 16);
        this.create_file_win(i, 0x80000000, 1, 3);
        i.cmp_ri(0, -1);
        i.jcc(0, ".rf_fail");
        i.test_rr(0, 0);
        i.jcc(0, ".rf_fail");
        i.mov_mem_r(5, -16, 0);
        i.mov_r_mem(1, 5, -16);
        i.xor_rr(2, 2);
        i.call_iat("iat_get_file_size");
        i.mov_mem_r(5, -24, 0);
        i.add_ri(0, 25);
        i.call("_alloc");
        i.mov_mem_r(5, -32, 0);
        i.mov_abs(11, "vt_string");
        i.mov_mem_r(0, 0, 11);
        i.mov_r_mem(11, 5, -24);
        i.mov_mem_r(0, 8, 11);
        i.mov_r_mem(1, 5, -16);
        i.mov_r_mem(2, 5, -32);
        i.add_ri(2, 16);
        i.mov_r_mem(8, 5, -24);
        i.lea_rip(9, "bytes_written");
        i.xor_rr(10, 10);
        i.mov_mem_r(4, 32, 10);
        i.call_iat("iat_read_file");
        i.mov_r_mem(1, 5, -16);
        i.call_iat("iat_close_handle");
        i.mov_r_mem(11, 5, -32);
        i.mov_r_mem(10, 5, -24);
        i.add_ri(11, 16);
        i.add_rr(11, 10);
        i.xor_rr(10, 10);
        i.mov_mem8_r(11, 0, 10);
        i.mov_r_mem(0, 5, -32);
        this.frame_pop(i);
        i.ret();
        i.mark(".rf_fail", 0, i.code.len);
        i.xor_rr(0, 0);
        this.frame_pop(i);
        i.ret();
    }

    fn void write_file_win(Image i) {
        i.mark("_write_file", 0, i.code.len);
        this.win_frame(i, 160);
        i.mov_mem_r(5, -8, 0);
        i.mov_mem_r(5, -16, 1);
        i.mov_r_mem(1, 5, -8);
        i.add_ri(1, 16);
        this.create_file_win(i, 0x40000000, 0, 2);
        i.cmp_ri(0, -1);
        i.jcc(0, ".wf_fail");
        i.test_rr(0, 0);
        i.jcc(0, ".wf_fail");
        i.mov_mem_r(5, -24, 0);
        i.mov_r_mem(1, 5, -24);
        i.mov_r_mem(2, 5, -16);
        i.add_ri(2, 8);
        i.mov_r_mem(11, 5, -16);
        i.mov_r_mem(8, 11, 0);
        i.lea_rip(9, "bytes_written");
        i.xor_rr(10, 10);
        i.mov_mem_r(4, 32, 10);
        i.call_iat("iat_write_file");
        i.mov_r_mem(1, 5, -24);
        i.call_iat("iat_close_handle");
        i.mov_ri(0, 1);
        this.frame_pop(i);
        i.ret();
        i.mark(".wf_fail", 0, i.code.len);
        i.xor_rr(0, 0);
        this.frame_pop(i);
        i.ret();
    }

    fn void file_io(Image i) {
        if (i.target == 1) {
            this.read_file_win(i);
            this.write_file_win(i);
        } else {
            this.read_file_elf(i);
            this.write_file_elf(i);
        }
    }

    fn void emit_str_from(Image i) {
        i.mark("_str_from", 0, i.code.len);
        this.frame_push(i);
        i.sub_ri(4, 32);
        i.mov_mem_r(5, -8, 0);
        i.mov_mem_r(5, -16, 1);
        i.mov_ri(0, 25);
        i.add_rr(0, 1);
        i.call("_alloc");
        i.mov_mem_r(5, -24, 0);
        i.mov_abs(11, "vt_string");
        i.mov_mem_r(0, 0, 11);
        i.mov_r_mem(11, 5, -16);
        i.mov_mem_r(0, 8, 11);
        i.mov_ri(10, 0);
        i.mark(".sf_loop", 0, i.code.len);
        i.mov_r_mem(11, 5, -16);
        i.cmp_rr(10, 11);
        i.jcc(4, ".sf_done");
        i.mov_r_mem(11, 5, -8);
        i.add_ri(11, 8);
        i.add_rr(11, 10);
        i.movzx_r8_mem(11, 0, 8);
        i.mov_r_mem(11, 5, -24);
        i.add_ri(11, 16);
        i.add_rr(11, 10);
        i.mov_mem8_r(11, 0, 8);
        i.add_ri(10, 1);
        i.jmp(".sf_loop");
        i.mark(".sf_done", 0, i.code.len);
        i.mov_r_mem(11, 5, -24);
        i.mov_r_mem(10, 5, -16);
        i.add_ri(11, 16);
        i.add_rr(11, 10);
        i.xor_rr(10, 10);
        i.mov_mem8_r(11, 0, 10);
        i.mov_r_mem(0, 5, -24);
        this.frame_pop(i);
        i.ret();
    }

    fn void exit_prog(Image i) {
        i.mark("_exit_prog", 0, i.code.len);
        if (i.target == 1) {
            i.mov_rr(1, 0);
            this.win_frame(i, 32);
            i.call_iat("iat_exit_proc");
        } else {
            i.mov_rr(7, 0);
            i.mov_ri(0, 60);
            i.syscall();
        }
        i.ret();
    }

    // C string (null-terminated, ptr in RAX) -> MKJI string in RAX
    fn void cstr_to_mkstr(Image i) {
        i.mark("_cstr_to_mkstr", 0, i.code.len);
        this.frame_push(i);
        i.sub_ri(4, 48);
        i.mov_mem_r(5, -8, 0); // src
        // strlen
        i.mov_rr(10, 0);
        i.xor_rr(1, 1);
        int loop = i.sym(".c2s_len");
        int ldone = i.sym(".c2s_ldone");
        i.mark_id(loop, 0, i.code.len);
        i.mov_rr(11, 10);
        i.add_rr(11, 1);
        i.movzx_r8_mem(11, 0, 9);
        i.test_rr(9, 9);
        i.jcc_id(0, ldone);
        i.add_ri(1, 1);
        i.jmp_id(loop);
        i.mark_id(ldone, 0, i.code.len);
        i.mov_mem_r(5, -16, 1);
        i.mov_rr(0, 1);
        i.add_ri(0, 25);
        i.call("_alloc");
        i.mov_mem_r(5, -24, 0);
        i.mov_abs(11, "vt_string");
        i.mov_mem_r(0, 0, 11);
        i.mov_r_mem(11, 5, -16);
        i.mov_mem_r(0, 8, 11);
        // copy
        i.mov_r_mem(10, 5, -8);
        i.mov_r_mem(0, 5, -24);
        i.add_ri(0, 16);
        i.xor_rr(8, 8);
        int cpy = i.sym(".c2s_cpy");
        int cd = i.sym(".c2s_cd");
        i.mark_id(cpy, 0, i.code.len);
        i.mov_r_mem(11, 5, -16);
        i.cmp_rr(8, 11);
        i.jcc_id(5, cd);
        i.mov_rr(11, 10);
        i.add_rr(11, 8);
        i.movzx_r8_mem(11, 0, 9);
        i.mov_rr(11, 0);
        i.add_rr(11, 8);
        i.mov_mem8_r(11, 0, 9);
        i.add_ri(8, 1);
        i.jmp_id(cpy);
        i.mark_id(cd, 0, i.code.len);
        i.mov_rr(11, 0);
        i.add_rr(11, 8);
        i.xor_rr(9, 9);
        i.mov_mem8_r(11, 0, 9);
        i.mov_r_mem(0, 5, -24);
        this.frame_pop(i);
        i.ret();
    }

    fn void init_args_pe(Image i) {
        i.mark("_init_args", 0, i.code.len);
        this.win_frame(i, 96);
        i.call_iat("iat_get_cmdline");
        i.mov_mem_r(5, -8, 0);
        // count args
        i.mov_rr(10, 0);
        i.xor_rr(8, 8);  // count
        i.xor_rr(9, 9);  // in_arg
        i.xor_rr(7, 7);  // in_quote
        int scan = i.sym(".ia_scan");
        int ws = i.sym(".ia_ws");
        int iq = i.sym(".ia_iq");
        int iqt = i.sym(".ia_iqt");
        int nw = i.sym(".ia_nw");
        int nx = i.sym(".ia_nx");
        int sd = i.sym(".ia_sd");
        i.mark_id(scan, 0, i.code.len);
        i.movzx_r8_mem(10, 0, 11);
        i.test_rr(11, 11);
        i.jcc_id(0, sd);
        i.test_rr(7, 7);
        i.jcc_id(1, iq);
        i.cmp_ri(11, 34);
        i.jcc_id(0, iqt);
        i.cmp_ri(11, 32);
        i.jcc_id(0, ws);
        i.cmp_ri(11, 9);
        i.jcc_id(0, ws);
        // word char, not in quote
        i.test_rr(9, 9);
        i.jcc_id(1, nx);
        i.add_ri(8, 1);
        i.mov_ri(9, 1);
        i.jmp_id(nx);
        i.mark_id(iqt, 0, i.code.len);
        i.test_rr(9, 9);
        i.jcc_id(1, nw);
        i.add_ri(8, 1);
        i.mov_ri(9, 1);
        i.mark_id(nw, 0, i.code.len);
        i.mov_ri(7, 1);
        i.jmp_id(nx);
        i.mark_id(iq, 0, i.code.len);
        i.cmp_ri(11, 34);
        i.jcc_id(1, nx);
        i.xor_rr(7, 7);
        i.jmp_id(nx);
        i.mark_id(ws, 0, i.code.len);
        i.xor_rr(9, 9);
        i.jmp_id(nx);
        i.mark_id(nx, 0, i.code.len);
        i.add_ri(10, 1);
        i.jmp_id(scan);
        i.mark_id(sd, 0, i.code.len);
        i.mov_abs(11, "__argc");
        i.mov_mem_r(11, 0, 8);
        i.mov_rr(0, 8);
        i.shl_ri(0, 3);
        i.add_ri(0, 8);
        i.call("_alloc");
        i.mov_mem_r(5, -16, 0);
        i.mov_abs(11, "__argvp");
        i.mov_mem_r(11, 0, 0);
        // pass 2
        i.mov_r_mem(10, 5, -8);
        i.xor_rr(6, 6);
        int p2 = i.sym(".ia_p2");
        int p2w = i.sym(".ia_p2w");
        int p2t = i.sym(".ia_p2t");
        int p2q = i.sym(".ia_p2q");
        int p2qe = i.sym(".ia_p2qe");
        int p2st = i.sym(".ia_p2st");
        int p2c = i.sym(".ia_p2c");
        int p2ce = i.sym(".ia_p2ce");
        int p2d = i.sym(".ia_p2d");
        i.mark_id(p2, 0, i.code.len);
        i.movzx_r8_mem(10, 0, 11);
        i.test_rr(11, 11);
        i.jcc_id(0, p2d);
        i.cmp_ri(11, 32);
        i.jcc_id(0, p2w);
        i.cmp_ri(11, 9);
        i.jcc_id(0, p2w);
        // arg start
        i.cmp_ri(11, 34);
        i.jcc_id(0, p2q);
        i.mov_mem_r(5, -24, 10);
        i.xor_rr(7, 7);
        i.mark_id(p2t, 0, i.code.len);
        i.movzx_r8_mem(10, 0, 11);
        i.test_rr(11, 11);
        i.jcc_id(0, p2st);
        i.cmp_ri(11, 32);
        i.jcc_id(0, p2st);
        i.cmp_ri(11, 9);
        i.jcc_id(0, p2st);
        i.add_ri(10, 1);
        i.add_ri(7, 1);
        i.jmp_id(p2t);
        i.mark_id(p2q, 0, i.code.len);
        i.add_ri(10, 1);
        i.mov_mem_r(5, -24, 10);
        i.xor_rr(7, 7);
        i.mark_id(p2qe, 0, i.code.len);
        i.movzx_r8_mem(10, 0, 11);
        i.test_rr(11, 11);
        i.jcc_id(0, p2st);
        i.cmp_ri(11, 34);
        i.jcc_id(0, p2st);
        i.add_ri(10, 1);
        i.add_ri(7, 1);
        i.jmp_id(p2qe);
        i.mark_id(p2st, 0, i.code.len);
        // if ended on quote, remember to skip it
        i.mov_mem_r(5, -32, 10);
        i.mov_rr(0, 7);
        i.add_ri(0, 25);
        i.call("_alloc");
        i.mov_abs(11, "vt_string");
        i.mov_mem_r(0, 0, 11);
        i.mov_mem_r(0, 8, 7);
        i.mov_mem_r(5, -40, 0);
        i.add_ri(0, 16);
        i.mov_r_mem(11, 5, -24);
        i.xor_rr(8, 8);
        i.mark_id(p2c, 0, i.code.len);
        i.cmp_rr(8, 7);
        i.jcc_id(5, p2ce);
        i.mov_rr(1, 11);
        i.add_rr(1, 8);
        i.movzx_r8_mem(1, 0, 2);
        i.mov_rr(1, 0);
        i.add_rr(1, 8);
        i.mov_mem8_r(1, 0, 2);
        i.add_ri(8, 1);
        i.jmp_id(p2c);
        i.mark_id(p2ce, 0, i.code.len);
        i.mov_rr(9, 0);
        i.add_rr(9, 8);
        i.xor_rr(8, 8);
        i.mov_mem8_r(9, 0, 8);
        // store
        i.mov_r_mem(11, 5, -16);
        i.mov_rr(8, 6);
        i.shl_ri(8, 3);
        i.add_rr(11, 8);
        i.mov_r_mem(0, 5, -40);
        i.mov_mem_r(11, 0, 0);
        i.add_ri(6, 1);
        // advance past closing quote if any
        i.mov_r_mem(10, 5, -32);
        i.movzx_r8_mem(10, 0, 11);
        i.cmp_ri(11, 34);
        i.jcc_id(1, p2);
        i.add_ri(10, 1);
        i.jmp_id(p2);
        i.mark_id(p2w, 0, i.code.len);
        i.add_ri(10, 1);
        i.jmp_id(p2);
        i.mark_id(p2d, 0, i.code.len);
        this.frame_pop(i);
        i.ret();
    }

    fn void init_args_elf(Image i) {
        // RAX = initial RSP
        i.mark("_init_args", 0, i.code.len);
        this.frame_push(i);
        i.sub_ri(4, 48);
        i.mov_mem_r(5, -8, 0);
        i.mov_r_mem(8, 0, 0);
        i.mov_abs(11, "__argc");
        i.mov_mem_r(11, 0, 8);
        i.mov_rr(0, 8);
        i.shl_ri(0, 3);
        i.add_ri(0, 8);
        i.call("_alloc");
        i.mov_mem_r(5, -16, 0);
        i.mov_abs(11, "__argvp");
        i.mov_mem_r(11, 0, 0);
        i.xor_rr(6, 6);
        int loop = i.sym(".iae_l");
        int done = i.sym(".iae_d");
        i.mark_id(loop, 0, i.code.len);
        i.mov_abs(11, "__argc");
        i.mov_r_mem(11, 11, 0);
        i.cmp_rr(6, 11);
        i.jcc_id(5, done);
        i.mov_r_mem(10, 5, -8);
        i.mov_rr(11, 6);
        i.add_ri(11, 1);
        i.shl_ri(11, 3);
        i.add_rr(10, 11);
        i.mov_r_mem(0, 10, 0);
        i.call("_cstr_to_mkstr");
        i.mov_r_mem(11, 5, -16);
        i.mov_rr(8, 6);
        i.shl_ri(8, 3);
        i.add_rr(11, 8);
        i.mov_mem_r(11, 0, 0);
        i.add_ri(6, 1);
        i.jmp_id(loop);
        i.mark_id(done, 0, i.code.len);
        this.frame_pop(i);
        i.ret();
    }

    fn void arg_count_rt(Image i) {
        i.mark("_arg_count", 0, i.code.len);
        i.mov_abs(11, "__argc");
        i.mov_r_mem(0, 11, 0);
        i.ret();
    }

    fn void get_arg_rt(Image i) {
        i.mark("_get_arg", 0, i.code.len);
        i.mov_rr(10, 0);
        i.mov_abs(11, "__argc");
        i.mov_r_mem(11, 11, 0);
        i.cmp_rr(10, 11);
        i.jcc(5, ".ga_bad");
        i.mov_abs(11, "__argvp");
        i.mov_r_mem(11, 11, 0);
        i.shl_ri(10, 3);
        i.add_rr(11, 10);
        i.mov_r_mem(0, 11, 0);
        i.ret();
        i.mark(".ga_bad", 0, i.code.len);
        i.mov_abs(0, "str_empty");
        i.ret();
    }

    fn void emit_all(Image i) {
        i.mark("_start", 0, i.code.len);
        if (i.target == 2) {
            i.mov_rr(3, 4);
        }
        i.call("_heap_init");
        if (i.target == 2) {
            i.mov_rr(0, 3);
            i.call("_init_args");
        } else {
            i.call("_init_args");
        }
        i.call("mk_main");
        i.call("_exit_prog");
        this.write(i);
        this.print_int(i);
        this.print_bool(i);
        this.print_string(i);
        this.print_object(i);
        this.print_null(i);
        this.emit_panic(i);
        this.str_eq(i);
        this.alloc(i);
        this.heap_init(i);
        this.file_io(i);
        this.emit_str_from(i);
        this.exit_prog(i);
        this.cstr_to_mkstr(i);
        if (i.target == 1) this.init_args_pe(i);
        else this.init_args_elf(i);
        this.arg_count_rt(i);
        this.get_arg_rt(i);
    }
}
