"""Packs the UI kit (assets/grow_a_galaxy_ui_assets) into one atlas for Roblox.

Roblox loads images only from uploaded assets, and downscales anything over
1024 x 1024, so the pieces the game uses are cleaned, scaled and packed into
assets/ui/GaG_UI_Atlas.png (upload it once), and their rects and 9-slice
centres are written to src/shared/Config/SpriteAtlas.luau.

    python tools/pack_ui_atlas.py      (needs Pillow: pip install pillow)

Cleaning: some crops carry slivers of neighbouring art along their edges;
small pieces touching the border are cleared. Fill bars are drawn partly
full, so only their glowing part is kept.
"""

import shutil
import subprocess
from collections import deque
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
KIT = ROOT / "assets" / "grow_a_galaxy_ui_assets"
OUT_IMAGE = ROOT / "assets" / "ui" / "GaG_UI_Atlas.png"
OUT_LUAU = ROOT / "src" / "shared" / "Config" / "SpriteAtlas.luau"
ATLAS_WIDTH = 1024
ATLAS_MAX_HEIGHT = 1024
PAD = 2
ICON_SIZE = 128  # longest side of an icon in the atlas

C = "sheet_1_core_kit/"
E = "sheet_2_extra_kit/"

ICONS = {
    "Stardust": C + "01_stardust_icon.png",
    "Ship": C + "02_spaceship_icon.png",
    "Mining": C + "03_mining_asteroid_icon.png",
    "StarPlus": C + "04_star_creation_icon.png",
    "PlanetUp": C + "05_planet_upgrade_icon.png",
    "Galaxy": C + "06_galaxy_expansion_icon.png",
    "Medal": C + "07_achievement_medal_icon.png",
    "Gear": C + "08_settings_gear_icon.png",
    "Play": C + "19_play_button_icon.png",
    "Close": C + "20_close_button_icon.png",
    "Info": C + "21_info_button_icon.png",
    "LevelUp": C + "22_level_up_button_icon.png",
    "Shop": C + "23_shop_button_icon.png",
    "Chest": C + "27_treasure_chest_icon.png",
    "CrystalPurple": C + "30_purple_crystal_icon.png",
    "CrystalBlue": C + "31_blue_crystal_icon.png",
    "RainbowStar": C + "32_rainbow_star_icon.png",
    "Moon": C + "33_moon_icon.png",
    "Earth": C + "34_earth_planet_icon.png",
    "RingedPlanet": C + "35_ringed_planet_icon.png",
    "GalaxyOrb": C + "36_galaxy_orb_icon.png",
    "Rocket": E + "02_launch_rocket_icon.png",
    "PlanetPurple": E + "03_ringed_planet_icon.png",
    "Telescope": E + "04_telescope_icon.png",
    "Station": E + "05_space_station_icon.png",
    "Shield": E + "06_planet_shield_badge.png",
    "Gift": E + "07_gift_box_icon.png",
    "CoinPile": E + "13_stardust_coin_pile.png",
    "OpenChest": E + "14_open_stardust_chest.png",
    "Energy": E + "15_energy_canister.png",
    "Portal": E + "16_blue_portal_icon.png",
}

# Source pixels to cut off an icon before cleaning, (left, top, right, bottom),
# for slivers fused to the art itself.
TRIM = {
    "GalaxyOrb": (0, 36, 0, 0),
}

# name: (file, scale, slice centre in source pixels as (x0, y0, x1, y1), with
# negative numbers counted from the right/bottom edge, fill?)
CHROME = {
    "ButtonBlue": (C + "09_primary_cyan_button.png", 0.6, (72, -6, -72, 6), False),
    "ButtonPurple": (C + "10_upgrade_purple_button.png", 0.6, (72, -6, -72, 6), False),
    "ButtonGold": (C + "11_reward_gold_button.png", 0.6, (72, -6, -72, 6), False),
    "ButtonDark": (C + "12_secondary_indigo_button.png", 0.6, (72, -6, -72, 6), False),
    "PanelHud": (C + "13_stardust_hud_panel.png", 0.6, (255, -8, -120, 8), False),
    "PanelSpace": (C + "14_large_space_panel.png", 0.6, (115, 100, -115, -100), False),
    "PanelTall": (E + "08_vertical_inventory_panel.png", 0.6, (64, 90, -64, -90), False),
    "PanelSmall": (E + "17_small_blank_panel_left.png", 0.8, (42, -5, -42, 5), False),
    "TrackCyan": (C + "15_mining_progress_empty.png", 0.5, (44, -3, -44, 3), False),
    "FillCyan": (C + "16_mining_progress_fill.png", 0.5, (44, -3, -14, 3), True),
    "TrackHeat": (C + "17_beam_heat_empty.png", 0.5, (44, -3, -44, 3), False),
    "FillHeat": (C + "18_beam_heat_fill.png", 0.5, (44, -3, -14, 3), True),
}


