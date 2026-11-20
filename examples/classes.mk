// Классы, типизированные поля, методы, this и new init
class Point {
    int x;
    int y;

    fn void init(int px, int py) {
        this.x = px;
        this.y = py;
    }

    fn int sum() {
        return this.x + this.y;
    }

    fn string describe() {
        return "Point";
    }
}

fn int twice(int n) {
    return n * 2;
}

Point p = new Point(3, 4);
print(p.describe());
print(p.x);
print(p.sum());
print(twice(p.sum()));

int i = 0;
while (i < 3) {
    print(i);
    i = i + 1;
}

if (p.sum() == 7) {
    print("seven");
} else {
    print("not seven");
}
