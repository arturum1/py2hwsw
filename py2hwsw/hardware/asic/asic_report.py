#!/usr/bin/env python3

# SPDX-FileCopyrightText: 2026 IObundle
#
# SPDX-License-Identifier: GPL-3.0-only

"""Extract the ASIC results of a LibreLane run and write a LaTeX table.

The metrics of the last (or requested) LibreLane run are read from
'runs/<run_tag>/final/metrics.json' and written as a table row to
'<document dir>/asic.tex', which is included by 'asic_results.tex' in the
generated core documentation.
"""

import argparse
import json
import os
import sys

# Metric names (in LibreLane's 'final/metrics.json') of the values to report
AREA_METRIC = "design__instance__area__stdcell"
GATES_METRIC = "design__instance__count__stdcell"
FFS_METRIC = "design__instance__count__class:sequential_cell"
SETUP_SLACK_METRIC = "timing__setup__ws"
CLOCK_PERIOD_METRIC = "clock__period__actual"

HEADER = """% SPDX-FileCopyrightText: 2026 IObundle
%
% SPDX-License-Identifier: GPL-3.0-only
"""


def get_run_metrics_path(runs_dir, run_tag):
    """Return the path of the metrics file of a run"""
    return os.path.join(runs_dir, run_tag, "final", "metrics.json")


def get_run_config(runs_dir, run_tag):
    """Return the configuration resolved by a run.

    The resolved configuration is preferred over the configuration file of the
    design directory, since the former also contains the values overridden in
    the command line (e.g. the clock period).
    """
    config_path = os.path.join(runs_dir, run_tag, "resolved.json")
    if not os.path.isfile(config_path):
        config_path = os.path.join(os.path.dirname(runs_dir.rstrip("/")), "config.json")
    with open(config_path) as f:
        return json.load(f)


def get_frequency(metrics, config):
    """Return the maximum frequency (MHz) achieved by the design.

    The worst setup slack is reported for the constrained clock period, so the
    period can be shortened by that slack before the timing is violated. A
    negative slack means the timing is not met at the constrained period, and
    the period has to be increased to achieve this frequency.
    """
    period = metrics.get(CLOCK_PERIOD_METRIC) or config.get("CLOCK_PERIOD")
    slack = metrics.get(SETUP_SLACK_METRIC)
    if not period:
        raise ValueError("Clock period not found in metrics nor in config")
    if slack is None:
        # No slack information: only the constrained frequency is known
        return 1000.0 / period, False
    achievable_period = period - slack
    if achievable_period <= 0:
        raise ValueError("Timing is not met at the constrained clock period")
    return 1000.0 / achievable_period, slack >= 0


def metrics_to_tex(metrics, config):
    """Return a LaTeX table row with the ASIC results of a run"""
    frequency, _ = get_frequency(metrics, config)
    return (
        f"{metrics[AREA_METRIC]:.2f} & "
        f"{int(metrics[GATES_METRIC])} & "
        f"{int(metrics[FFS_METRIC])} & "
        f"{frequency:.2f} \\\\ \\hline\n"
    )


def asic_report(runs_dir, run_tag, out_dir, flow="Classic"):
    """Write the ASIC results table of a run to the documentation directory"""
    metrics_path = get_run_metrics_path(runs_dir, run_tag)
    if not os.path.isfile(metrics_path):
        print(f"ERROR: '{metrics_path}' not found. Run the ASIC flow first.")
        return None

    with open(metrics_path) as f:
        metrics = json.load(f)
    config = get_run_config(runs_dir, run_tag)

    for metric in (AREA_METRIC, GATES_METRIC, FFS_METRIC):
        if metric not in metrics:
            print(f"ERROR: metric '{metric}' not found in '{metrics_path}'")
            return None

    pdk = config.get("PDK", "unknown PDK")
    row = metrics_to_tex(metrics, config)

    comments = ""
    slack = metrics.get(SETUP_SLACK_METRIC)
    if slack is not None and slack < 0:
        print(
            f"WARNING: timing is not met at the constrained clock period "
            f"(worst setup slack {slack} ns)."
        )
        comments = "% WARNING: the reported frequency is not met at the constrained clock period\n"

    os.makedirs(out_dir, exist_ok=True)
    out_path = os.path.join(out_dir, "asic.tex")
    with open(out_path, "w") as f:
        f.write(HEADER)
        f.write(f"% Flow: {flow}; PDK: {pdk}; run: {run_tag}\n")
        f.write(comments)
        f.write(row)
    print(f"ASIC results written to '{out_path}'.")
    return out_path


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runs_dir", default="runs", help="LibreLane runs directory")
    parser.add_argument("--run_tag", required=True, help="name of the run directory")
    parser.add_argument(
        "--out", default="../../document/tsrc", help="output documentation directory"
    )
    parser.add_argument("--flow", default="Classic", help="name of the flow used")
    args = parser.parse_args()

    if asic_report(args.runs_dir, args.run_tag, args.out, args.flow) is None:
        sys.exit(1)
