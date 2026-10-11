"""Rebuild per-instruction stage occupancy from trace.csv (written by
tb_timing_trace.v from the real cpu_core RTL). Every instruction instance is
tracked through F -> ID -> EX -> WB using stall_pipeline as the shift enable,
then cross-checked against the logged fetch_pc / id_pc / ex_pc."""
import csv

PROG = {0x00: "addi x1,x0,7", 0x04: "addi x2,x0,9", 0x08: "mul  x3,x1,x2",
        0x0c: "add  x4,x3,x1", 0x10: "lui  x5,0x20000", 0x14: "sw   x4,0(x5)",
        0x18: "lw   x6,0(x5)", 0x1c: "add  x7,x6,x1", 0x20: "beq  x0,x0,+8",
        0x24: "addi x8,x0,1", 0x28: "div  x9,x4,x1", 0x2c: "addi x10,x9,1",
        0x30: "nop"}


def load(path="trace.csv"):
    rows = []
    with open(path) as fh:
        for r in csv.DictReader(fh):
            d = {}
            for k, v in r.items():
                d[k] = int(v, 16) if k in ("fetch_pc", "id_pc", "ex_pc") else int(v)
            rows.append(d)
    return rows


def build(rows):
    """returns list of instances: dict(pc, F=[cycles], ID=[...], EX=[...], WB=[...], squashed)"""
    inst = []

    def new(pc):
        d = {"pc": pc, "F": [], "ID": [], "EX": [], "WB": [], "squashed": False}
        inst.append(d)
        return d

    p0 = new(0)
    p0["F"].append(-1)                       # fetched before the first logged cycle
    slot = {"F": new(rows[0]["fetch_pc"]), "ID": p0, "EX": None, "WB": None}
    for c, r in enumerate(rows):
        for s in ("F", "ID", "EX", "WB"):
            if slot[s] is not None:
                slot[s][s].append(c)
        if slot["EX"] is not None and r["branch_stall"] and not r["stall"]:
            slot["EX"]["squashed"] = True
        if c + 1 < len(rows) and not r["stall"]:
            nxt = new(rows[c + 1]["fetch_pc"])
            slot = {"F": nxt, "ID": slot["F"], "EX": slot["ID"], "WB": slot["EX"]}
    # cross-check against logged PCs
    ok = True
    for c, r in enumerate(rows[:70]):
        for s, key in (("F", "fetch_pc"), ("ID", "id_pc"), ("EX", "ex_pc")):
            who = [i for i in inst if c in i[s]]
            if who and who[0]["pc"] != r[key] and not (s == "EX" and c == 0):
                ok = False
                print("MISMATCH", c, s, hex(who[0]["pc"]), hex(r[key]))
    return inst, ok


if __name__ == "__main__":
    rows = load()
    inst, ok = build(rows)
    print("cross-check vs RTL trace:", "PASS" if ok else "FAIL")
    for i in inst[:22]:
        f = lambda l: (str(l[0]) + "-" + str(l[-1])) if l else "."
        print(hex(i["pc"]), PROG.get(i["pc"], "?"), "F", f(i["F"]), "ID", f(i["ID"]),
              "EX", f(i["EX"]), "WB", f(i["WB"]), "SQUASHED" if i["squashed"] else "")
