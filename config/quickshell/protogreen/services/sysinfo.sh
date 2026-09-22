#!/usr/bin/env bash
# Emit "cpu;ctemp;mem;gpu;gtemp" once every INTERVAL seconds for the visor bar.
# cpu = % busy, ctemp = CPU °C, mem = % used, gpu = % util, gtemp = GPU °C
INTERVAL=3
ZONE=/sys/class/thermal/thermal_zone5/temp   # x86_pkg_temp
gpu_every=5   # poll the GPU every Nth tick (15s; nvidia-smi costs ~100-300ms each)
GPU_READ=__HOME__/.config/hypr/scripts/gpu-read.sh   # vendor-agnostic: nvidia/amd/intel
tick=0

read_cpu() { read -r _ a b c d rest < /proc/stat; echo "$((a+b+c)) $((a+b+c+d))"; }

prev=($(read_cpu))
while :; do
    sleep "$INTERVAL"
    cur=($(read_cpu))
    du=$(( ${cur[0]} - ${prev[0]} )); dt=$(( ${cur[1]} - ${prev[1]} ))
    cpu=0; [ "$dt" -gt 0 ] && cpu=$(( 100 * du / dt ))
    prev=("${cur[@]}")

    ctemp=0; [ -r "$ZONE" ] && ctemp=$(( $(cat "$ZONE") / 1000 ))

    mem=$(awk '/MemTotal/{t=$2}/MemAvailable/{a=$2}END{if(t>0)printf "%d",(t-a)*100/t}' /proc/meminfo)

    if [ $(( tick % gpu_every )) -eq 0 ]; then
        read -r gpu gtemp < <("$GPU_READ" 2>/dev/null)
        [ -z "$gpu" ] && gpu=0; [ -z "$gtemp" ] && gtemp=0
    fi
    tick=$((tick+1))

    echo "${cpu};${ctemp};${mem};${gpu:-0};${gtemp:-0}"
done
