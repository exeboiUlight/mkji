// Негативный тест: файл с ошибками для проверки сообщений компилятора.
fn int one(int x) {
    return x;
}

fn void nothing() {
}

fn int partial(bool b) {
    if (b) {
        return 1;
    }
}

fn int dead() {
    return 1;
    print("unreachable");
}

int wrong = true;          // E0001
print(missing);            // E0002
one(1, 2);                 // E0003
if (1) { print("no"); }    // E0004
int unused = 0;            // W0001 (не ошибка)
int from_void = nothing(); // E0008
int nul = null;            // E0009
int dup = 1;
int dup = 2;               // E0010
int no_init;               // E0011
(1)();                     // E0007
