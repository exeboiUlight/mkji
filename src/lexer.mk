// MKJI 1.0 — лексер (на MKJI). Возвращает токены по запросу.
// Использует только while/return (в MKJI 1.0 нет for/break/continue).
use "core.mk";

class Lexer {
    string src;
    int pos;
    int line;
    int col;
    Tok cur;

    fn void setup(string s) {
        this.src = s;
        this.pos = 0;
        this.line = 1;
        this.col = 1;
        this.cur = new Tok();
        this.next();
    }

    fn int peek(int n) {
        int p = this.pos + n;
        if (p >= this.src.len) return -1;
        return this.src[p];
    }

    fn int take() {
        if (this.pos >= this.src.len) return -1;
        int c = this.src[this.pos];
        this.pos = this.pos + 1;
        if (c == 10) {
            this.line = this.line + 1;
            this.col = 1;
        } else {
            this.col = this.col + 1;
        }
        return c;
    }

    fn bool alpha(int c) {
        return (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || c == 95;
    }

    fn bool digit(int c) { return c >= 48 && c <= 57; }

    fn bool space(int c) {
        return c == 32 || c == 9 || c == 13 || c == 10 || c == 12;
    }

    fn int hexval(int c) {
        if (c >= 48 && c <= 57) return c - 48;
        if (c >= 97 && c <= 102) return c - 97 + 10;
        if (c >= 65 && c <= 70) return c - 65 + 10;
        return -1;
    }

    // Смотрит вперёд: начинается ли следующий токен имя (IDENT или IDENT '[')?
    // Нужно, чтобы отличить `Point p = ...;` от `p = ...;`.
    fn bool next_is_ident() {
        int p = this.pos;
        bool done = false;
        while (!done) {
            while (p < this.src.len && this.space(this.src[p])) p = p + 1;
            if (p + 1 < this.src.len && this.src[p] == 47 && this.src[p + 1] == 47) {
                while (p < this.src.len && this.src[p] != 10) p = p + 1;
            } else if (p + 1 < this.src.len && this.src[p] == 47 && this.src[p + 1] == 42) {
                p = p + 2;
                while (p + 1 < this.src.len &&
                       !(this.src[p] == 42 && this.src[p + 1] == 47)) p = p + 1;
                if (p + 1 < this.src.len) p = p + 2;
            } else {
                done = true;
            }
        }
        if (p >= this.src.len) return false;
        if (this.alpha(this.src[p])) return true;
        if (this.src[p] == 91) {
            p = p + 1;
            while (p < this.src.len && this.space(this.src[p])) p = p + 1;
            return p < this.src.len && this.src[p] == 93;
        }
        return false;
    }

    fn byte[] one(int c) {
        byte[] b = new byte[1];
        b[0] = c;
        return b;
    }

    fn byte[] two(int a, int b) {
        byte[] r = new byte[2];
        r[0] = a;
        r[1] = b;
        return r;
    }

    fn int escaped() {
        int c = this.take();
        if (c == 110) return 10;
        if (c == 116) return 9;
        if (c == 114) return 13;
        if (c == 48) return 0;
        if (c == 92) return 92;
        if (c == 34) return 34;
        return c;
    }

    fn void skip_trivia() {
        bool done = false;
        while (!done) {
            int c = this.peek(0);
            if (c >= 0 && this.space(c)) {
                this.take();
            } else if (c == 47 && this.peek(1) == 47) {
                while (this.peek(0) >= 0 && this.peek(0) != 10) this.take();
            } else if (c == 47 && this.peek(1) == 42) {
                this.take();
                this.take();
                while (this.peek(0) >= 0 &&
                       !(this.peek(0) == 42 && this.peek(1) == 47)) this.take();
                if (this.peek(0) >= 0) {
                    this.take();
                    this.take();
                }
            } else {
                done = true;
            }
        }
    }

    fn void next() {
        this.skip_trivia();
        int line = this.line;
        int col = this.col;
        int c = this.peek(0);
        if (c < 0) {
            this.cur.setup(5, this.one(0), 1, 0);
            this.cur.setpos(line, col);
            return;
        }

        if (this.alpha(c)) {
            byte[] b = new byte[128];
            int n = 0;
            while (c >= 0 && (this.alpha(c) || this.digit(c))) {
                if (n < 127) {
                    b[n] = c;
                    n = n + 1;
                }
                this.take();
                c = this.peek(0);
            }
            this.cur.setup(1, b, n, 0);
            this.cur.setpos(line, col);
            return;
        }

        if (this.digit(c)) {
            int v = 0;
            if (c == 48 && (this.peek(1) == 120 || this.peek(1) == 88)) {
                this.take();
                this.take();
                int d = this.peek(0);
                while (this.hexval(d) >= 0) {
                    v = v * 16 + this.hexval(d);
                    this.take();
                    d = this.peek(0);
                }
            } else {
                while (c >= 0 && this.digit(c)) {
                    v = v * 10 + (c - 48);
                    this.take();
                    c = this.peek(0);
                }
            }
            this.cur.setup(2, this.one(0), 1, v);
            this.cur.setpos(line, col);
            return;
        }

        if (c == 34) {
            this.take();
            byte[] b = new byte[1024];
            int n = 0;
            int x = this.peek(0);
            while (x >= 0 && x != 34) {
                this.take();
                if (x == 92) x = this.escaped();
                if (n < 1023) {
                    b[n] = x;
                    n = n + 1;
                }
                x = this.peek(0);
            }
            if (this.peek(0) == 34) this.take();
            this.cur.setup(3, b, n, n);
            this.cur.setpos(line, col);
            return;
        }

        int a = this.peek(0);
        int b = this.peek(1);
        if ((a == 38 && b == 38) || (a == 124 && b == 124) ||
            (a == 60 && b == 60) || (a == 62 && b == 62) ||
            (a == 61 && b == 61) || (a == 33 && b == 61) ||
            (a == 60 && b == 61) || (a == 62 && b == 61)) {
            this.take();
            this.take();
            this.cur.setup(4, this.two(a, b), 2, 0);
            this.cur.setpos(line, col);
            return;
        }

        this.take();
        this.cur.setup(4, this.one(a), 1, 0);
        this.cur.setpos(line, col);
    }

    fn bool is_p(int ch) {
        return this.cur.kind == 4 && this.cur.tlen == 1 && this.cur.text[0] == ch;
    }

    fn bool is_p2(int a, int b) {
        return this.cur.kind == 4 && this.cur.tlen == 2 &&
               this.cur.text[0] == a && this.cur.text[1] == b;
    }

    fn bool is_s(string s) {
        return this.cur.kind == 1 && name_eq(this.cur.text, this.cur.tlen, s);
    }

    fn void expect_p(int ch) {
        if (!this.is_p(ch)) die("expected punctuation");
        this.next();
    }

    fn void expect_p2(int a, int b) {
        if (!this.is_p2(a, b)) die("expected punctuation");
        this.next();
    }

    fn void expect_s(string s) {
        if (!this.is_s(s)) die("expected keyword");
        this.next();
    }

    fn void expect_eof() {
        if (this.cur.kind != 5) die("expected end of file");
    }
}
