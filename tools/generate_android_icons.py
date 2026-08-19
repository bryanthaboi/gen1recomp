#!/usr/bin/env python3
"""
Generates Android Adaptive Icon (based on cleaned love.png Pokéball + Gen1Recomp emblem)
and 3D Cartridge Shortcut assets for all density buckets (mdpi, hdpi, xhdpi, xxhdpi, xxxhdpi).
"""

import os
from collections import deque
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES_DIR = os.path.join(ROOT, "mobile", "android", "app", "src", "main", "res")

DENSITIES = {
    "mdpi": {"shortcut": 48, "adaptive": 108},
    "hdpi": {"shortcut": 72, "adaptive": 162},
    "xhdpi": {"shortcut": 96, "adaptive": 216},
    "xxhdpi": {"shortcut": 144, "adaptive": 324},
    "xxxhdpi": {"shortcut": 192, "adaptive": 432},
}

SHELL_COLORS = {
    "red": {"main": (230, 45, 55), "dark": (175, 25, 35), "light": (255, 90, 100)},
    "blue": {"main": (35, 125, 235), "dark": (20, 85, 175), "light": (80, 165, 255)},
    "yellow": {"main": (255, 205, 10), "dark": (210, 160, 0), "light": (255, 230, 80)},
    "gold": {"main": (225, 170, 40), "dark": (170, 120, 20), "light": (245, 200, 80)},
}

def extract_cleaned_love_emblem():
    """Extracts the Pokéball/Gen1Recomp emblem from love.png with transparent bg and deepened blacks."""
    src_path = os.path.join(RES_DIR, "drawable-xxxhdpi", "love.png")
    if not os.path.exists(src_path):
        src_path = os.path.join(RES_DIR, "drawable-xxhdpi", "love.png")
    src = Image.open(src_path).convert("RGBA")
    arr = np.array(src, dtype=np.uint8)
    h, w = arr.shape[:2]
    
    visited = np.zeros((h, w), dtype=bool)
    bg_mask = np.zeros((h, w), dtype=bool)

    queue = deque()
    for x in range(w):
        queue.append((0, x)); queue.append((h-1, x))
    for y in range(h):
        queue.append((y, 0)); queue.append((y, w-1))

    bg_ref = np.array([255, 237, 254], dtype=float)
    while queue:
        y, x = queue.popleft()
        if visited[y, x]: continue
        visited[y, x] = True
        color = arr[y, x, :3].astype(float)
        if np.max(np.abs(color - bg_ref)) < 28:
            bg_mask[y, x] = True
            for dy, dx in [(-1,0), (1,0), (0,-1), (0,1)]:
                ny, nx = y + dy, x + dx
                if 0 <= ny < h and 0 <= nx < w and not visited[ny, nx]:
                    queue.append((ny, nx))

    out_arr = arr.copy().astype(float)
    out_arr[bg_mask, 3] = 0

    # Deepen the soft blacks/outlines for crispness:
    fg_mask = ~bg_mask
    rgb = out_arr[fg_mask, :3]
    lum = 0.299 * rgb[:, 0] + 0.587 * rgb[:, 1] + 0.114 * rgb[:, 2]

    for i in range(len(rgb)):
        l = lum[i]
        if l < 110:
            factor = (l / 110.0) ** 1.8
            rgb[i, 0] = max(0, rgb[i, 0] * factor * 0.7)
            rgb[i, 1] = max(0, rgb[i, 1] * factor * 0.7)
            rgb[i, 2] = max(0, rgb[i, 2] * factor * 0.8)

    out_arr[fg_mask, :3] = np.clip(rgb, 0, 255)
    return Image.fromarray(out_arr.astype(np.uint8))

CLEANED_EMBLEM = extract_cleaned_love_emblem()

def create_adaptive_foreground(size):
    emblem = CLEANED_EMBLEM.copy()
    target_size = int(size * 0.78)
    emblem.thumbnail((target_size, target_size), Image.Resampling.LANCZOS)
    
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    x = (size - emblem.width) // 2
    y = (size - emblem.height) // 2
    canvas.paste(emblem, (x, y), emblem)
    return canvas

def create_adaptive_monochrome(size):
    fg = create_adaptive_foreground(size)
    arr = np.array(fg, dtype=float)
    lum = 0.299 * arr[:, :, 0] + 0.587 * arr[:, :, 1] + 0.114 * arr[:, :, 2]
    alpha = arr[:, :, 3]
    
    mono_alpha = np.zeros_like(alpha)
    valid = alpha > 20
    mono_alpha[valid & (lum > 70)] = 255
    mono_alpha[valid & (lum <= 70)] = 0
    
    mono_img = np.zeros((size, size, 4), dtype=np.uint8)
    mono_img[:, :, 0] = 255
    mono_img[:, :, 1] = 255
    mono_img[:, :, 2] = 255
    mono_img[:, :, 3] = mono_alpha.astype(np.uint8)
    
    return Image.fromarray(mono_img)

