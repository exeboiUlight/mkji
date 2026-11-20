// MKJI 1.0 — формирование PE64/ELF64 образов.
use "core.mk";
use "emit.mk";

fn byte[] to_byte_array(Buf b) {
    byte[] out = new byte[b.len];
    int i = 0;
    while (i < b.len) {
        out[i] = b.p[i];
        i = i + 1;
    }
    return out;
}

fn void buf_put_str(Buf b, string s) {
    byte[] x = bytes(s);
    b.write(x, s.len);
}

fn int align_up(int v, int a) {
    int r = v % a;
    if (r == 0) return v;
    return v + (a - r);
}

fn void put_u64_parts(Buf b, int lo, int hi) {
    b.u32(lo);
    b.u32(hi);
}

fn void write_name_bytes(Buf b, byte[] name, int nlen) {
    int i = 0;
    while (i < nlen) { b.put(name[i]); i = i + 1; }
    b.put(0);
}

fn string ext_iat_label(int idx) {
    byte[] b = new byte[24];
    b[0] = 105; b[1] = 97; b[2] = 116; b[3] = 95; b[4] = 101; b[5] = 120; b[6] = 116; b[7] = 95;
    int n = 8;
    if (idx == 0) {
        b[n] = 48;
        n = n + 1;
    } else {
        byte[] tmp = new byte[12];
        int t = 0;
        int v = idx;
        while (v > 0) {
            tmp[t] = 48 + (v % 10);
            t = t + 1;
            v = v / 10;
        }
        int k = t - 1;
        while (k >= 0) {
            b[n] = tmp[k];
            n = n + 1;
            k = k - 1;
        }
    }
    return str_from(b, n);
}

