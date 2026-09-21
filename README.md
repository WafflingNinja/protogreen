<h1 align="center">PROTO//GREEN</h1>

<p align="center">
  <b>A green protogen Hyprland rice.</b><br>
  Hand-written Quickshell visor bar · live recolour engine · optional local AI pet.<br>
  <sub>Daily driver on CachyOS — not a demo, not a screenshot build.</sub>
</p>

<p align="center">
  <img src="demo/preview.gif" width="640" alt="PROTO//GREEN desktop preview">
</p>

<p align="center">
  <a href="demo/protogreen-demo.mp4"><b>▶ full demo video</b></a> · 49 s, 1080p
</p>

<p align="center">
  <img alt="Hyprland 0.56" src="https://img.shields.io/badge/Hyprland-0.56-2ea043?style=flat-square">
  <img alt="Quickshell 0.3" src="https://img.shields.io/badge/Quickshell-0.3-56d4dd?style=flat-square">
  <img alt="Arch / CachyOS" src="https://img.shields.io/badge/Arch%20%7C%20CachyOS-1793d1?style=flat-square">
  <img alt="MIT" src="https://img.shields.io/badge/licence-MIT-7ee787?style=flat-square">
</p>

---

## Why this one is different

Most rices are a waybar config with nice colours. This one replaces the bar entirely:
**`protogreen`**, a Quickshell (QML) shell written from scratch — a protogen visor whose
face reacts to what the machine is doing, an eye that tracks, a HUD, a theme panel that
recolours every app at once, and a small assistant that can actually drive the desktop.

<table>
<tr><td width="50%"><img src="demo/shot-desktop.png" alt="desktop with fastfetch and cava"></td>
<td width="50%"><img src="demo/shot-launcher.png" alt="rofi launcher"></td></tr>
</table>

## Stack

| | |
|---|---|
| **Compositor** | Hyprland 0.56.2 |
| **Shell / bar** | Quickshell 0.3.1 — `config/quickshell/protogreen`, 34 QML files |
| **Fallback bar** | waybar (`SUPER+SHIFT+B` swaps live) |
| **Launcher** | rofi · **Terminal** kitty · **Files** thunar |
| **Notifications** | dunst · **Lock / idle** hyprlock + hypridle |
| **Wallpaper** | mpvpaper (animated) → hyprpaper / awww (static) |
| **Palette** | bg `#0d1117` · green `#2ea043` · sage `#7ee787` · teal `#56d4dd` |
| **Built on** | CachyOS · i5-11400H · Intel UHD + RTX 2050 hybrid · 1080p144 |

## Features

### 🟩 The visor bar
`Bar.qml` · `VisorEye.qml` · `MoodFace.qml` — workspaces, media, tray, CPU/GPU/temps,
cava spectrum, battery, power profile. The face changes with system state; the eye
follows the pointer.

### 🎨 Live theme engine
`SUPER+SHIFT+T`. Pick a colour on the wheel and `scripts/theme_apply.py` rewrites
Hyprland borders, the bar, waybar, rofi, dunst, kitty, cava, fastfetch and GTK — no file
editing, no relog.

### 🤖 Pip — optional assistant
`SUPER+A`. Two halves, and **only the second needs anything installed**:

- **Commands** — open apps, switch workspaces, volume, brightness, screenshots, lock.
  Pattern matching in QML, zero dependencies, works on any machine.
