// Minimal harmless test target — no network, no crypto, just a hash check
#include <stdio.h>
#include <string.h>

unsigned int magic_mix(const char *s, unsigned long len) {
  unsigned int h = 0x9e376a8e; // 0x9E3779B9 ^ 0x1337
  for (unsigned long i = 0; i < len; i++) {
    h = ((s[i] ^ h) * 0x85EBCA6Bu);
    h = (h ^ (h >> 13)) + 0x165667b1;
  }
  return h;
}

int check_licence(const char *key) {
  size_t l = strlen(key);
  if (l <= 7) return 0;
  unsigned int h = magic_mix(key, l);
  return ((short)h == -0x5a10); // low 16 bits == 0xA5F0
}

int main(int argc, char **argv) {
  if (argc < 2) { printf("usage: %s <key>\n", argv[0]); return 1; }
  printf("%s\n", check_licence(argv[1]) ? "LICENCE OK" : "LICENCE BAD");
  return 0;
}
