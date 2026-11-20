// Комплексный тест расширений MKJI 1.0:
// use, массивы, индексация строк, hex, побитовые операции, файловый I/O.
use "lib.mk";

string s = "ABC";
byte[] buf = new byte[3];
buf[0] = s[0];
buf[1] = s[1];
buf[2] = s[2];

int[] nums = new int[3];
nums[0] = 10;
nums[1] = 20;
nums[2] = 30;

print(buf[0]);
print(buf[1]);
print(buf[2]);
print(buf.len);
print(s.len);
print(nums[1]);
print(nums.len);
print(add(3, 4));

int a = 0xFF & 0x0F;
int b = 0xF0 | 0x0F;
int c = 0xF0 ^ 0xFF;
int d = 1 << 4;
int e = 256 >> 4;
print(a);
print(b);
print(c);
print(d);
print(e);

bool ok = write_file("features_out.txt", buf);
print(ok);
string back = read_file("features_out.txt");
print(back);
