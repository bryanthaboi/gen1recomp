# Touch skins and the Skin Studio

A **skin** replaces the on-screen controls wholesale: a bezel image, a
control layout, and the rectangle the Game Boy screen is drawn into. Engine:
`src/core/TouchSkin.lua` (model, parsers, zip export), `src/core/TouchControls.lua`
(draw and input), `src/render/Renderer.lua` (the screen viewport),
`src/ui/SkinStudio.lua` (the desktop editor). Tests:
`tests/engine/touch_skin_test.lua`, `tests/engine/skin_studio_test.lua`,
`tests/engine/skin_studio_image_import.lua`,
`tests/engine/launcher_skins_tab.lua`.

Skins are picked in the launcher's **Skins** tab, which also imports them and
opens the studio. `options.touchControls.skin` holds the folder name.

## Formats

Two load. `skin.lua` wins when a folder has both.

**RetroArch overlay `.cfg`.** The libretro `common-overlays` collection loads
as-is. Supported keys:

| Key | Meaning |
| --- | --- |
| `overlays` | page count |
| `overlayN_name` | page name, the target of `next_target` |
| `overlayN_overlay` | bezel image |
| `overlayN_full_screen` | stretch the page to the window |
| `overlayN_rect` | page placement, default `0,0,1,1` |
| `overlayN_aspect_ratio` | design aspect; the overlay letterboxes to it even when full screen |
| `overlayN_range_mod`, `overlayN_alpha_mod` | desc defaults |
| `overlayN_viewport` | `x,y,w,h`, the screen cutout |
| `overlayN_viewport_fill` | parsed; the engine always fits, see below |
| `overlayN_descM` | `binds,x,y,shape,range_x,range_y` |
| `overlayN_descM_overlay` | control art |
| `overlayN_descM_next_target` | page to switch to |
| `overlayN_descM_range_mod`, `_alpha_mod` | per-control overrides |
| `overlayN_descM_reach_x/_y/_up/_down/_left/_right` | hitbox reach |

`x,y` is the centre and `range_x,range_y` are half extents, both normalized.
Hitboxes are `radial` or `rect`. Pipe-separated binds (`left|down`) are one
control that holds both. A `nul` desc is decoration: it draws and never
captures a touch.

Alpha follows RetroArch (`input_driver.c`, `input_overlay_post_poll`): every
image sits at the overlay opacity, and a pressed control's image swaps to
`opacity * alpha_mod`. So `alpha_mod` above 1 lights a control up and below 1
fades it out, and both directions read as a press animation.

**Native `skin.lua`.** This module's own model written back out: one Lua
table, no flat key space, and a separate `imagePressed` per control that a
`.cfg` cannot express. Loaded with an empty environment, so a skin authored by
a stranger cannot reach `love` or `io`. Sizes here are full width and height
rather than RetroArch's half extents, because that is what an editor's numeric
fields mean.

```lua
return {
  name = "my_skin",
  pages = {
    {
      name = "main",
      image = "img/bezel.png",
      fullScreen = true,
      viewport = { x = 0.0, y = 0.0, w = 1.0, h = 0.5, fill = false },
      controls = {
        { bind = "a", x = 0.87, y = 0.72, w = 0.18, h = 0.10,
          shape = "radial", image = "img/a.png", imagePressed = "img/a_down.png" },
      },
    },
  },
}
```

## Bindable actions

The eight Game Boy buttons: `a`, `b`, `start`, `select`, `up`, `down`,
`left`, `right`.

Engine hotkeys, handled in `Game:touchSkinHotkey`:

| Bind | Effect |
| --- | --- |
| `overlay_next`, `overlay_previous` | switch page, honouring `next_target` |
| `hold_fast_forward`, `fast_forward` | fast forward while held |
| `toggle_fast_forward` | step the speed option |
| `reset` | soft reset to the title |
| `menu_toggle` | open OPTIONS |

`screenshot`, `pause_toggle` and `exit_emulator` are recognised but have no
handler yet: a control bound to them draws and does nothing. Anything else,
`rewind` included, is not in the bind table at all, so the control falls back
to decoration and never captures a touch.

As an extension to the format, `key:<name>` presses any keyboard key, which is
how a skin button reaches a mod hotkey.

## The screen viewport

