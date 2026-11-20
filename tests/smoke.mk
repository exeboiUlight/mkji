fn int fact(int n) {
    if (n <= 1) {
        return 1;
    }
    return n * fact(n - 1);
}

class Counter {
    int n;
    string tag;

    fn void init(string t) {
        this.n = 0;
        this.tag = t;
    }

    fn void inc() {
        this.n = this.n + 1;
    }

    fn int value() {
        return this.n;
    }
}

int value = 7;
bool ok = value > 3 && fact(4) == 24;
string msg = "smoke";
Counter c = new Counter(msg);
c.inc();
c.inc();

print(value);
print(ok);
print(msg);
print(c.value());
print(c);
print(null);
