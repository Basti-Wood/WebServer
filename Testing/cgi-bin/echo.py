#!/usr/bin/env python3
import os, sys

length = int(os.environ.get("CONTENT_LENGTH") or 0)
data = sys.stdin.read(length) if length > 0 else ""

print("Content-Type: text/plain")
print()
print("method=%s length=%d body=%s" % (os.environ.get("REQUEST_METHOD", "?"), length, data))
