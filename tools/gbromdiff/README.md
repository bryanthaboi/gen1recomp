# gbromdiff

Compare two Game Boy ROMs bank by bank, and say **where** and **how** they
disagree.

Written for one specific problem: bringing a localised Gen 1 Pokémon release
into a disassembly. It is not specific to Pokémon, or to Gen 1 — any pair of
Game Boy ROMs will do.

## Why

The European Pokémon releases are rebuilds of their US counterparts. Most
banks are byte-identical, the text banks are entirely different, and a handful
of code banks are the US code with pointers shifted. Which bank is which is
the first thing you need to know and the last thing anyone writes down.

That distinction is the whole point of this tool:

```
  bank   differing bytes            shape
  0x04       30 (  0.2%)   patched
  0x10    16328 ( 99.7%)   replaced
```

A bank differing in 99.7% of its bytes is a **different payload** — translated
text — and needs new source. A bank differing in 0.2% is **the same code with
values moved**, and usually needs a pointer table corrected rather than a
rewrite. Those two findings lead to completely different work, and a plain
`cmp` cannot tell them apart.

## The loop it is built for

```
1. build the disassembly
2. diff the build against the retail ROM   ← this tool
3. fix the banks that disagree
4. go to 1, until nothing disagrees
```

Exit status is **0 when the ROMs are identical** and **1 when they differ**, so
it drops straight into that loop:

```bash
make && ./gbromdiff.py build.gb retail.gb || echo "not there yet"
```

## Usage

```bash
./gbromdiff.py A.gb B.gb                        # bank-by-bank summary
./gbromdiff.py A.gb B.gb --regions              # contiguous differing runs
./gbromdiff.py A.gb B.gb --sym pokeyellow.sym   # name the symbols involved
./gbromdiff.py A.gb B.gb --json                 # machine-readable
```

With an rgbds `.sym` file it names the symbol each differing region falls
inside, which turns

```
0x0703A1 differs
```

into

```
0x0703A1-0x0703B4  bank 0x1C  20 bytes  TextPredef+0x3A1
```

`--gap N` controls how many matching bytes are tolerated inside one region
(default 16). Without it, a shifted pointer table reports as hundreds of
one-byte findings instead of one region worth looking at.

No dependencies beyond Python 3.

## What this does not do

It does not build anything, and it does not write a disassembly. It tells you
where two ROMs differ. Turning that into a source tree that rebuilds a
localised ROM byte-for-byte is the actual project; this is the instrument you
point at it between iterations.

## Context

The Spanish Red and Blue releases are supported in
[gen1recomp](https://github.com/bryanthaboi/gen1recomp) by way of
[einstein95/pokered-es](https://github.com/einstein95/pokered-es), a
shift-matching disassembly whose `.sym` files provide Spanish addresses for
every symbol.

Spanish **Yellow** has no equivalent, so it cannot be supported the same way.
French (`Narishma-gb/pokeyellow-fr`) and German (`Brianum/pokeyellow-de`)
Yellow disassemblies both exist, so adapting pret's Yellow to a European
release is demonstrably possible — it simply has not been done for Spanish.
This tool exists to make that attempt less tedious.

MIT licensed. Contributions welcome, particularly from anyone actually
attempting `pokeyellow-es`.
