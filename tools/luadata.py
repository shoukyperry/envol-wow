"""Read Lua table literals as plain data (no code execution)."""
import re

class P:
    def __init__(self, s, i=0):
        self.s, self.i = s, i

    def ws(self):
        s = self.s
        while True:
            while self.i < len(s) and s[self.i] in " \t\r\n":
                self.i += 1
            if s.startswith("--", self.i):
                m = re.compile(r"--\[(=*)\[").match(s, self.i)
                if m:
                    end = s.index("]" + m.group(1) + "]", m.end())
                    self.i = end + len(m.group(1)) + 2
                else:
                    nl = s.find("\n", self.i)
                    self.i = len(s) if nl < 0 else nl + 1
                continue
            return

    def peek(self):
        self.ws()
        return self.s[self.i] if self.i < len(self.s) else ""

    def string(self):
        s = self.s
        c = s[self.i]
        if c == "[":
            m = re.compile(r"\[(=*)\[").match(s, self.i)
            close = "]" + m.group(1) + "]"
            start = m.end()
            if s.startswith("\n", start):
                start += 1
            end = s.index(close, start)
            self.i = end + len(close)
            return s[start:end]
        self.i += 1
        out = []
        while True:
            ch = s[self.i]
            if ch == c:
                self.i += 1
                return "".join(out)
            if ch == "\\":
                n = s[self.i + 1]
                esc = {"n": "\n", "t": "\t", "r": "\r", "\\": "\\", '"': '"', "'": "'", "\n": "\n", "a": "\a", "b": "\b"}
                if n in esc:
                    out.append(esc[n]); self.i += 2
                elif n.isdigit():
                    m = re.compile(r"\d{1,3}").match(s, self.i + 1)
                    out.append(chr(int(m.group()))); self.i = m.end()
                else:
                    out.append(n); self.i += 2
            else:
                out.append(ch); self.i += 1

    def value(self):
        c = self.peek()
        s = self.s
        if c == "{":
            return self.table()
        if c in "\"'" or (c == "[" and re.compile(r"\[=*\[").match(s, self.i)):
            return self.string()
        m = re.compile(r"-?(0x[0-9a-fA-F]+|\d+\.?\d*([eE][-+]?\d+)?|\.\d+)").match(s, self.i)
        if m:
            self.i = m.end()
            t = m.group()
            if "x" in t:
                return int(t, 16)
            f = float(t)
            return int(f) if re.fullmatch(r"-?\d+", t) else f
        for kw, v in (("true", True), ("false", False), ("nil", None)):
            if s.startswith(kw, self.i):
                self.i += len(kw)
                return v
        m = re.compile(r"([A-Za-z_]\w*)\[(\d+)\]").match(s, self.i)
        if m:
            self.i = m.end()
            return {"__ref": m.group(1), "idx": int(m.group(2))}
        raise ValueError("unexpected %r at %d" % (s[self.i:self.i + 40], self.i))

    def table(self):
        self.i += 1  # {
        arr, d = [], {}
        while True:
            c = self.peek()
            if c == "}":
                self.i += 1
                break
            if c == "[" and not re.compile(r"\[=*\[").match(self.s, self.i):
                self.i += 1
                k = self.value()
                assert self.peek() == "]"; self.i += 1
                assert self.peek() == "="; self.i += 1
                d[k] = self.value()
            else:
                m = re.compile(r"([A-Za-z_]\w*)\s*=(?!=)").match(self.s, self.i)
                if m:
                    self.i = m.end()
                    d[m.group(1)] = self.value()
                else:
                    arr.append(self.value())
            c = self.peek()
            if c in ",;":
                self.i += 1
        if d and arr:
            for n, v in enumerate(arr, 1):
                d[n] = v
            return d
        return d if d else arr


def tables_after(text, marker):
    """Yield each table literal that directly follows `marker` in text."""
    pos = 0
    while True:
        j = text.find(marker, pos)
        if j < 0:
            return
        p = P(text, j + len(marker))
        p.ws()
        if p.peek() == "{":
            yield p.table()
            pos = p.i
        else:
            pos = j + len(marker)


# ---- écriture de tables Lua (données générées) ----
IDENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
RESERVED = {"and", "break", "do", "else", "elseif", "end", "false", "for", "function", "if", "in", "local",
            "nil", "not", "or", "repeat", "return", "then", "true", "until", "while"}


def lstr(s):
    s = s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\r", "")
    return '"' + s + '"'


def ser(v):
    if v is None:
        return "nil"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        r = ("%.3f" % v).rstrip("0").rstrip(".")
        return r if r not in ("", "-") else "0"
    if isinstance(v, str):
        return lstr(v)
    if isinstance(v, list):
        return "{" + ",".join(ser(x) for x in v) + "}"
    if isinstance(v, dict):
        parts = []
        for k, x in v.items():
            if x is None:
                continue
            if isinstance(k, str) and IDENT.match(k) and k not in RESERVED:
                parts.append(k + "=" + ser(x))
            else:
                parts.append("[" + ser(k) + "]=" + ser(x))
        return "{" + ",".join(parts) + "}"
    raise TypeError(type(v))


