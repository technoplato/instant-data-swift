#!/usr/bin/env python3
"""Resolves each conflict block as the cherry-picked commit's lines, then HEAD's (history headers: both kept)."""
import re, sys
for name in sys.argv[1:]:
    text = open(name).read()
    pattern = re.compile(r"<<<<<<< [^\n]*\n(.*?)=======\n(.*?)>>>>>>> [^\n]*\n", re.S)
    text, n = pattern.subn(lambda m: m.group(2) + m.group(1), text)
    assert "<<<<<<<" not in text and ">>>>>>>" not in text, name
    open(name, "w").write(text)
    print(f"{name}: {n} block(s)")
