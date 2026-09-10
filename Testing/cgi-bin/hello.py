#!/usr/bin/env python3
import os

name = "world"
for part in os.environ.get("QUERY_STRING", "").split("&"):
    if part.startswith("name="):
        name = part[5:] or "world"

body = "<h1>Hello, %s!</h1>" % name
print("Content-Type: text/html")
print()
print(body)
