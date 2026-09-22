#!/usr/bin/env bash
# GPU util% + temp for waybar (glyph added in waybar format).
# Vendor detection lives in gpu-read.sh — NVIDIA, AMD and Intel all land here.
read -r util temp < <("$(dirname "$(readlink -f "$0")")/gpu-read.sh")
[ -z "$util" ] && exit 0
echo "${util}% ${temp}°"
