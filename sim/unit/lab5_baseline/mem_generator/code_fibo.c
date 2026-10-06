#include <stdio.h>
int main(void) {
    int n = 10;
    int a = 0, b = 1, next;
    for (int i = 2; i < n; i++) {
        next = a + b;
        a = b;
        b = next;
    }
    return b;
}