// Prepare PE .idata: kernel32 runtime imports + user extern libraries
fn void img_prepare_pe(Image img, Prog prog) {
    int nlibs = 1 + prog.nextlibs;
    int[] lib_counts = new int[128];
    int li = 0;
    while (li < nlibs) { lib_counts[li] = 0; li = li + 1; }
    lib_counts[0] = 9;

    int ei = 0;
    while (ei < prog.nexterns) {
        int pl = prog.externs[ei].lib;
        if (pl >= 0 && pl < prog.nextlibs) {
            lib_counts[1 + pl] = lib_counts[1 + pl] + 1;
        }
        ei = ei + 1;
    }

    int desc_size = (nlibs + 1) * 20;
    int ilt_size = 0;
    li = 0;
    while (li < nlibs) { ilt_size = ilt_size + (lib_counts[li] + 1) * 8; li = li + 1; }
    int iat_size = ilt_size;
    int ilt_off = desc_size;
    int iat_off = ilt_off + ilt_size;
    int hn_off = iat_off + iat_size;

    Buf tail = new Buf();
    tail.setup(4096);

    int[] lib_ilt = new int[128];
    int[] lib_iat = new int[128];
    int cur_ilt = ilt_off;
    int cur_iat = iat_off;
    li = 0;
    while (li < nlibs) {
        lib_ilt[li] = cur_ilt;
        lib_iat[li] = cur_iat;
        cur_ilt = cur_ilt + (lib_counts[li] + 1) * 8;
        cur_iat = cur_iat + (lib_counts[li] + 1) * 8;
        li = li + 1;
    }

    int cur = hn_off;

    string[] k32_names = new string[9];
    k32_names[0] = "GetStdHandle"; k32_names[1] = "WriteFile"; k32_names[2] = "ExitProcess";
    k32_names[3] = "VirtualAlloc"; k32_names[4] = "CreateFileA"; k32_names[5] = "ReadFile";
    k32_names[6] = "GetFileSize"; k32_names[7] = "CloseHandle"; k32_names[8] = "GetCommandLineA";
    string[] k32_labels = new string[9];
    k32_labels[0] = "iat_get_std"; k32_labels[1] = "iat_write_file"; k32_labels[2] = "iat_exit_proc";
    k32_labels[3] = "iat_virtual_alloc"; k32_labels[4] = "iat_create_file"; k32_labels[5] = "iat_read_file";
    k32_labels[6] = "iat_get_file_size"; k32_labels[7] = "iat_close_handle"; k32_labels[8] = "iat_get_cmdline";

    int[] k32_hn = new int[9];
    int k = 0;
    while (k < 9) {
        k32_hn[k] = cur;
        tail.u16(0);
        buf_put_str(tail, k32_names[k]);
        tail.put(0);
        cur = hn_off + tail.len;
        if ((cur % 2) != 0) { tail.put(0); cur = cur + 1; }
        k = k + 1;
    }

    int[] ext_hn = new int[512];
    ei = 0;
    while (ei < prog.nexterns) {
        ext_hn[ei] = cur;
        tail.u16(0);
        write_name_bytes(tail, prog.externs[ei].cname, prog.externs[ei].cnlen);
        cur = hn_off + tail.len;
        if ((cur % 2) != 0) { tail.put(0); cur = cur + 1; }
        ei = ei + 1;
    }

    int k32_dll_off = cur;
    buf_put_str(tail, "kernel32.dll"); tail.put(0);
    cur = hn_off + tail.len;

    int[] ext_dll_off = new int[128];
    li = 0;
    while (li < prog.nextlibs) {
        ext_dll_off[li] = cur;
        write_name_bytes(tail, prog.extlibs[li].name, prog.extlibs[li].namelen);
        cur = hn_off + tail.len;
        li = li + 1;
    }

    int idat_rva = img.sec_rva[2];
    Buf b = new Buf();
    b.setup(hn_off + tail.len + 128);

    // Import descriptors
    b.u32(idat_rva + lib_ilt[0]);
    b.u32(0); b.u32(0);
    b.u32(idat_rva + k32_dll_off);
    b.u32(idat_rva + lib_iat[0]);

    li = 0;
    while (li < prog.nextlibs) {
        b.u32(idat_rva + lib_ilt[1 + li]);
        b.u32(0); b.u32(0);
        b.u32(idat_rva + ext_dll_off[li]);
        b.u32(idat_rva + lib_iat[1 + li]);
        li = li + 1;
    }
    b.u32(0); b.u32(0); b.u32(0); b.u32(0); b.u32(0);

    // ILT
    k = 0;
    while (k < 9) { put_u64_parts(b, idat_rva + k32_hn[k], 0); k = k + 1; }
    put_u64_parts(b, 0, 0);
    li = 0;
    while (li < prog.nextlibs) {
        ei = 0;
        while (ei < prog.nexterns) {
            if (prog.externs[ei].lib == li) {
                put_u64_parts(b, idat_rva + ext_hn[ei], 0);
            }
            ei = ei + 1;
        }
        put_u64_parts(b, 0, 0);
        li = li + 1;
    }

    // IAT
    k = 0;
    while (k < 9) {
        img.mark(k32_labels[k], 2, b.len);
        put_u64_parts(b, idat_rva + k32_hn[k], 0);
        k = k + 1;
    }
    put_u64_parts(b, 0, 0);
    li = 0;
    while (li < prog.nextlibs) {
        ei = 0;
        while (ei < prog.nexterns) {
            if (prog.externs[ei].lib == li) {
                // build label "iat_ext_<ei>" inline (avoids function-call issue)
                byte[] lb = new byte[24];
                lb[0] = 105; lb[1] = 97; lb[2] = 116; lb[3] = 95; lb[4] = 101; lb[5] = 120; lb[6] = 116; lb[7] = 95;
                int ln = 8;
                if (ei == 0) {
                    lb[ln] = 48;
                    ln = ln + 1;
                } else {
                    byte[] tmp = new byte[12];
                    int t = 0;
                    int v = ei;
                    while (v > 0) {
                        tmp[t] = 48 + (v % 10);
                        t = t + 1;
                        v = v / 10;
                    }
                    int kk = t - 1;
                    while (kk >= 0) {
                        lb[ln] = tmp[kk];
                        ln = ln + 1;
                        kk = kk - 1;
                    }
                }
                img.mark(str_from(lb, ln), 2, b.len);
                put_u64_parts(b, idat_rva + ext_hn[ei], 0);
            }
            ei = ei + 1;
        }
        put_u64_parts(b, 0, 0);
        li = li + 1;
    }

    while (b.len < hn_off) b.put(0);
    b.write(tail.p, tail.len);

    img.idata = b;
}

