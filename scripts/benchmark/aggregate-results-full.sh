#!/bin/bash
# Aggregate full benchmark results (with Pub/Sub testing)
# Usage: ./scripts/benchmark/aggregate-results-full.sh

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

python3 -c "
import json
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

        # Handle both old format and new format with ping_test/interaction_test
        if 'ping_test' in data:
            # New format
            services[service].append({
                'image_size_mb': data.get('image_size_mb', 0),
                'ping_startup': data['ping_test']['startup_time_seconds'],
                'ping_latency': data['ping_test']['avg_ping_time_seconds'],
                'ping_memory': data['ping_test']['memory_usage_mb'],
                'interact_startup': data['interaction_test']['startup_time_seconds'],
                'interact_latency': data['interaction_test']['interaction_latency_seconds'],
                'pubsub_received': data['interaction_test'].get('pubsub_received', False),
                'pubsub_latency': data['interaction_test'].get('pubsub_latency_seconds', 0),
                'interact_memory': data['interaction_test']['memory_usage_mb'],
            })
        else:
            # Old format - use same values for both
            services[service].append({
                'image_size_mb': data.get('image_size_mb', 0),
                'ping_startup': data['startup_time_seconds'],
                'ping_latency': data['avg_ping_time_seconds'],
                'ping_memory': data['memory_usage_mb'],
                'interact_startup': data['startup_time_seconds'],
                'interact_latency': data['avg_ping_time_seconds'],
                'pubsub_received': False,
                'pubsub_latency': 0,
                'interact_memory': data['memory_usage_mb'],
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

    image_size = runs[0]['image_size_mb']

    # Ping test stats
    ping_startups = [r['ping_startup'] for r in runs]
    ping_latencies = [r['ping_latency'] for r in runs]
    ping_memories = [r['ping_memory'] for r in runs]

    # Interaction test stats
    interact_startups = [r['interact_startup'] for r in runs]
    interact_latencies = [r['interact_latency'] for r in runs]
    interact_memories = [r['interact_memory'] for r in runs]
    pubsub_success_rate = sum(1 for r in runs if r['pubsub_received']) / len(runs) * 100
    pubsub_latencies = [r['pubsub_latency'] for r in runs if r['pubsub_received'] and r['pubsub_latency'] > 0]

    summary['services'][service] = {
        'iterations': len(runs),
        'image_size_mb': round(image_size, 2),
        'ping_test': {
            'startup_time': {
                'mean': round(mean(ping_startups), 3),
                'min': round(min(ping_startups), 3),
                'max': round(max(ping_startups), 3),
            },
            'latency_ms': round(mean(ping_latencies) * 1000, 2),
            'memory_mb': round(mean(ping_memories), 2),
        },
        'interaction_test': {
            'startup_time': {
                'mean': round(mean(interact_startups), 3),
                'min': round(min(interact_startups), 3),
                'max': round(max(interact_startups), 3),
            },
            'latency_ms': round(mean(interact_latencies) * 1000, 2),
            'memory_mb': round(mean(interact_memories), 2),
            'pubsub_success_rate': round(pubsub_success_rate, 1),
            'pubsub_latency_ms': round(mean(pubsub_latencies) * 1000, 2) if pubsub_latencies else 0,
        },
    }

# Save summary JSON
with open(summary_file, 'w') as f:
    json.dump(summary, f, indent=2)

print(f'Summary saved to: {summary_file}')

# Generate Markdown report
report_lines = [
    '# Performance Benchmark Results (Full)',
    '',
    f'Generated: {datetime.now().strftime(\"%Y-%m-%d %H:%M:%S\")}',
    '',
    '## Summary',
    '',
    'This benchmark tests each service with two separate cold-start scenarios:',
    '1. **Ping Test**: Container starts, health check, ping latency measured, container killed',
    '2. **Interaction Test**: Container starts (with Pub/Sub), slash command sent, Pub/Sub message verified, container killed',
    '',
    '## Ping Test Results',
    '',
    '| Service | Startup | Ping Latency | Memory | Image Size |',
    '|---------|---------|--------------|--------|------------|',
]

# Sort by ping startup time
sorted_by_ping = sorted(
    summary['services'].items(),
    key=lambda x: x[1]['ping_test']['startup_time']['mean']
)

for service, stats in sorted_by_ping:
    pt = stats['ping_test']
    row = (
        f\"| {service} | \"
        f\"{pt['startup_time']['mean']:.3f}s | \"
        f\"{pt['latency_ms']:.2f}ms | \"
        f\"{pt['memory_mb']:.1f} MB | \"
        f\"{stats['image_size_mb']:.1f} MB |\"
    )
    report_lines.append(row)

report_lines.extend([
    '',
    '## Interaction Test Results (with Pub/Sub)',
    '',
    '| Service | Startup | Interaction Latency | Pub/Sub | Memory |',
    '|---------|---------|---------------------|---------|--------|',
])

# Sort by interaction startup time
sorted_by_interact = sorted(
    summary['services'].items(),
    key=lambda x: x[1]['interaction_test']['startup_time']['mean']
)

for service, stats in sorted_by_interact:
    it = stats['interaction_test']
    pubsub_status = f\"{it['pubsub_success_rate']:.0f}%\" if it['pubsub_success_rate'] > 0 else 'N/A'
    row = (
        f\"| {service} | \"
        f\"{it['startup_time']['mean']:.3f}s | \"
        f\"{it['latency_ms']:.2f}ms | \"
        f\"{pubsub_status} | \"
        f\"{it['memory_mb']:.1f} MB |\"
    )
    report_lines.append(row)

report_lines.extend([
    '',
    '## Key Findings',
    '',
])

# Find winners
fastest_ping = min(summary['services'].items(), key=lambda x: x[1]['ping_test']['startup_time']['mean'])
fastest_interact = min(summary['services'].items(), key=lambda x: x[1]['interaction_test']['startup_time']['mean'])
smallest_image = min(summary['services'].items(), key=lambda x: x[1]['image_size_mb'])
lowest_memory = min(summary['services'].items(), key=lambda x: x[1]['ping_test']['memory_mb'])

report_lines.extend([
    f\"- **Fastest Ping Startup**: {fastest_ping[0]} ({fastest_ping[1]['ping_test']['startup_time']['mean']:.3f}s)\",
    f\"- **Fastest Interaction Startup**: {fastest_interact[0]} ({fastest_interact[1]['interaction_test']['startup_time']['mean']:.3f}s)\",
    f\"- **Smallest Image**: {smallest_image[0]} ({smallest_image[1]['image_size_mb']:.1f} MB)\",
    f\"- **Lowest Memory**: {lowest_memory[0]} ({lowest_memory[1]['ping_test']['memory_mb']:.1f} MB)\",
    '',
    '---',
    '',
    '*Benchmarks run with Docker Desktop. Each test uses a completely fresh container (killed between tests).*',
])

with open(report_file, 'w') as f:
    f.write('\n'.join(report_lines))

print(f'Report saved to: {report_file}')

# Print quick summary
print()
print('=' * 80)
print('Ping Test Summary (sorted by startup time)')
print('=' * 80)
print(f\"{'Service':<20} {'Startup':>10} {'Ping':>12} {'Memory':>10} {'Image':>10}\")
print('-' * 80)
for service, stats in sorted_by_ping:
    pt = stats['ping_test']
    print(f\"{service:<20} {pt['startup_time']['mean']:>9.3f}s {pt['latency_ms']:>11.2f}ms {pt['memory_mb']:>9.1f}MB {stats['image_size_mb']:>9.1f}MB\")

print()
print('=' * 80)
print('Interaction Test Summary (sorted by startup time)')
print('=' * 80)
print(f\"{'Service':<20} {'Startup':>10} {'Latency':>12} {'Pub/Sub':>10} {'Memory':>10}\")
print('-' * 80)
for service, stats in sorted_by_interact:
    it = stats['interaction_test']
    pubsub = f\"{it['pubsub_success_rate']:.0f}%\" if it['pubsub_success_rate'] > 0 else 'N/A'
    print(f\"{service:<20} {it['startup_time']['mean']:>9.3f}s {it['latency_ms']:>11.2f}ms {pubsub:>10} {it['memory_mb']:>9.1f}MB\")
"
