"""Tiny SVG drawing kit for the block diagrams (flat boxes, hard drop shadow,
thin arrows, one navy accent). Style follows the H&P 'multi-cycle operations'
slide. Every figure script imports this and only places things."""

NAVY = "#004870"
GREY = "#e3e3e3"
INK = "#1a1a1a"
FONT = "Liberation Sans, Helvetica, Arial, sans-serif"


def esc(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


class Fig:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.o = []
        self.defs = []

    # ---- primitives -------------------------------------------------
    def raw(self, s):
        self.o.append(s)

    def text(self, x, y, s, size=11, bold=False, anchor="start", fill=INK,
             halo=False, rot=None, italic=False):
        st = f'font-size="{size}" text-anchor="{anchor}" fill="{fill}"'
        if bold:
            st += ' font-weight="bold"'
        if italic:
            st += ' font-style="italic"'
        if halo:
            st += ' stroke="white" stroke-width="3" paint-order="stroke"'
        tr = f' transform="rotate({rot} {x} {y})"' if rot is not None else ""
        self.raw(f'<text x="{x}" y="{y}" {st}{tr}>{esc(s)}</text>')

    def box(self, x, y, w, h, lines=(), kind="old", size=11, title=None,
            align="center", shadow=4, dashed=False, fill=None):
        """kind: old (grey), new (navy, white text), plain (white, no shadow)."""
        if kind == "new":
            f, tc, sh = NAVY, "white", "#7f9fb3"
        elif kind == "plain":
            f, tc, sh = "white", INK, None
        else:
            f, tc, sh = GREY, INK, "#6b6b6b"
        if fill:
            f = fill
        if sh and shadow:
            self.raw(f'<rect x="{x+shadow}" y="{y+shadow}" width="{w}" height="{h}" fill="{sh}"/>')
        d = ' stroke-dasharray="5 3"' if dashed else ""
        self.raw(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="{f}" stroke="{INK}" stroke-width="1"{d}/>')
        rows = ([(title, True)] if title else []) + [(l, False) for l in lines]
        lh = size + 3
        ty = y + (h - lh * len(rows)) / 2 + size
        for s, b in rows:
            if align == "center":
                self.text(x + w / 2, ty, s, size, b, "middle", tc)
            else:
                self.text(x + 8, ty, s, size, b, "start", tc)
            ty += lh

    def bar(self, x, y, w, h, title, sub, size=10):
        """Vertical pipeline-register bar with rotated text."""
        self.raw(f'<rect x="{x+4}" y="{y+4}" width="{w}" height="{h}" fill="#6b6b6b"/>')
        self.raw(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="{GREY}" stroke="{INK}"/>')
        cx = x + w / 2
        cy = y + h / 2
        self.text(cx - 3, cy, title, size + 1, True, "middle", rot=-90)
        self.text(cx + 11, cy, sub, size - 1, False, "middle", rot=-90)

    def region(self, x, y, w, h, label, dashed=True, color="#555"):
        d = ' stroke-dasharray="7 4"' if dashed else ""
        self.raw(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="none" stroke="{color}" stroke-width="1.1"{d}/>')
        self.text(x + 8, y + 15, label, 11, True, fill=color)

    def arrow(self, pts, label=None, lp=None, dashed=False, head=True,
              width=1.2, both=False, lsize=10, anchor="middle", color=INK,
              dot=None, lrot=None):
        p = " ".join(f"{a},{b}" for a, b in pts)
        d = ' stroke-dasharray="5 3"' if dashed else ""
        me = ' marker-end="url(#ah)"' if head else ""
        ms = ' marker-start="url(#ah)"' if both else ""
        self.raw(f'<polyline points="{p}" fill="none" stroke="{color}" stroke-width="{width}"{d}{me}{ms}/>')
        for dx, dy in (dot or []):
            self.raw(f'<circle cx="{dx}" cy="{dy}" r="2.6" fill="{INK}"/>')
        if label:
            if lp is None:
                (x1, y1), (x2, y2) = pts[0], pts[1]
                lp = ((x1 + x2) / 2, (y1 + y2) / 2 - 4)
            self.text(lp[0], lp[1], label, lsize, False, anchor, halo=True, rot=lrot)

    # ---- output -----------------------------------------------------
    def svg(self):
        head = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {self.w} {self.h}" '
                f'width="{self.w}" height="{self.h}" font-family="{FONT}">'
                '<defs><marker id="ah" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" '
                'markerHeight="7" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="#1a1a1a"/>'
                '</marker>' + "".join(self.defs) + '</defs>'
                f'<rect width="{self.w}" height="{self.h}" fill="white"/>')
        return head + "\n".join(self.o) + "</svg>"

    def title(self, t, sub):
        self.text(40, 40, t, 22, True)
        self.text(40, 62, sub, 12, fill="#444")
        self.raw(f'<rect x="40" y="70" width="{self.w-80}" height="3" fill="{NAVY}"/>')
