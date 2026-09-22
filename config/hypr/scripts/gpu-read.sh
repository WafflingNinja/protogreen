#!/usr/bin/env bash
# Print "<util%> <temp°C>" for the primary GPU, whatever vendor it is.
#
# Detection happens HERE rather than in the installer on purpose: people who copy
# config/ by hand (see the README FAQ) never run install.sh, and a machine can grow
# or lose a dGPU after install. One probe, two callers — gpu.sh (waybar) and
# services/sysinfo.sh (visor bar).
#
# Always exits 0 and always prints two numbers. "0 0" means "no reading", which is
# what both callers already treat as absent.

# NVIDIA first: on a hybrid laptop the dGPU is the one worth reporting.
if command -v nvidia-smi >/dev/null 2>&1; then
    read -r u t < <(nvidia-smi --query-gpu=utilization.gpu,temperature.gpu \
        --format=csv,noheader,nounits 2>/dev/null | tr -d ',' | head -1)
    # nvidia-smi can exist with no working GPU (driver package left behind)
    if [ -n "${u:-}" ]; then
        echo "$u ${t:-0}"
        exit 0
    fi
fi

# AMD: gpu_busy_percent is amdgpu-only, so its presence IS the vendor test.
for dev in /sys/class/drm/card*/device; do
    [ -r "$dev/gpu_busy_percent" ] || continue
    u=$(< "$dev/gpu_busy_percent")
    t=0
    for h in "$dev"/hwmon/hwmon*/temp1_input; do
        [ -r "$h" ] && { t=$(( $(< "$h") / 1000 )); break; }
    done
    echo "${u:-0} $t"
    exit 0
done

# Intel (i915/xe): no busy-percent counter without root or intel_gpu_top, so util
# stays 0 and only the temperature is real. Reporting a fake number would be worse.
for h in /sys/class/drm/card*/device/hwmon/hwmon*/temp1_input; do
    [ -r "$h" ] && { echo "0 $(( $(< "$h") / 1000 ))"; exit 0; }
done

echo "0 0"
