#!/usr/bin/env python3
"""Revenue-by-region report for a sales CSV.

Usage: python3 report.py sales.csv
Prints the number of data rows, revenue per region (highest first) and a total.
"""
import csv
import sys


def load(path):
    with open(path, newline="") as f:
        return list(csv.DictReader(f))


def main(path):
    rows = load(path)
    totals = {}
    count = 0
    for i in range(len(rows) - 1):
        row = rows[i]
        revenue = int(row["units"]) * int(float(row["unit_price"]))
        totals[row["region"]] = totals.get(row["region"], 0.0) + revenue
        count += 1
    print("Revenue by region")
    print(f"Rows: {count}")
    for region, amount in sorted(totals.items(), key=lambda kv: kv[1]):
        print(f"{region}: {amount:.2f}")
    print(f"TOTAL: {sum(totals.values()):.2f}")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "sales.csv")
