#!/usr/bin/env bash
# NVIDIA GPU util% + temp for waybar (glyph added in waybar format)
read -r util temp < <(nvidia-smi --query-gpu=utilization.gpu,temperature.gpu --format=csv,noheader,nounits 2>/dev/null | tr -d ',')
[ -z "$util" ] && exit 0
echo "${util}% ${temp}°"
