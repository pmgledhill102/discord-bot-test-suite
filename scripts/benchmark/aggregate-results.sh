#!/bin/bash
# Aggregate benchmark results and generate report
# Usage: ./scripts/benchmark/aggregate-results.sh
#
# Reads individual result files and produces:
# - Summary JSON
# - Markdown report table

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESULTS_DIR="$SCRIPT_DIR/results"
SUMMARY_FILE="$SCRIPT_DIR/benchmark-summary.json"
REPORT_FILE="$SCRIPT_DIR/benchmark-report.md"

if [[ ! -d "$RESULTS_DIR" ]]; then
    echo "ERROR: Results directory not found. Run benchmarks first."
    exit 1
fi

echo "Aggregating benchmark results..."

# Aggregate all results using Python for easier JSON handling
python3 << 'PYTHON_SCRIPT'
import json
import os
from pathlib import Path
from statistics import mean, stdev
from datetime import datetime

results_dir = Path("RESULTS_DIR_PLACEHOLDER")
summary_file = Path("SUMMARY_FILE_PLACEHOLDER")
report_file = Path("REPORT_FILE_PLACEHOLDER")

# Collect all results by service
services = {}

for result_file in results_dir.glob("*.json"):
    try:
        with open(result_file) as f:
            data = json.load(f)

        if data.get("status") != "success":
            continue

        service = data["service"]
        if service not in services:
            services[service] = []

        services[service].append({
            "startup_time": data["startup_time_seconds"],
            "ping_time": data["avg_ping_time_seconds"],
            "memory_mb": data["memory_usage_mb"],
            "image_size_mb": data["image_size_mb"]
        })
    except Exception as e:
        print(f"Warning: Could not parse {result_file}: {e}")

# Calculate statistics for each service
summary = {
    "generated_at": datetime.now().isoformat(),
    "services": {}
}

for service, runs in sorted(services.items()):
    if not runs:
        continue

    startup_times = [r["startup_time"] for r in runs]
    ping_times = [r["ping_time"] for r in runs]
    memory_values = [r["memory_mb"] for r in runs]
    image_size = runs[0]["image_size_mb"]  # Same for all runs

    summary["services"][service] = {
        "iterations": len(runs),
        "image_size_mb": round(image_size, 2),
        "startup_time": {
            "mean": round(mean(startup_times), 3),
            "min": round(min(startup_times), 3),
            "max": round(max(startup_times), 3),
            "stdev": round(stdev(startup_times), 3) if len(startup_times) > 1 else 0
        },
        "ping_time": {
            "mean": round(mean(ping_times) * 1000, 2),  # Convert to ms
            "min": round(min(ping_times) * 1000, 2),
            "max": round(max(ping_times) * 1000, 2)
        },
        "memory_mb": {
            "mean": round(mean(memory_values), 2),
            "min": round(min(memory_values), 2),
            "max": round(max(memory_values), 2)
        }
    }

# Save summary JSON
with open(summary_file, "w") as f:
    json.dump(summary, f, indent=2)

print(f"Summary saved to: {summary_file}")

# Generate Markdown report
report_lines = [
    "# Performance Benchmark Results",
    "",
    f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
    "",
    "## Summary Table",
    "",
    "| Service | Image Size | Startup Time | Ping Latency | Memory |",
    "|---------|------------|--------------|--------------|--------|",
]

# Sort by startup time (fastest first)
sorted_services = sorted(
    summary["services"].items(),
    key=lambda x: x[1]["startup_time"]["mean"]
)

for service, stats in sorted_services:
    row = (
        f"| {service} | "
        f"{stats['image_size_mb']:.1f} MB | "
        f"{stats['startup_time']['mean']:.3f}s | "
        f"{stats['ping_time']['mean']:.2f}ms | "
        f"{stats['memory_mb']['mean']:.1f} MB |"
    )
    report_lines.append(row)

report_lines.extend([
    "",
    "## Detailed Results",
    "",
    "### Startup Time (seconds)",
    "",
    "Time from `docker run` to health endpoint responding.",
    "",
    "| Service | Mean | Min | Max | StdDev |",
    "|---------|------|-----|-----|--------|",
])

for service, stats in sorted_services:
    st = stats["startup_time"]
    report_lines.append(
        f"| {service} | {st['mean']:.3f} | {st['min']:.3f} | {st['max']:.3f} | {st['stdev']:.3f} |"
    )

report_lines.extend([
    "",
    "### Image Size (MB)",
    "",
    "| Service | Size |",
    "|---------|------|",
])

# Sort by image size
for service, stats in sorted(summary["services"].items(), key=lambda x: x[1]["image_size_mb"]):
    report_lines.append(f"| {service} | {stats['image_size_mb']:.1f} |")

report_lines.extend([
    "",
    "### Memory Usage (MB)",
    "",
    "Memory usage at idle after startup.",
    "",
    "| Service | Mean | Min | Max |",
    "|---------|------|-----|-----|",
])

