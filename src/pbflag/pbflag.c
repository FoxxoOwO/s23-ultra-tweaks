/* pbflag: insert or overwrite a boolean flag in a Google Play services phenotype snapshot (.pb),
 * keeping the snapshot's field order. Flag entries are field 5; an existing entry is replaced in
 * place, a new one goes before the first entry with a larger numeric name.
 * Usage: pbflag <in.pb> <out.pb> <flag-name> <0|1>
 * Port of the Python tool used during development; same byte output. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static unsigned char *buf; static size_t len;

static int rv(size_t *i, unsigned long long *r) {
	unsigned s = 0; *r = 0;
	while (*i < len && s < 64) { unsigned char c = buf[(*i)++]; *r |= (unsigned long long)(c & 0x7f) << s; s += 7; if (c < 0x80) return 0; }
	return -1;
}
static size_t ev(unsigned long long n, unsigned char *o) {
	size_t k = 0; do { unsigned char c = n & 0x7f; n >>= 7; o[k++] = n ? (c | 0x80) : c; } while (n); return k;
}
/* name of a field-5 entry: its payload's field 1 */
static int entry_name(size_t st, size_t end, char *name, size_t cap) {
	size_t i = st; unsigned long long key, ln;
	if (rv(&i, &key) || rv(&i, &ln)) return -1;
	size_t pe = i + ln; if (pe > end) return -1;
	while (i < pe) {
		if (rv(&i, &key)) return -1;
		unsigned fn = key >> 3, wt = key & 7; unsigned long long v;
		if (wt == 0) { if (rv(&i, &v)) return -1; }
		else if (wt == 2) {
			if (rv(&i, &v)) return -1;
			if (fn == 1) {
				if (v >= cap || i + v > pe) return -1;
				memcpy(name, buf + i, v); name[v] = 0; return 0;
			}
			i += v;
		} else if (wt == 1) i += 8; else if (wt == 5) i += 4; else return -1;
	}
	return -1;
}
static int isnum(const char *s) { if (!*s) return 0; for (; *s; s++) if (*s < '0' || *s > '9') return 0; return 1; }

int main(int argc, char **argv) {
	if (argc != 5) { fprintf(stderr, "usage: pbflag in.pb out.pb flag 0|1\n"); return 2; }
	FILE *f = fopen(argv[1], "rb"); if (!f) { perror(argv[1]); return 1; }
	fseek(f, 0, SEEK_END); len = ftell(f); fseek(f, 0, SEEK_SET);
	buf = malloc(len + 1); if (fread(buf, 1, len, f) != len) { perror("read"); return 1; } fclose(f);
	const char *flag = argv[3]; unsigned long long val = strtoull(argv[4], 0, 10), want = strtoull(flag, 0, 10);
	unsigned char entry[256], newf[300]; size_t nl = strlen(flag), el = 0, nfl = 0;
	if (nl > 200 || !isnum(flag)) { fprintf(stderr, "flag must be numeric\n"); return 2; }
	entry[el++] = 0x0a; el += ev(nl, entry + el); memcpy(entry + el, flag, nl); el += nl;
	entry[el++] = 0x18; el += ev(val, entry + el);
	newf[nfl++] = 0x2a; nfl += ev(el, newf + nfl); memcpy(newf + nfl, entry, el); nfl += el;

	/* pass 1: does the flag already exist (entries are not always sorted)? */
	int exists = 0; char name[256];
	for (size_t i = 0; i < len && !exists;) {
		size_t st = i; unsigned long long key, v;
		if (rv(&i, &key)) break;
		unsigned fn = key >> 3, wt = key & 7;
		if (wt == 0) { if (rv(&i, &v)) break; }
		else if (wt == 2) { if (rv(&i, &v) || i + v > len) break; i += v; }
		else if (wt == 1) i += 8; else if (wt == 5) i += 4; else break;
		if (fn == 5 && entry_name(st, i, name, sizeof name) == 0 && !strcmp(name, flag)) exists = 1;
	}
	FILE *o = fopen(argv[2], "wb"); if (!o) { perror(argv[2]); return 1; }
	size_t i = 0, outlen = 0; int done = 0;
	while (i < len) {
		size_t st = i; unsigned long long key, v;
		if (rv(&i, &key)) goto bad;
		unsigned fn = key >> 3, wt = key & 7;
		if (wt == 0) { if (rv(&i, &v)) goto bad; }
		else if (wt == 2) { if (rv(&i, &v) || i + v > len) goto bad; i += v; }
		else if (wt == 1) i += 8; else if (wt == 5) i += 4; else goto bad;
		if (i > len) goto bad;
		if (fn == 5 && !done && entry_name(st, i, name, sizeof name) == 0) {
			if (!strcmp(name, flag)) { fwrite(newf, 1, nfl, o); outlen += nfl; done = 1; continue; }
			if (!exists && isnum(name) && strtoull(name, 0, 10) > want) { fwrite(newf, 1, nfl, o); outlen += nfl; done = 1; }
		}
		fwrite(buf + st, 1, i - st, o); outlen += i - st;
	}
	if (!done) { fprintf(stderr, "no place to insert %s\n", flag); fclose(o); remove(argv[2]); return 1; }
	fclose(o); printf("ok %zu -> %zu\n", len, outlen); return 0;
bad:
	fprintf(stderr, "snapshot parse error at %zu\n", i); fclose(o); remove(argv[2]); return 1;
}