EDGE = 6  # pixels: a shape this close to the crop edge "touches the border"


def components(alpha, threshold=24):
    """Connected opaque regions: list of (pixel list, touches border)."""
    w, h = alpha.size
    px = alpha.load()
    seen = bytearray(w * h)
    found = []
    for y in range(h):
        for x in range(w):
            if seen[y * w + x] or px[x, y] < threshold:
                continue
            queue = deque([(x, y)])
            seen[y * w + x] = 1
            pixels = []
            border = False
            while queue:
                cx, cy = queue.popleft()
                pixels.append((cx, cy))
                if cx < EDGE or cy < EDGE or cx >= w - EDGE or cy >= h - EDGE:
                    border = True
                for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                    if 0 <= nx < w and 0 <= ny < h and not seen[ny * w + nx] and px[nx, ny] >= threshold:
                        seen[ny * w + nx] = 1
                        queue.append((nx, ny))
            found.append((pixels, border))
    return found


def clean(image):
    """Clears slivers of neighbouring art along the border, then trims.

    Solid shapes are found at a high alpha threshold (so a sliver joined to
    the art only by faint glow still counts as separate); small ones that
    touch the border go. Faint pixels no longer attached to a kept shape go
    too.
    """
    image = image.convert("RGBA")
    # The crops carry transparent padding: measure "the border" from the art.
    box = image.getchannel("A").point(lambda a: 255 if a >= 8 else 0).getbbox()
    if box:
        image = image.crop(box)
    px = image.load()
    strong = components(image.getchannel("A"), threshold=110)
    if not strong:
        return image
    biggest = max(len(p) for p, _ in strong)
    keep = set()
    for pixels, border in strong:
        if border and len(pixels) < biggest * 0.15:
            for x, y in pixels:
                px[x, y] = (0, 0, 0, 0)
        else:
            keep.update(pixels)
    for pixels, _ in components(image.getchannel("A"), threshold=8):
        if not any(p in keep for p in pixels):
            for x, y in pixels:
                px[x, y] = (0, 0, 0, 0)
    alpha = image.getchannel("A").point(lambda a: 0 if a < 8 else a)
    image.putalpha(alpha)
    box = image.getbbox()
    return image.crop(box) if box else image