fn void img_prepare_elf(Image img, Prog prog) {
    if (prog.nexterns <= 0) return;

    // Determine which external libraries are needed (have extern functions)
    int[] lib_needed = new int[64];
    int li = 0;
    while (li < prog.nextlibs) { lib_needed[li] = 0; li = li + 1; }
    int ei = 0;
    while (ei < prog.nexterns) {
        int pl = prog.externs[ei].lib;
        if (pl >= 0 && pl < prog.nextlibs) lib_needed[pl] = 1;
        ei = ei + 1;
    }
    int nneeded = 0;
    li = 0;
    while (li < prog.nextlibs) {
        if (lib_needed[li] != 0) nneeded = nneeded + 1;
        li = li + 1;
    }

    img.data.align(8);

    // --- GOT slots (one per extern), marked as iat_ext_<i> ---
    int got_data_off = img.data.len;
    ei = 0;
    while (ei < prog.nexterns) {
        byte[] lb = new byte[24];
        lb[0] = 105; lb[1] = 97; lb[2] = 116; lb[3] = 95; lb[4] = 101; lb[5] = 120; lb[6] = 116; lb[7] = 95;
        int ln = 8;
        if (ei == 0) {
            lb[ln] = 48;
            ln = ln + 1;
        } else {
            byte[] tmp = new byte[12];
            int t = 0;
            int v = ei;
            while (v > 0) {
                tmp[t] = 48 + (v % 10);
                t = t + 1;
                v = v / 10;
            }
            int kk = t - 1;
            while (kk >= 0) {
                lb[ln] = tmp[kk];
                ln = ln + 1;
                kk = kk - 1;
            }
        }
        img.mark(str_from(lb, ln), 1, img.data.len);
        img.data.u64(0);
        ei = ei + 1;
    }

    // --- SysV .hash (DT_HASH) ---
    // nbucket, nchain, bucket[nbucket], chain[nchain]
    int nbucket = prog.nexterns;
    if (nbucket < 1) nbucket = 1;
    int nchain = prog.nexterns + 1; // symbol 0 + externs
    img.data.align(4);
    int hash_data_off = img.data.len;
    int[] buckets = new int[512];
    int[] chains = new int[512];
    int bi = 0;
    while (bi < nbucket) { buckets[bi] = 0; bi = bi + 1; }
    int ci = 0;
    while (ci < nchain) { chains[ci] = 0; ci = ci + 1; }
    // compute hashes and insert symbols (skip 0)
    ei = 0;
    while (ei < prog.nexterns) {
        // ELF hash of extern symbol name
        int h = 0;
        int si = 0;
        while (si < prog.externs[ei].cnlen) {
            int ch = prog.externs[ei].cname[si] & 255;
            h = (h << 4) + ch;
            int g = h & 0xF0000000;
            if (g != 0) {
                h = h ^ (g >> 24);
                h = h & (0xFFFFFFFF - g);
            }
            si = si + 1;
        }
        int bidx = (h & 0x7FFFFFFF) % nbucket;
        int symidx = ei + 1;
        chains[symidx] = buckets[bidx];
        buckets[bidx] = symidx;
        ei = ei + 1;
    }
    // emit hash table
    img.data.u32(nbucket);
    img.data.u32(nchain);
    bi = 0;
    while (bi < nbucket) { img.data.u32(buckets[bi]); bi = bi + 1; }
    ci = 0;
    while (ci < nchain) { img.data.u32(chains[ci]); ci = ci + 1; }

    // --- .dynstr: \0 + needed lib names + extern symbol names ---
    int[] lib_stroff = new int[64];
    int[] sym_stroff = new int[512];
    int str_data_off = img.data.len;
    int cursor = 1; // leading \0
    li = 0;
    while (li < prog.nextlibs) {
        if (lib_needed[li] != 0) {
            lib_stroff[li] = cursor;
            cursor = cursor + prog.extlibs[li].namelen + 1;
        } else {
            lib_stroff[li] = 0;
        }
        li = li + 1;
    }
    ei = 0;
    while (ei < prog.nexterns) {
        sym_stroff[ei] = cursor;
        cursor = cursor + prog.externs[ei].cnlen + 1;
        ei = ei + 1;
    }
    int str_size = cursor;
    img.data.put(0);
    li = 0;
    while (li < prog.nextlibs) {
        if (lib_needed[li] != 0) {
            write_name_bytes(img.data, prog.extlibs[li].name, prog.extlibs[li].namelen);
        }
        li = li + 1;
    }
    ei = 0;
    while (ei < prog.nexterns) {
        write_name_bytes(img.data, prog.externs[ei].cname, prog.externs[ei].cnlen);
        ei = ei + 1;
    }

    // --- .dynsym: null + one STN_UNDEF GLOBAL FUNC per extern ---
    img.data.align(8);
    int sym_data_off = img.data.len;
    img.data.u32(0); img.data.put(0); img.data.put(0); img.data.u16(0);
    img.data.u64(0); img.data.u64(0);
    ei = 0;
    while (ei < prog.nexterns) {
        img.data.u32(sym_stroff[ei]); // st_name
        img.data.put(0x12);           // st_info = STB_GLOBAL|STT_FUNC
        img.data.put(0);              // st_other
        img.data.u16(0);              // st_shndx = SHN_UNDEF
        img.data.u64(0);              // st_value
        img.data.u64(0);              // st_size
        ei = ei + 1;
    }

    // --- .rela.dyn: R_X86_64_GLOB_DAT for each GOT slot ---
    img.data.align(8);
    int rela_data_off = img.data.len;
    int data_rva = img.sec_rva[1];
    int base_lo = img.base_lo;
    int base_hi = img.base_hi;
    ei = 0;
    while (ei < prog.nexterns) {
        int slot_file_off = data_rva + got_data_off + ei * 8;
        int slot_vaddr_lo = base_lo + slot_file_off;
        int slot_vaddr_hi = base_hi;
        put_u64_parts(img.data, slot_vaddr_lo, slot_vaddr_hi); // r_offset
        int sym_index = ei + 1;
        put_u64_parts(img.data, 6, sym_index); // r_info = (sym<<32)|R_X86_64_GLOB_DAT
        put_u64_parts(img.data, 0, 0);          // r_addend
        ei = ei + 1;
    }

    // --- .dynamic ---
    img.data.align(8);
    int dyn_data_off = img.data.len;
    int hash_vaddr_lo = base_lo + data_rva + hash_data_off;
    int str_vaddr_lo = base_lo + data_rva + str_data_off;
    int sym_vaddr_lo = base_lo + data_rva + sym_data_off;
    int rela_vaddr_lo = base_lo + data_rva + rela_data_off;
    li = 0;
    while (li < prog.nextlibs) {
        if (lib_needed[li] != 0) {
            put_u64_parts(img.data, 1, 0); // DT_NEEDED
            put_u64_parts(img.data, lib_stroff[li], 0);
        }
        li = li + 1;
    }
    // DT_HASH
    put_u64_parts(img.data, 4, 0);
    put_u64_parts(img.data, hash_vaddr_lo, base_hi);
    // DT_STRTAB
    put_u64_parts(img.data, 5, 0);
    put_u64_parts(img.data, str_vaddr_lo, base_hi);
    // DT_STRSZ
    put_u64_parts(img.data, 10, 0);
    put_u64_parts(img.data, str_size, 0);
    // DT_SYMTAB
    put_u64_parts(img.data, 6, 0);
    put_u64_parts(img.data, sym_vaddr_lo, base_hi);
    // DT_SYMENT
    put_u64_parts(img.data, 11, 0);
    put_u64_parts(img.data, 24, 0);
    // DT_RELA
    put_u64_parts(img.data, 7, 0);
    put_u64_parts(img.data, rela_vaddr_lo, base_hi);
    // DT_RELASZ
    put_u64_parts(img.data, 8, 0);
    put_u64_parts(img.data, prog.nexterns * 24, 0);
    // DT_RELAENT
    put_u64_parts(img.data, 9, 0);
    put_u64_parts(img.data, 24, 0);
    // DT_NULL
    put_u64_parts(img.data, 0, 0);
    put_u64_parts(img.data, 0, 0);

    int dyn_end = img.data.len;
    img.dyn_off = data_rva + dyn_data_off;
    img.dyn_size = dyn_end - dyn_data_off;
}

