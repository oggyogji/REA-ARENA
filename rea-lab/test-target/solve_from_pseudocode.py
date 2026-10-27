# Re-implement hash from decompiled pseudocode (not original C)
def magic_mix_python(s: bytes):
    h = 0x9e376a8e
    for b in s:
        h = ((b ^ h) * 0x85EBCA6B) & 0xFFFFFFFF
        h = ((h ^ (h >> 0xD)) + 0x165667b1) & 0xFFFFFFFF
    return h

# Brute-force 8-char key with low16 == 0xA5F0 (needs ~57k iterations for n7VUWkQz)
import string, random
chars = string.ascii_letters + string.digits
random.seed(0)
for i in range(100000):
    cand = ''.join(random.choices(chars, k=8))
    h = magic_mix_python(cand.encode())
    if (h & 0xFFFF) == 0xA5F0:
        print(f"recovered valid key: '{cand}' at iteration {i}")
        print(f"  hash = 0x{h:08X}  low16 = 0x{h & 0xFFFF:04X}")
        break
