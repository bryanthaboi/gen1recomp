#!/usr/bin/env python3
"""
Generates the Android adaptive launcher icon from assets/logo/gen1recomp_cover.png
and 3D cartridge shortcut assets for every density bucket
(mdpi, hdpi, xhdpi, xxhdpi, xxxhdpi).
"""

import os
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES_DIR = os.path.join(ROOT, "mobile", "android", "app", "src", "main", "res")
COVER = os.path.join(ROOT, "assets", "logo", "gen1recomp_cover.png")

DENSITIES = {
    "mdpi": {"shortcut": 48, "adaptive": 108},
    "hdpi": {"shortcut": 72, "adaptive": 162},
    "xhdpi": {"shortcut": 96, "adaptive": 216},
    "xxhdpi": {"shortcut": 144, "adaptive": 324},
    "xxxhdpi": {"shortcut": 192, "adaptive": 432},
}

SHELL_COLORS = {
    # Gen 1 (GB)
    "red": {"main": (230, 45, 55), "dark": (175, 25, 35), "light": (255, 90, 100), "shape": "gb"},
    "blue": {"main": (35, 125, 235), "dark": (20, 85, 175), "light": (80, 165, 255), "shape": "gb"},
    "yellow": {"main": (255, 205, 10), "dark": (210, 160, 0), "light": (255, 230, 80), "shape": "gb"},
    # Gen 2 (GBC)
    "gold": {"main": (225, 170, 40), "dark": (170, 120, 20), "light": (245, 200, 80), "shape": "gb"},
    "silver": {"main": (185, 190, 200), "dark": (130, 135, 145), "light": (225, 230, 240), "shape": "gb"},
    "crystal": {"main": (105, 195, 225), "dark": (60, 135, 165), "light": (180, 240, 255), "shape": "gb"},
    # Gen 3 (GBA)
    "firered": {"main": (235, 65, 35), "dark": (175, 30, 15), "light": (255, 115, 75), "shape": "gba"},
    "leafgreen": {"main": (40, 175, 80), "dark": (20, 120, 45), "light": (85, 215, 125), "shape": "gba"},
    "ruby": {"main": (195, 30, 50), "dark": (140, 15, 30), "light": (240, 75, 95), "shape": "gba"},
    "sapphire": {"main": (25, 70, 185), "dark": (15, 40, 135), "light": (70, 120, 240), "shape": "gba"},
    "emerald": {"main": (20, 155, 80), "dark": (10, 105, 50), "light": (65, 205, 125), "shape": "gba"},
}

def create_adaptive_foreground(size):
    """Full-bleed cover. The launcher mask crops the edges; the mark stays centered."""
    cover = Image.open(COVER).convert("RGBA")
    return cover.resize((size, size), Image.Resampling.LANCZOS)

def render_3d_cartridge(version, size):
    conf = SHELL_COLORS[version]
    shape = conf.get("shape", "gb")
    colors = conf
    S = size * 4
    
    # Transparent canvas so the cartridge sits directly on launcher's white circle plate
    canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    
    if shape == "gba":
        pad_x = int(S * 0.04)
        cw = S - pad_x * 2
        ch = int(cw * 0.64)
        pad_y = (S - ch) // 2
        
        # Soft drop shadow
        shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        sdraw = ImageDraw.Draw(shadow)
        sdraw.rounded_rectangle([pad_x + 6, pad_y + 12, pad_x + cw + 6, pad_y + ch + 12],
                               radius=int(S * 0.04), fill=(0, 0, 0, 95))
        shadow = shadow.filter(ImageFilter.GaussianBlur(int(S * 0.03)))
        canvas.paste(shadow, (0, 0), shadow)
        
        radius = int(S * 0.04)
        depth = int(S * 0.025)
        # 3D lower bevel
        draw.rounded_rectangle([pad_x, pad_y + depth, pad_x + cw, pad_y + ch + depth],
                              radius=radius, fill=colors["dark"])
        # Main shell
        draw.rounded_rectangle([pad_x, pad_y, pad_x + cw, pad_y + ch],
                              radius=radius, fill=colors["main"])
        
        # Top ridge
        top_lip_h = int(ch * 0.12)
        draw.rounded_rectangle([pad_x + 4, pad_y + 2, pad_x + cw - 4, pad_y + top_lip_h],
                              radius=int(radius * 0.5), fill=colors["light"])
        draw.rounded_rectangle([pad_x + 6, pad_y + 4, pad_x + cw - 6, pad_y + top_lip_h - 1],
                              radius=int(radius * 0.4), fill=colors["main"])
        
        # Label area (landscape aspect ratio ~ 2:1)
        label_margin_x = int(cw * 0.08)
        label_top_y = pad_y + int(ch * 0.20)
        label_w = cw - label_margin_x * 2
        label_h = int(ch * 0.70)
        label_x = pad_x + label_margin_x
        
        # Label border/recess
        draw.rounded_rectangle([label_x - 2, label_top_y - 2, label_x + label_w + 2, label_top_y + label_h + 2],
                              radius=int(radius * 0.5), fill=colors["dark"])
        
        label_path = os.path.join(ROOT, "assets", "labels", f"{version}.png")
        if os.path.exists(label_path):
            label_img = Image.open(label_path).convert("RGBA")
            label_img = label_img.resize((label_w, label_h), Image.Resampling.LANCZOS)
            
            mask = Image.new("L", (label_w, label_h), 0)
            mdraw = ImageDraw.Draw(mask)
            mdraw.rounded_rectangle([0, 0, label_w, label_h], radius=int(radius * 0.4), fill=255)
            
            canvas.paste(label_img, (label_x, label_top_y), mask)
        else:
            draw.rounded_rectangle([label_x, label_top_y, label_x + label_w, label_top_y + label_h],
                                  radius=int(radius * 0.4), fill=(240, 240, 240, 255))
        
        # Outer highlight
        draw.rounded_rectangle([pad_x, pad_y, pad_x + cw, pad_y + ch],
                              radius=radius, outline=colors["light"], width=max(2, int(S * 0.008)))
    else:
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
        
        for ver in SHELL_COLORS:
            cart = render_3d_cartridge(ver, sizes["shortcut"])
            cart.save(os.path.join(drawable_dir, f"ic_shortcut_{ver}.png"), "PNG")
        
        print(f"Generated assets for drawable-{density}")

if __name__ == "__main__":
    main()
