#!/usr/bin/env python3
import json
import sys
from datetime import datetime, timezone, tzinfo
from pathlib import Path

import matplotlib.dates as mdates
import matplotlib.pyplot as plt
from matplotlib.ticker import FuncFormatter


def parse_jsonl(path: Path):
    times = []
    rates = []
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            entry = json.loads(line)
        except json.JSONDecodeError:
            continue
        ts = datetime.fromisoformat(entry["timestamp"].replace("Z", "+00:00"))
        times.append(ts)
        rates.append(entry.get("hashrate", 0))
    return times, rates


def format_rate(rate: int) -> str:
    units = [
        (10**18, "EH/s"),
        (10**15, "PH/s"),
        (10**12, "TH/s"),
        (10**9, "GH/s"),
        (10**6, "MH/s"),
        (10**3, "kH/s"),
    ]
    for scale, unit in units:
        if rate >= scale:
            return f"{rate / scale:.3g} {unit}"
    return f"{rate} H/s"


def log_ticks():
    ticks = []
    labels = []
    steps = [1, 10, 100]
    prefixes = [
        (10**3, "kH/s"),
        (10**6, "MH/s"),
        (10**9, "GH/s"),
        (10**12, "TH/s"),
        (10**15, "PH/s"),
        (10**18, "EH/s"),
    ]
    for scale, unit in prefixes:
        for step in steps:
            value = float(step * scale)
            ticks.append(value)
            labels.append(f"{step} {unit}")
    return ticks, labels


def snap_ylim(rates, ticks):
    ticks_sorted = sorted(ticks)
    min_rate = min(rates)
    max_rate = max(rates)

    ymin = ticks_sorted[0]
    for t in reversed(ticks_sorted):
        if t <= min_rate:
            ymin = t
            break

    ymax = ticks_sorted[-1]
    for t in ticks_sorted:
        if t >= max_rate:
            ymax = t
            break

    return ymin, ymax


def format_xtick(x, _pos=None):
    dt = mdates.num2date(x, tz=timezone.utc)
    if dt.hour == 0:
        return dt.strftime("%d/%m\n%H:%M")
    return dt.strftime("%H:%M")


def main():
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <hashrate.jsonl> <output.png>", file=sys.stderr)
        sys.exit(1)

    log_path = Path(sys.argv[1])
    output_path = Path(sys.argv[2])

    times, rates = parse_jsonl(log_path)
    if not times:
        print("No data found.", file=sys.stderr)
        sys.exit(1)

    last_time = times[-1]
    last_rate = rates[-1]

    outer_bg_color = "#000000"
    plot_bg_color = "#0b1d3a"
    text_color = "#ffffff"
    date_color = "#8ecbff"
    rate_color = "#8dff9a"

    fig, ax = plt.subplots(figsize=(10, 5), facecolor=outer_bg_color)
    fig.patch.set_facecolor(outer_bg_color)
    ax.set_facecolor(plot_bg_color)

    ax.plot(times, rates, marker="o", linewidth=1.5, color=text_color)
    ax.set_xlabel("Time (UTC)", color=text_color)
    ax.set_ylabel("Hashrate", color=text_color)
    ax.set_yscale("log")

    ticks, labels = log_ticks()
    ax.set_yticks(ticks)
    ax.set_yticklabels(labels, color=rate_color)
    ymin, ymax = snap_ylim(rates, ticks)
    ax.set_ylim(ymin, ymax)

    ax.xaxis.set_major_locator(
        mdates.HourLocator(byhour=list(range(0, 24, 4)), tz=timezone.utc)
    )
    ax.xaxis.set_major_formatter(FuncFormatter(format_xtick))
    ax.set_xlim(times[0], times[-1])
    plt.setp(ax.get_xticklabels(), rotation=45, ha="right", color=date_color)
    ax.tick_params(axis="y", colors=rate_color)
    ax.tick_params(axis="x", colors=date_color)

    title_date = last_time.strftime("%d/%m")
    title_time = last_time.strftime("%H:%M")
    title_rate = format_rate(last_rate)

    ax.text(
        0.5, 1.12, "SRI Pool mainnet",
        transform=ax.transAxes, ha="center", va="bottom", color=rate_color,
    )

    segments = [
        f"Last entry: {title_date}",
        f" | {title_time}",
        f" | {title_rate}",
    ]
    colors = [text_color, date_color, rate_color]

    y_pos = 1.04
    fig.canvas.draw()
    renderer = fig.canvas.get_renderer()
    ax_bbox = ax.get_window_extent(renderer=renderer)
    y_pix = ax.transAxes.transform((0, y_pos))[1]

    temp_texts = []
    widths = []
    for segment in segments:
        t = ax.text(
            0, y_pos, segment,
            transform=ax.transAxes, ha="left", va="bottom", alpha=0.0,
        )
        temp_texts.append(t)
        bbox = t.get_window_extent(renderer=renderer)
        widths.append(bbox.width)

    total_width = sum(widths)
    start_x_pix = ax_bbox.x0 + (ax_bbox.width - total_width) / 2

    x_pix = start_x_pix
    for segment, color, width in zip(segments, colors, widths):
        x_axes = ax.transAxes.inverted().transform((x_pix, y_pix))[0]
        ax.text(
            x_axes, y_pos, segment,
            transform=ax.transAxes, ha="left", va="bottom", color=color,
        )
        x_pix += width

    for t in temp_texts:
        t.remove()

    ax.grid(
        True, which="both", linestyle="--", linewidth=0.5,
        alpha=0.3, color=date_color,
    )
    plt.tight_layout()

    output_path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(
        output_path,
        dpi=150,
        facecolor=fig.get_facecolor(),
        edgecolor="none",
        transparent=False,
    )
    print(f"Saved plot to {output_path}")


if __name__ == "__main__":
    main()
