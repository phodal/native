#!/usr/bin/env python3
"""The GLib 2.72 receipt's error-set whitelist.

Compiling gtk_host.c on stock ubuntu 22.04 (GLib 2.72, GTK 4.6) cannot
succeed: the toolkit's GTK floor is 4.10, so GTK-age failures are the
expected steady state. What this receipt pins is that NOTHING ELSE
fails - a glib/gio symbol needing 2.74+ without a version-checked
fallback shows up here as a diagnostic outside the whitelist below.

The whitelist is by diagnostic SHAPE, not symbol prefix:
- undeclared gtk_/GTK_ functions are the GTK-age roots;
- undeclared plain (non-glib-namespaced) identifiers are their
  cascades (locals whose declaring line failed);
- int-conversion lines are cascades of undeclared functions returning
  int, and incidentally name glib types (GListModel), so a prefix
  blacklist would false-positive on them.
Everything else - unknown type name 'G...', undeclared g_/G_ symbols,
missing members, or any shape not seen before - fails the step.
"""
import re
import sys

bad = []
for line in sys.stdin:
    m = re.search(r": error: (.*)", line)
    if not m:
        continue
    msg = m.group(1)
    if re.match(r"call to undeclared function '(gtk_|GTK_)", msg):
        continue
    if re.match(r"use of undeclared identifier '(?!g_|G_|G[A-Z])", msg):
        continue
    if "incompatible integer to pointer conversion" in msg:
        continue
    bad.append(line.rstrip())

if bad:
    print("non-GTK-age diagnostics against GLib 2.72 - the pre-2.74 fallback story regressed:")
    print("\n".join(bad))
    sys.exit(1)
print("fallback receipt ok: every error is GTK-age by shape")