fn void write_section_name(Buf f, string name) {
    byte[] nb = bytes(name);
    f.write(nb, name.len);
    int pad = 8 - name.len;
    int i = 0;
    while (i < pad) { f.put(0); i = i + 1; }
}

fn void write_pe(Image img, string path) {
    int code_raw = align_up(img.code.len, 4096);
    int data_raw = align_up(img.data.len, 4096);
    int idat_raw = align_up(img.idata.len, 4096);
    int headers = 4096;
    int image_size = align_up(img.sec_rva[2] + idat_raw, 4096);

    Buf f = new Buf();
    f.setup(headers + code_raw + data_raw + idat_raw + 4096);

    // DOS header
    f.put(77); f.put(90);
    while (f.len < 60) f.put(0);
    f.u32(128);
    while (f.len < 128) f.put(0);

    // PE signature + COFF
    f.put(80); f.put(69); f.put(0); f.put(0);
    f.u16(0x8664);
    f.u16(3);
    f.u32(0); f.u32(0); f.u32(0);
    f.u16(240);
    f.u16(0x22);

    // Optional header PE32+
    f.u16(0x20B); f.put(14); f.put(0);
    f.u32(code_raw);
    f.u32(data_raw + idat_raw);
    f.u32(0);
    f.u32(img.sec_rva[0]); // EntryPoint RVA
    f.u32(img.sec_rva[0]); // BaseOfCode
    put_u64_parts(f, 0, 5); // ImageBase 0x140000000
    f.u32(4096); f.u32(4096); // SectionAlignment, FileAlignment
    f.u16(6); f.u16(0); // OS version
    f.u16(0); f.u16(0); // Image version
    f.u16(6); f.u16(0); // Subsystem version
    f.u32(0); // Win32VersionValue
    f.u32(image_size);
    f.u32(headers);
    f.u32(0); // CheckSum
    f.u16(3); // Subsystem console
    f.u16(0); // DllCharacteristics
    put_u64_parts(f, 0x100000, 0); put_u64_parts(f, 0x1000, 0); // stack reserve/commit
    put_u64_parts(f, 0x100000, 0); put_u64_parts(f, 0x1000, 0); // heap reserve/commit
    f.u32(0); // LoaderFlags
    f.u32(16); // NumberOfRvaAndSizes
    // Data directories
    f.u32(0); f.u32(0); // 0 Export
    f.u32(img.sec_rva[2]); f.u32(img.idata.len); // 1 Import
    int dd = 2;
    while (dd < 16) { f.u32(0); f.u32(0); dd = dd + 1; }

    // Section headers: .text, .data, .idata
    // .text
    write_section_name(f, ".text");
    f.u32(img.code.len); f.u32(img.sec_rva[0]);
    f.u32(code_raw); f.u32(headers);
    f.u32(0); f.u32(0);
    f.u16(0); f.u16(0);
    f.u32(0x60000020);
    // .data
    write_section_name(f, ".data");
    f.u32(img.data.len); f.u32(img.sec_rva[1]);
    f.u32(data_raw); f.u32(headers + code_raw);
    f.u32(0); f.u32(0);
    f.u16(0); f.u16(0);
    f.u32(0xC0000040);
    // .idata
    write_section_name(f, ".idata");
    f.u32(img.idata.len); f.u32(img.sec_rva[2]);
    f.u32(idat_raw); f.u32(headers + code_raw + data_raw);
    f.u32(0); f.u32(0);
    f.u16(0); f.u16(0);
    f.u32(0xC0000040);

    while (f.len < headers) f.put(0);
    f.write(img.code.p, img.code.len);
    while (f.len < headers + code_raw) f.put(0);
    f.write(img.data.p, img.data.len);
    while (f.len < headers + code_raw + data_raw) f.put(0);
    f.write(img.idata.p, img.idata.len);
    while (f.len < headers + code_raw + data_raw + idat_raw) f.put(0);

    bool ok = write_file(path, to_byte_array(f));
    if (!ok) die("cannot write output file");
}