`overlayN_viewport` is the cutout the picture is fitted into. The Game Boy
screen keeps its whole-pixel scale and letterboxes inside that rect rather than
stretching to it, so a bezel gets an exact 160x144 picture; `viewport_fill` is
parsed but does not stretch. `overlayN_viewport_expand = true` is an extension
that lets a widescreen bezel take the filling survey-zoom world view instead.

A viewport also implies the faithful-ratio lock. Without it the world pass
expands to fill the cutout and you get more map instead of a Game Boy screen.

Border art often ships with a transparent hole and no `viewport` key. **Detect
screen from bezel** in the studio measures the hole out of the art's alpha
channel and writes the rect.

## Bezels versus pads

A skin whose active page binds nothing is a frame rather than a pad: a TV
surround, a handheld shell, a Super Game Boy border. Those draw on **desktop**
as well, where the touch overlay itself does not, and a gamepad does not hide
them. Anything that binds a button still follows the usual mobile /
`POKEPORT_TOUCH` rule.

## Installing

Drop a folder or a `.zip` into `skins/` in the save directory, or drop a zip on
the launcher window while the Skins tab is open. A zip is mounted in place, so
there is nothing to unpack. The folder needs one `skin.lua` or `.cfg`
(`overlay.cfg` is preferred when there are several) and the images it names.

Two ship bundled, both from libretro's `common-overlays` under CC-BY-4.0:

| Skin | Source | Shape |
| --- | --- | --- |
| `gb_anim` | `gamepads/gb_anim_portrait` | handheld shell, working buttons, two pages |
| `tv_crt` | `borders/tv-integer` | CRT television frame, no buttons |

Attribution lives in each folder's `README.md`. `tv_crt` is a photograph of a
real television: CC-BY-4.0 upstream, but treat it as a test asset rather than
shipping branding.

## The studio

Launcher, Skins tab, **Open Skin Studio**, or the gear on any skin row to open
that skin. Desktop only: the launcher does not offer it on Android or iOS,
because it wants a mouse, typed coordinates and room for an inspector.

**Canvas.** A mock device at a chosen preset, so a phone skin is authored at
phone proportions on a desktop monitor.

| Preset | Size |
| --- | --- |
| Phone portrait / landscape | 1080x1920, 1920x1080 |
| Tablet portrait / landscape | 1536x2048, 2048x1536 |
| Steam Deck | 1280x800 |
| Desktop 1080p | 1920x1080 |
| Ultrawide 21:9 | 2560x1080 |
| Super Game Boy border | 256x224 |

The Super Game Boy preset locks the viewport to the real screen window,
160x144 at (48,40), so an SGB border cannot be drawn out of register.

**Editing.** Click a control to select it, drag to move, eight handles to
resize. X / Y / W / H are in canvas pixels, so a control can be typed to the
coordinate its art was drawn at. Bind, hitbox shape, hit reach and idle and
pressed images are per control; the bezel, the pages and the screen cutout are
per page. The cutout is itself a draggable element with a 10:9 lock.

Each page can **Lock** to portrait or landscape. With **Match canvas** on
(the default), Next page picks a matching mock device and the canvas preset
picks a matching page. Turn Match canvas off to look at a portrait page on a
landscape device.

A RetroArch overlay whose pages are already named portrait / landscape
(the auto-rotate convention) locks those pages and turns Match canvas on
when you open it. You do not have to click Lock first.

**Art.** The **Bezel**, **Idle art** and **Pressed art** rows cycle through the
images already in the skin folder; the **Import** button beside each one opens
the host file picker (`src/core/FilePicker.lua`: osascript, PowerShell,
zenity/kdialog) and copies the chosen PNG or JPG into `img/` under the name in
the SKIN field, then assigns it to that slot. Dropping a PNG or JPG on the
window does the same for whichever slot was last touched. A new bezel does not
move the screen cutout: press **Detect screen from bezel** to measure it out of
the art's alpha.

**Testing.** **Test** makes the canvas live: clicking presses real Game Boy
buttons and the footer reports what is held. **Play** saves the skin, selects
it, and boots the game with it.

**Saving.** **Save** writes `skins/<name>/skin.lua` and copies every image the
skin names, so the folder stands alone. **Export** packs it as one zip
(`src/core/SkinZip.lua`, store-only) carrying the native `skin.lua`, the
images, and the original `.cfg` when it came from one. An exported skin drops
straight back into `skins/` and still opens in RetroArch.

## Not implemented

RetroArch's `analog_*`, `dpad_area`, `abxy_area` and `retrok_*` desc types.