- **Chat** — a local [ollama](https://ollama.com) model (`llama3.2:3b`), with a scraped
  DuckDuckGo lookup when the model admits it is unsure. ~2 GB download, ~4 GB RAM while
  answering, runs on CPU. No API key. Nothing leaves the machine except that search.

Skip ollama and everything else is untouched — the popup just says chat needs it.

### 📊 HUD
`SUPER+D`. Full-screen dashboard: sensors, toggles, tools.

### 🔋 One power & wallpaper authority
`scripts/power-watch.sh` polls every 3 s. Game starts → animated wallpaper swaps to a
frozen frame (frees the iGPU, kills the compositor stutter). On battery → power-saver
profile + static wallpaper. On AC → balanced + animated. One script decides, instead of
three fighting each other.

### 🖱️ Extras
Wayland-safe autoclicker through `/dev/uinput` (`F8`), crosshair overlay (`F4`),
screenshot pipeline with satty annotation, UI sound pack on window events, wallpaper
converter for Wallpaper Engine scenes.

## Install

Arch / CachyOS.

```bash
git clone https://github.com/rostikcermak-pixel/protogreen.git
cd protogreen
bash install.sh
```

`install.sh` asks before every step. It:

1. installs the packages (one `pacman` call, listed before it runs),
2. **renames** anything already in `~/.config` to `<name>.bak-<date>` — nothing is
   overwritten,
3. copies the configs in and rewrites the baked-in absolute paths to your `$HOME`,
4. offers two optional extras: `linux-wallpaperengine-git` (AUR, only for converting new
   Wallpaper Engine scenes) and ollama + the model (only for Pip's chat).

Files are copied, not symlinked — edit them freely afterwards.

Then log out and pick **Hyprland** at your display manager.

## Keybinds

`SUPER` is the mod.

| Key | Action |
|---|---|
| `SUPER` tap · `SUPER+R` · `SUPER+SPACE` | app launcher |
| `SUPER+Q` · `E` · `C` · `M` | terminal · files · close window · exit Hyprland |
| `SUPER+F` · `V` · `P` · `J` | fullscreen · float · pseudo · toggle split |
| `SUPER+L` | lock |
| `SUPER+1…0` / `+SHIFT` | workspace / move window there |
| `SUPER+CTRL+←→` | move window to prev/next workspace |
| `SUPER+←↑↓→` / `+SHIFT` / `+ALT` | focus / move / resize |
| `SUPER+S` · `SUPER+CTRL+S` | special workspace · send there |
| `SUPER+TAB` | cycle windows |
| `SUPER+H` | clipboard history |
| `SUPER+SHIFT+S` · `W` · `Print` | screenshot region · window · full |
| `SUPER+SHIFT+C` · `E` · `N` | colour picker · emoji · night light |
| `SUPER+SHIFT+B` | visor bar ⇄ waybar |
| `SUPER+D` · `SUPER+A` · `SUPER+SHIFT+T` | HUD · Pip · theme panel |
| `F4` · `F8` | crosshair · autoclicker |

## Layout

```
config/
├─ hypr/                     hyprland.conf · hyprlock · hypridle · hyprpaper · theme.conf
│  ├─ scripts/               theme engine, power watcher, screenshots, autoclicker, …
│  ├─ sounds/                UI sound pack
│  └─ wallpapers/            static PNG + animated mp4
├─ quickshell/protogreen/    visor bar, HUD, assistant, theme panel (QML)
└─ waybar · rofi · dunst · kitty · cava · btop · fastfetch · gtk-3.0 · qt6ct
demo/                        preview gif, full video, screenshots
install.sh
```

## Before you copy it

- Built on a **hybrid Intel + NVIDIA** laptop. The NVIDIA env vars and
  `cursor:no_hardware_cursors` at the top of `hyprland.conf` exist for that — delete them
  on AMD or plain Intel.
- Monitor line is `eDP-1 1920x1080@144`. Change it for your panel.
- The setup is **additive**: it was built next to KDE Plasma and does not touch it.
- A few configs (dunst, qt6ct, hyprpaper, the QML) need absolute paths and expand neither
  `~` nor `$HOME`, so they ship with a literal **`__HOME__`**. `install.sh` fills it in. If
  you copy files by hand instead, run:
  `grep -rlI __HOME__ ~/.config | xargs sed -i "s|__HOME__|$HOME|g"`

## Licence & credits

Configs, scripts and QML: **MIT** — see [LICENSE](LICENSE).

Not covered by it, and not my work:

- `config/hypr/wallpapers/protogen-neon.mp4` — a conversion of Wallpaper Engine workshop
  item `3157997169` ("Protogen Neon City Nachi"). Included so the rice looks as shown;
  the art belongs to its creator.
- `config/hypr/wallpapers/green-furry.png` — likewise.
- `config/hypr/sounds/` — ships with its own `License.txt` (Kenney, CC0).
- `config/cava/shaders/` — cava's bundled shaders, under their own headers.

---

<p align="center">
  Made by <b>WaffleNinja</b><br>
  <a href="https://www.tiktok.com/@waffleninja7">TikTok</a> ·
  <a href="https://t.me/TheWaffleNinja">Telegram</a> ·
  <a href="https://www.instagram.com/waffleninja444/">Instagram</a>
</p>