fn void write_elf(Image img, string path) {
    int code_off = img.sec_rva[0];
    int data_off = img.sec_rva[1];
    int total = align_up(data_off + img.data.len, 4096);
    bool dyn = img.dyn_size > 0;
    int phnum = 1;
    if (dyn) phnum = 4;

    Buf f = new Buf();
    f.setup(total + 4096);

    // ELF64 header
    f.put(0x7F); f.put(69); f.put(76); f.put(70); // \x7F ELF
    f.put(2); f.put(1); f.put(1); f.put(0); // 64-bit, little, v1
    f.put(0); f.put(0); f.put(0); f.put(0); f.put(0); f.put(0); f.put(0); f.put(0); // padding
    f.u16(2);  // ET_EXEC
    f.u16(62); // EM_X86_64
    f.u32(1);  // version
    // entry = image_base + sec_rva[0]
    int entry_lo = img.base_lo + img.sec_rva[0];
    put_u64_parts(f, entry_lo, img.base_hi);
    put_u64_parts(f, 64, 0);       // e_phoff
    put_u64_parts(f, 0, 0);        // e_shoff
    f.u32(0);  // e_flags
    f.u16(64); // e_ehsize
    f.u16(56); // e_phentsize
    f.u16(phnum);  // e_phnum
    f.u16(0); f.u16(0); f.u16(0); // e_shentsize, e_shnum, e_shstrndx

    if (dyn) {
        int phoff = 64;
        int phsize = phnum * 56;
        int interp_off = phoff + phsize;
        string interp = "/lib64/ld-linux-x86-64.so.2";
        int interp_size = interp.len + 1;

        // PT_PHDR
        f.u32(6); f.u32(5); // type, flags PF_R|PF_X
        put_u64_parts(f, phoff, 0);
        put_u64_parts(f, img.base_lo + phoff, img.base_hi);
        put_u64_parts(f, img.base_lo + phoff, img.base_hi);
        put_u64_parts(f, phsize, 0);
        put_u64_parts(f, phsize, 0);
        put_u64_parts(f, 8, 0);

        // PT_INTERP
        f.u32(3); f.u32(4); // type, flags PF_R
        put_u64_parts(f, interp_off, 0);
        put_u64_parts(f, img.base_lo + interp_off, img.base_hi);
        put_u64_parts(f, img.base_lo + interp_off, img.base_hi);
        put_u64_parts(f, interp_size, 0);
        put_u64_parts(f, interp_size, 0);
        put_u64_parts(f, 1, 0);

        // PT_LOAD (whole image, RWX)
        f.u32(1); f.u32(7); // p_type, p_flags (RWX)
        put_u64_parts(f, 0, 0);                      // p_offset
        put_u64_parts(f, img.base_lo, img.base_hi);  // p_vaddr
        put_u64_parts(f, img.base_lo, img.base_hi);  // p_paddr
        put_u64_parts(f, total, 0);                  // p_filesz
        put_u64_parts(f, total, 0);                  // p_memsz
        put_u64_parts(f, 4096, 0);                   // p_align

        // PT_DYNAMIC
        f.u32(2); f.u32(6); // type, flags PF_R|PF_W
        put_u64_parts(f, img.dyn_off, 0);
        put_u64_parts(f, img.base_lo + img.dyn_off, img.base_hi);
        put_u64_parts(f, img.base_lo + img.dyn_off, img.base_hi);
        put_u64_parts(f, img.dyn_size, 0);
        put_u64_parts(f, img.dyn_size, 0);
        put_u64_parts(f, 8, 0);

        // Interpreter string
        buf_put_str(f, interp);
        f.put(0);
    } else {
        // Program header PT_LOAD
        f.u32(1); f.u32(7); // p_type, p_flags (RWX)
        put_u64_parts(f, 0, 0);                      // p_offset
        put_u64_parts(f, img.base_lo, img.base_hi);  // p_vaddr
        put_u64_parts(f, img.base_lo, img.base_hi);  // p_paddr
        put_u64_parts(f, total, 0);                  // p_filesz
        put_u64_parts(f, total, 0);                  // p_memsz
        put_u64_parts(f, 4096, 0);                   // p_align
    }

    while (f.len < code_off) f.put(0);
    f.write(img.code.p, img.code.len);
    while (f.len < data_off) f.put(0);
    f.write(img.data.p, img.data.len);
    while (f.len < total) f.put(0);

    bool ok = write_file(path, to_byte_array(f));
    if (!ok) die("cannot write output file");
}