for service, stats in sorted(summary["services"].items(), key=lambda x: x[1]["memory_mb"]["mean"]):
    mem = stats["memory_mb"]
    report_lines.append(f"| {service} | {mem['mean']:.1f} | {mem['min']:.1f} | {mem['max']:.1f} |")

report_lines.extend([
    "",
    "---",
    "",
    "*Benchmarks run with Docker Desktop on local machine.*"
])

# Save report
with open(report_file, "w") as f:
    f.write("\n".join(report_lines))

print(f"Report saved to: {report_file}")

# Print quick summary to terminal
print("\n" + "=" * 50)
print("Quick Summary (sorted by startup time)")
print("=" * 50)
print(f"{'Service':<20} {'Startup':>10} {'Ping':>10} {'Memory':>10} {'Image':>10}")
print("-" * 60)
for service, stats in sorted_services:
    print(f"{service:<20} {stats['startup_time']['mean']:>9.3f}s {stats['ping_time']['mean']:>9.2f}ms {stats['memory_mb']['mean']:>9.1f}MB {stats['image_size_mb']:>9.1f}MB")

PYTHON_SCRIPT

# Replace placeholders with actual paths
python3 << EOF
import re

script = open("$SCRIPT_DIR/aggregate-results.sh").read()
# This is a workaround - the actual aggregation happens above
EOF

# Actually run the Python script with correct paths
python3 -c "
import json
import os
from pathlib import Path
from statistics import mean, stdev
from datetime import datetime

results_dir = Path('$RESULTS_DIR')
summary_file = Path('$SUMMARY_FILE')
report_file = Path('$REPORT_FILE')

# Collect all results by service
services = {}

for result_file in results_dir.glob('*.json'):
    try:
        with open(result_file) as f:
            data = json.load(f)

        if data.get('status') != 'success':
            continue

        service = data['service']
        if service not in services:
            services[service] = []

        services[service].append({
            'startup_time': data['startup_time_seconds'],
            'ping_time': data['avg_ping_time_seconds'],
            'memory_mb': data['memory_usage_mb'],
            'image_size_mb': data['image_size_mb']
        })
    except Exception as e:
        print(f'Warning: Could not parse {result_file}: {e}')

if not services:
    print('No results found!')
    exit(1)

# Calculate statistics for each service
summary = {
    'generated_at': datetime.now().isoformat(),
    'services': {}
}

for service, runs in sorted(services.items()):
    if not runs:
        continue

    startup_times = [r['startup_time'] for r in runs]
    ping_times = [r['ping_time'] for r in runs]
    memory_values = [r['memory_mb'] for r in runs]
    image_size = runs[0]['image_size_mb']

    summary['services'][service] = {
        'iterations': len(runs),
        'image_size_mb': round(image_size, 2),
        'startup_time': {
            'mean': round(mean(startup_times), 3),
            'min': round(min(startup_times), 3),
            'max': round(max(startup_times), 3),
            'stdev': round(stdev(startup_times), 3) if len(startup_times) > 1 else 0
        },
        'ping_time': {
            'mean': round(mean(ping_times) * 1000, 2),
            'min': round(min(ping_times) * 1000, 2),
            'max': round(max(ping_times) * 1000, 2)
        },
        'memory_mb': {
            'mean': round(mean(memory_values), 2),
            'min': round(min(memory_values), 2),
            'max': round(max(memory_values), 2)
        }
    }

# Save summary JSON
with open(summary_file, 'w') as f:
    json.dump(summary, f, indent=2)

print(f'Summary saved to: {summary_file}')

# Generate Markdown report
report_lines = [
    '# Performance Benchmark Results',
    '',
    f'Generated: {datetime.now().strftime(\"%Y-%m-%d %H:%M:%S\")}',
    '',
    '## Summary Table',
    '',
    '| Service | Image Size | Startup Time | Ping Latency | Memory |',
    '|---------|------------|--------------|--------------|--------|',
]

sorted_services = sorted(
    summary['services'].items(),
    key=lambda x: x[1]['startup_time']['mean']
)

for service, stats in sorted_services:
    row = (
        f\"| {service} | \"
        f\"{stats['image_size_mb']:.1f} MB | \"
        f\"{stats['startup_time']['mean']:.3f}s | \"
        f\"{stats['ping_time']['mean']:.2f}ms | \"
        f\"{stats['memory_mb']['mean']:.1f} MB |\"
    )
    report_lines.append(row)

report_lines.extend([
    '',
    '---',
    '',
    '*Benchmarks run with Docker Desktop on local machine.*'
])

with open(report_file, 'w') as f:
    f.write('\n'.join(report_lines))

print(f'Report saved to: {report_file}')

print()
print('=' * 60)
print('Quick Summary (sorted by startup time)')
print('=' * 60)
print(f\"{'Service':<20} {'Startup':>10} {'Ping':>10} {'Memory':>10} {'Image':>10}\")
print('-' * 60)
for service, stats in sorted_services:
    print(f\"{service:<20} {stats['startup_time']['mean']:>9.3f}s {stats['ping_time']['mean']:>9.2f}ms {stats['memory_mb']['mean']:>9.1f}MB {stats['image_size_mb']:>9.1f}MB\")
"
