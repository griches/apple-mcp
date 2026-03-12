#!/usr/bin/env python3
"""
Discover interactive macOS Accessibility elements for a running app.

Setup:
  uv venv /tmp/ax_env
  uv pip install pyobjc-framework-ApplicationServices pyobjc-framework-Cocoa --python /tmp/ax_env/bin/python

Examples:
  /tmp/ax_env/bin/python scripts/discover_ax_elements.py --app "Final Cut Pro"
  /tmp/ax_env/bin/python scripts/discover_ax_elements.py --app "Final Cut Pro" --title share
  /tmp/ax_env/bin/python scripts/discover_ax_elements.py --app Finder --max-depth 6
"""

from __future__ import annotations

import argparse
import sys

from Cocoa import NSWorkspace
from ApplicationServices import (
    AXIsProcessTrusted,
    AXUIElementCreateApplication,
    AXUIElementCopyAttributeValue,
    kAXChildrenAttribute,
    kAXDescriptionAttribute,
    kAXErrorSuccess as AX_SUCCESS,
    kAXPositionAttribute,
    kAXRoleAttribute,
    kAXRoleDescriptionAttribute,
    kAXSizeAttribute,
    kAXTitleAttribute,
    kAXValueAttribute,
    AXValueGetValue,
)


DEFAULT_ROLES = {
    "AXButton",
    "AXMenuItem",
    "AXMenuBarItem",
    "AXComboBox",
    "AXPopUpButton",
    "AXTextField",
    "AXCheckBox",
    "AXRadioButton",
    "AXMenuButton",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", default="Final Cut Pro", help="Localized app name")
    parser.add_argument("--title", default="", help="Case-insensitive title substring filter")
    parser.add_argument("--max-depth", type=int, default=8, help="AX tree recursion depth")
    return parser.parse_args()


def str_attr(element, key):
    err, value = AXUIElementCopyAttributeValue(element, key, None)
    if err == AX_SUCCESS and isinstance(value, str):
        return value
    return None


def point_of(element):
    err_p, pos_val = AXUIElementCopyAttributeValue(element, kAXPositionAttribute, None)
    err_s, size_val = AXUIElementCopyAttributeValue(element, kAXSizeAttribute, None)
    if err_p != AX_SUCCESS or err_s != AX_SUCCESS:
        return None, None

    result_p = AXValueGetValue(pos_val, 1, None)  # kAXValueCGPointType
    result_s = AXValueGetValue(size_val, 2, None)  # kAXValueCGSizeType

    ok_p, x, y = False, 0.0, 0.0
    ok_s, width, height = False, 0.0, 0.0

    if result_p and len(result_p) == 2:
        point_ok, point_val = result_p
        if point_ok and hasattr(point_val, "x"):
            x, y = point_val.x, point_val.y
            ok_p = True

    if result_s and len(result_s) == 2:
        size_ok, size_val2 = result_s
        if size_ok and hasattr(size_val2, "width"):
            width, height = size_val2.width, size_val2.height
            ok_s = True

    if ok_p and ok_s and width > 0 and height > 0:
        return x + width / 2, y + height / 2

    return None, None


def collect(element, results, title_filter: str, max_depth: int, depth: int = 0):
    if depth > max_depth:
        return

    role = str_attr(element, kAXRoleAttribute)
    if role in DEFAULT_ROLES:
        title = (
            str_attr(element, kAXTitleAttribute)
            or str_attr(element, kAXDescriptionAttribute)
            or str_attr(element, kAXRoleDescriptionAttribute)
            or str_attr(element, kAXValueAttribute)
            or ""
        )
        if not title_filter or title_filter in title.lower():
            x, y = point_of(element)
            if x is not None:
                results.append((role, title, int(x), int(y)))

    err, children = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute, None)
    if err == AX_SUCCESS and children:
        for child in children:
            collect(child, results, title_filter, max_depth, depth + 1)


def main():
    args = parse_args()

    if not AXIsProcessTrusted():
        print("ERROR: Accessibility permission not granted.", file=sys.stderr)
        sys.exit(1)

    app = next(
        (
            candidate
            for candidate in NSWorkspace.sharedWorkspace().runningApplications()
            if candidate.localizedName() == args.app
        ),
        None,
    )
    if app is None:
        print(f"ERROR: {args.app} is not running.", file=sys.stderr)
        sys.exit(1)

    results = []
    collect(
        AXUIElementCreateApplication(app.processIdentifier()),
        results,
        args.title.lower(),
        args.max_depth,
    )

    if not results:
        print(f"No interactive elements found in {args.app}.")
        return

    print(f"\n{args.app} — {len(results)} interactive elements\n")
    print(f"{'ROLE':<22} {'TITLE':<60} {'X':>6} {'Y':>6}")
    print("-" * 100)
    for role, title, x, y in sorted(results, key=lambda row: (row[0], row[1].lower(), row[2], row[3])):
        print(f"{role:<22} {title[:60]:<60} {x:>6} {y:>6}")


if __name__ == "__main__":
    main()
