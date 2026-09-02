#!/usr/bin/env python3
"""Proves sql/*.sql and server/storage/schema.lua carry the same statements.

The Open77 server runtime installs no file-reading API, so the migration runner cannot load
sql/ itself and the statements are held twice on purpose. This check is what keeps the two
copies honest: run it after editing either side.

    python3 tools/check_sql_parity.py

Exit code 0 when every migration matches, 1 otherwise. Comparison ignores only the .sql
file's leading `--` header, its trailing `;`, and surrounding whitespace -- everything else,
byte for byte and statement for statement, has to be identical.
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCHEMA = os.path.join(ROOT, "server", "storage", "schema.lua")

ENTRY = re.compile(
    r'name\s*=\s*"(?P<name>[^"]+)"\s*,\s*'
    r'file\s*=\s*"(?P<file>[^"]+)"\s*,\s*'
    r'statements\s*=\s*\{(?P<statements>.*?)\n\s*\}\s*,',
    re.S,
)
LONG_STRING = re.compile(r"\[\[(.*?)\]\]", re.S)


def lua_migrations(path):
    """Every migration in schema.lua, in file order, as (name, file, [statement, ...])."""
    text = open(path, encoding="utf-8").read()
    out = []
    for match in ENTRY.finditer(text):
        statements = [s.strip() for s in LONG_STRING.findall(match.group("statements"))]
        out.append((match.group("name"), match.group("file"), statements))
    return out


def sql_statements(path):
    """The statements in a .sql file, with the header comment and the trailing `;` removed."""
    lines = open(path, encoding="utf-8").read().split("\n")
    body, started = [], False
    for line in lines:
        if not started and (line.startswith("--") or line.strip() == ""):
            continue
        started = True
        body.append(line)
    text = "\n".join(body).strip()
    return [s.strip() for s in text.split(";\n") if s.strip()] if ";\n" in text \
        else [text[:-1].strip() if text.endswith(";") else text]


def main():
    migrations = lua_migrations(SCHEMA)
    if not migrations:
        print("FAIL: no migrations parsed out of server/storage/schema.lua")
        return 1

    seen, failures = set(), 0
    for name, relative, statements in migrations:
        path = os.path.join(ROOT, relative)
        seen.add(os.path.normpath(path))
        if not os.path.exists(path):
            print("FAIL %-22s %s does not exist" % (name, relative))
            failures += 1
            continue

        from_file = sql_statements(path)
        if len(from_file) != len(statements):
            print("FAIL %-22s %s has %d statement(s), schema.lua has %d"
                  % (name, relative, len(from_file), len(statements)))
            failures += 1
            continue

        for index, (lua, sql) in enumerate(zip(statements, from_file), 1):
            if lua != sql:
                print("FAIL %-22s statement %d differs from %s" % (name, index, relative))
                for line in _diff(lua, sql):
                    print("      " + line)
                failures += 1
                break
        else:
            print("ok   %-22s %s" % (name, relative))

    for entry in sorted(os.listdir(os.path.join(ROOT, "sql"))):
        path = os.path.normpath(os.path.join(ROOT, "sql", entry))
        if entry.endswith(".sql") and path not in seen:
            print("FAIL sql/%s is not claimed by any migration in schema.lua" % entry)
            failures += 1

    print("%d migration(s), %d failure(s)" % (len(migrations), failures))
    return 1 if failures else 0


def _diff(lua, sql):
    left, right = lua.split("\n"), sql.split("\n")
    for number in range(max(len(left), len(right))):
        a = left[number] if number < len(left) else "<missing>"
        b = right[number] if number < len(right) else "<missing>"
        if a != b:
            yield "line %d schema.lua: %r" % (number + 1, a)
            yield "line %d sql:        %r" % (number + 1, b)


if __name__ == "__main__":
    sys.exit(main())