def render_3d_cartridge(version, size):
    colors = SHELL_COLORS[version]
    S = size * 4
    
    # Transparent canvas so the cartridge sits directly on launcher's white circle plate
    canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    
    # Tight padding to maximize cartridge size
    pad_x = int(S * 0.05)
    pad_y = int(S * 0.03)
    cw = S - pad_x * 2
    ch = S - pad_y * 2
    
    # Soft drop shadow
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    sdraw = ImageDraw.Draw(shadow)
    sdraw.rounded_rectangle([pad_x + 8, pad_y + 14, pad_x + cw + 8, pad_y + ch + 14],
                           radius=int(S * 0.05), fill=(0, 0, 0, 90))
    shadow = shadow.filter(ImageFilter.GaussianBlur(int(S * 0.03)))
    canvas.paste(shadow, (0, 0), shadow)
    
    radius = int(S * 0.045)
    depth = int(S * 0.03)
    draw.rounded_rectangle([pad_x, pad_y + depth, pad_x + cw, pad_y + ch + depth],
                          radius=radius, fill=colors["dark"])
    draw.rounded_rectangle([pad_x, pad_y, pad_x + cw, pad_y + ch],
                          radius=radius, fill=colors["main"])
    
    notch_w = int(cw * 0.65)
    notch_h = int(ch * 0.07)
    notch_x = pad_x + (cw - notch_w) // 2
    notch_y = pad_y + int(ch * 0.035)
    draw.rounded_rectangle([notch_x, notch_y, notch_x + notch_w, notch_y + notch_h],
                          radius=int(notch_h * 0.4), fill=colors["dark"])
    draw.rounded_rectangle([notch_x, notch_y - 2, notch_x + notch_w, notch_y + notch_h - 2],
                          radius=int(notch_h * 0.4), fill=colors["light"])
    
    label_margin_x = int(cw * 0.09)
    label_top_y = pad_y + int(ch * 0.20)
    label_w = cw - label_margin_x * 2
    label_h = int(ch * 0.70)
    label_x = pad_x + label_margin_x
    
    draw.rounded_rectangle([label_x - 3, label_top_y - 3, label_x + label_w + 3, label_top_y + label_h + 3],
                          radius=int(radius * 0.7), fill=colors["dark"])
    
    label_path = os.path.join(ROOT, "assets", "labels", f"{version}.png")
    if os.path.exists(label_path):
        label_img = Image.open(label_path).convert("RGBA")
        label_img = label_img.resize((label_w, label_h), Image.Resampling.LANCZOS)
        
        mask = Image.new("L", (label_w, label_h), 0)
        mdraw = ImageDraw.Draw(mask)
        mdraw.rounded_rectangle([0, 0, label_w, label_h], radius=int(radius * 0.5), fill=255)
        
        canvas.paste(label_img, (label_x, label_top_y), mask)
    else:
        draw.rounded_rectangle([label_x, label_top_y, label_x + label_w, label_top_y + label_h],
                              radius=int(radius * 0.5), fill=(240, 240, 240, 255))
    
    draw.rounded_rectangle([pad_x, pad_y, pad_x + cw, pad_y + ch],
                          radius=radius, outline=colors["light"], width=max(2, int(S * 0.008)))
    
    return canvas.resize((size, size), Image.Resampling.LANCZOS)

def main():
    os.makedirs(os.path.join(RES_DIR, "values"), exist_ok=True)
    os.makedirs(os.path.join(RES_DIR, "mipmap-anydpi-v26"), exist_ok=True)
    
    for density, sizes in DENSITIES.items():
        drawable_dir = os.path.join(RES_DIR, f"drawable-{density}")
        os.makedirs(drawable_dir, exist_ok=True)
        
        fg = create_adaptive_foreground(sizes["adaptive"])
        fg.save(os.path.join(drawable_dir, "ic_launcher_foreground.png"), "PNG")
        
        for ver in ("red", "blue", "yellow", "gold"):
            cart = render_3d_cartridge(ver, sizes["shortcut"])
            cart.save(os.path.join(drawable_dir, f"ic_shortcut_{ver}.png"), "PNG")
        
        print(f"Generated assets for drawable-{density}")

if __name__ == "__main__":
    main()
