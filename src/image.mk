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

// Prepare PE .idata: kernel32 imports
fn void img_prepare_pe(Image img) {
    Buf tail = new Buf();
    tail.setup(512);
    int[] hn = new int[9];

    int desc_end = 40;
    int ilt_off = desc_end;
    int iat_off = ilt_off + 80;
    int hn_off = iat_off + 80;

    int cur = hn_off;

    hn[0] = cur; tail.u16(0); buf_put_str(tail, "GetStdHandle"); tail.put(0);
    cur = hn_off + tail.len; if ((cur % 2) != 0) { tail.put(0); cur = cur + 1; }
    hn[1] = cur; tail.u16(0); buf_put_str(tail, "WriteFile"); tail.put(0);
    cur = hn_off + tail.len; if ((cur % 2) != 0) { tail.put(0); cur = cur + 1; }
    hn[2] = cur; tail.u16(0); buf_put_str(tail, "ExitProcess"); tail.put(0);
    cur = hn_off + tail.len; if ((cur % 2) != 0) { tail.put(0); cur = cur + 1; }
    hn[3] = cur; tail.u16(0); buf_put_str(tail, "VirtualAlloc"); tail.put(0);
    cur = hn_off + tail.len; if ((cur % 2) != 0) { tail.put(0); cur = cur + 1; }
    hn[4] = cur; tail.u16(0); buf_put_str(tail, "CreateFileA"); tail.put(0);
    cur = hn_off + tail.len; if ((cur % 2) != 0) { tail.put(0); cur = cur + 1; }
    hn[5] = cur; tail.u16(0); buf_put_str(tail, "ReadFile"); tail.put(0);
    cur = hn_off + tail.len; if ((cur % 2) != 0) { tail.put(0); cur = cur + 1; }
    hn[6] = cur; tail.u16(0); buf_put_str(tail, "GetFileSize"); tail.put(0);
    cur = hn_off + tail.len; if ((cur % 2) != 0) { tail.put(0); cur = cur + 1; }
    hn[7] = cur; tail.u16(0); buf_put_str(tail, "CloseHandle"); tail.put(0);
    cur = hn_off + tail.len; if ((cur % 2) != 0) { tail.put(0); cur = cur + 1; }
    hn[8] = cur; tail.u16(0); buf_put_str(tail, "GetCommandLineA"); tail.put(0);
    cur = hn_off + tail.len; if ((cur % 2) != 0) { tail.put(0); cur = cur + 1; }

    int dll_off = cur;
    buf_put_str(tail, "kernel32.dll"); tail.put(0);

    int idat_rva = img.sec_rva[2];
    Buf b = new Buf();
    b.setup(1024);

    // Import directory descriptor (kernel32)
    b.u32(idat_rva + ilt_off);
    b.u32(0); b.u32(0);
    b.u32(idat_rva + dll_off);
    b.u32(idat_rva + iat_off);
    // Null descriptor
    b.u32(0); b.u32(0); b.u32(0); b.u32(0); b.u32(0);

    // ILT
    int k = 0;
    while (k < 9) { put_u64_parts(b, idat_rva + hn[k], 0); k = k + 1; }
    put_u64_parts(b, 0, 0);

    // IAT with labels
    img.mark("iat_get_std", 2, b.len);       put_u64_parts(b, idat_rva + hn[0], 0);
    img.mark("iat_write_file", 2, b.len);    put_u64_parts(b, idat_rva + hn[1], 0);
    img.mark("iat_exit_proc", 2, b.len);     put_u64_parts(b, idat_rva + hn[2], 0);
    img.mark("iat_virtual_alloc", 2, b.len); put_u64_parts(b, idat_rva + hn[3], 0);
    img.mark("iat_create_file", 2, b.len);   put_u64_parts(b, idat_rva + hn[4], 0);
    img.mark("iat_read_file", 2, b.len);     put_u64_parts(b, idat_rva + hn[5], 0);
    img.mark("iat_get_file_size", 2, b.len); put_u64_parts(b, idat_rva + hn[6], 0);
    img.mark("iat_close_handle", 2, b.len);  put_u64_parts(b, idat_rva + hn[7], 0);
    img.mark("iat_get_cmdline", 2, b.len);   put_u64_parts(b, idat_rva + hn[8], 0);
    put_u64_parts(b, 0, 0);

    while (b.len < hn_off) b.put(0);
    b.write(tail.p, tail.len);

    img.idata = b;
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
    f.u16(1);  // e_phnum
    f.u16(0); f.u16(0); f.u16(0); // e_shentsize, e_shnum, e_shstrndx

    // Program header PT_LOAD
    f.u32(1); f.u32(7); // p_type, p_flags (RWX)
    put_u64_parts(f, 0, 0);                      // p_offset
    put_u64_parts(f, img.base_lo, img.base_hi);  // p_vaddr
    put_u64_parts(f, img.base_lo, img.base_hi);  // p_paddr
    put_u64_parts(f, total, 0);                  // p_filesz
    put_u64_parts(f, total, 0);                  // p_memsz
    put_u64_parts(f, 4096, 0);                   // p_align

    while (f.len < code_off) f.put(0);
    f.write(img.code.p, img.code.len);
    while (f.len < data_off) f.put(0);
    f.write(img.data.p, img.data.len);
    while (f.len < total) f.put(0);

    bool ok = write_file(path, to_byte_array(f));
    if (!ok) die("cannot write output file");
}