def fill_part(image):
    """The glowing part of a partly full bar: up to where the fill ends."""
    w, h = image.size
    px = image.load()
    y = h // 2
    lit = [sum(px[x, y][:3]) for x in range(w)]
    peak = max(lit)
    # The fill ends where a dark run starts (the bright rim at the far right
    # end of the empty part doesn't count).
    run = 10
    end = w - 1
    for x in range(w // 10, w - run):
        if all(lit[x + i] < peak * 0.35 for i in range(run)):
            end = x
            break
    return image.crop((0, 0, min(w, end + 1), h))


def resolve(value, size):
    return value if value >= 0 else size + value


def load_items():
    items = []
    for name, rel in ICONS.items():
        image = Image.open(KIT / rel)
        if name in TRIM:
            left, top, right, bottom = TRIM[name]
            image = image.crop((left, top, image.width - right, image.height - bottom))
        image = clean(image)
        scale = ICON_SIZE / max(image.size)
        image = image.resize((max(1, round(image.width * scale)), max(1, round(image.height * scale))), Image.LANCZOS)
        items.append({"name": name, "image": image, "slice": None})
    for name, (rel, scale, cut, is_fill) in CHROME.items():
        image = clean(Image.open(KIT / rel))
        if is_fill:
            image = fill_part(image)
        w, h = image.size
        if cut[1] < 0 and cut[3] > 0 and abs(cut[1]) == cut[3]:
            # (-n, n) on an axis means "a band of 2n pixels around the middle".
            y0, y1 = h // 2 - cut[3], h // 2 + cut[3]
        else:
            y0, y1 = resolve(cut[1], h), resolve(cut[3], h)
        x0, x1 = resolve(cut[0], w), resolve(cut[2], w)
        image = image.resize((round(w * scale), round(h * scale)), Image.LANCZOS)
        sw, sh = image.size
        slice_ = (
            max(1, min(sw - 2, round(x0 * scale))),
            max(1, min(sh - 2, round(y0 * scale))),
            max(2, min(sw - 1, round(x1 * scale))),
            max(2, min(sh - 1, round(y1 * scale))),
        )
        items.append({"name": name, "image": image, "slice": slice_})
    return items


def pack(items):
    """Skyline packing, biggest first: each sprite drops into the lowest spot
    across the atlas that's wide enough."""
    items.sort(key=lambda i: (-i["image"].height * i["image"].width))
    skyline = [0] * ATLAS_WIDTH
    for item in items:
        w, h = item["image"].size
        w += PAD
        best_x, best_y = 0, None
        for x in range(0, ATLAS_WIDTH - w + 1, 2):
            y = max(skyline[x : x + w])
            if best_y is None or y < best_y:
                best_x, best_y = x, y
        item["x"], item["y"] = best_x + PAD, best_y + PAD
        for x in range(best_x, best_x + w):
            skyline[x] = best_y + h + PAD
    height = max(skyline) + PAD
    if height > ATLAS_MAX_HEIGHT:
        raise SystemExit(f"Atlas too tall ({height}px): lower ICON_SIZE or chrome scales")
    return height


def main():
    items = load_items()
    height = pack(items)
    atlas = Image.new("RGBA", (ATLAS_WIDTH, height), (0, 0, 0, 0))
    for item in items:
        atlas.alpha_composite(item["image"], (item["x"], item["y"]))
    OUT_IMAGE.parent.mkdir(parents=True, exist_ok=True)
    atlas.save(OUT_IMAGE, optimize=True)

    lines = [
        "--!strict",
        "-- GENERATED by tools/pack_ui_atlas.py from assets/grow_a_galaxy_ui_assets.",
        "-- Do not edit: change the script and run it again. Rects are pixels of",
        f"-- assets/ui/GaG_UI_Atlas.png ({ATLAS_WIDTH} x {height}); `slice` is a",
        "-- 9-slice sprite's stretchable centre, relative to its own rect.",
        "",
        "export type Rect = { x0: number, y0: number, x1: number, y1: number }",
        "export type SpriteDef = { x: number, y: number, w: number, h: number, slice: Rect? }",
        "",
        "local SPRITES: { [string]: SpriteDef } = {",
    ]
    for item in sorted(items, key=lambda i: i["name"]):
        w, h = item["image"].size
        cut = item["slice"]
        slice_text = (
            f", slice = {{ x0 = {cut[0]}, y0 = {cut[1]}, x1 = {cut[2]}, y1 = {cut[3]} }}" if cut else ""
        )
        lines.append(f"\t{item['name']} = {{ x = {item['x']}, y = {item['y']}, w = {w}, h = {h}{slice_text} }},")
    lines += [
        "}",
        "",
        "return {",
        f"\tWIDTH = {ATLAS_WIDTH},",
        f"\tHEIGHT = {height},",
        "\tSPRITES = SPRITES,",
        "}",
        "",
    ]
    OUT_LUAU.write_text("\n".join(lines), encoding="utf-8", newline="\n")
    # Format like the rest of the code, so `stylua --check` passes.
    stylua = shutil.which("stylua") or str(Path.home() / ".rokit" / "bin" / "stylua.exe")
    try:
        subprocess.run([stylua, str(OUT_LUAU)], cwd=ROOT, check=True)
    except (OSError, subprocess.CalledProcessError):
        print(f"StyLua not found: run `stylua {OUT_LUAU.relative_to(ROOT)}` before committing")
    print(f"Packed {len(items)} sprites into {ATLAS_WIDTH} x {height}: {OUT_IMAGE}")


if __name__ == "__main__":
    main()
