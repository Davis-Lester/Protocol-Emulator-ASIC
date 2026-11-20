"""Check post-route fanout counts in the Tiny Tapeout submission metrics."""
import argparse
import csv
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("metrics_csv", type=Path)
    args = parser.parse_args()
    with args.metrics_csv.open(newline="", encoding="utf-8") as stream:
        metrics = {row["Metric"]: row["Value"] for row in csv.DictReader(stream)}

    metric = "design__max_fanout_violation__count"
    passed = True
    for corner in ("nom_fast_1p32V_m40C", "nom_typ_1p20V_25C", "nom_slow_1p08V_125C"):
        value = metrics.get(f"{metric}__corner:{corner}", "missing")
        print(f"{corner}: {value} fanout violations")
        if value != "0":
            passed = False
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
