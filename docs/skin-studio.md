# Touch skins and the Skin Studio

A **skin** replaces the on-screen controls wholesale: a bezel image, a
control layout, and the rectangle the Game Boy screen is drawn into. Engine:
`src/core/TouchSkin.lua` (model, parsers, zip export), `src/core/TouchControls.lua`
(draw and input), `src/render/Renderer.lua` (the screen viewport),
`src/core/DeltaSkin.lua` (Delta `.deltaskin` import and export),
`src/ui/SkinStudio.lua` (the desktop editor). Tests:
`tests/engine/touch_skin_test.lua`, `tests/engine/skin_studio_test.lua`,
`tests/engine/skin_studio_ux.lua`,
`tests/engine/skin_studio_image_import.lua`,
`tests/engine/skin_format_import_test.lua`,
`tests/engine/launcher_skins_tab.lua`,
`tests/engine/launcher_skins_ux.lua`.

Skins are picked in the launcher's **Skins** tab, which also imports them and
opens the studio. `options.touchControls.skin` holds the folder name.

## Formats

Three load: the native `skin.lua`, a RetroArch overlay `.cfg`, and a Delta
`.deltaskin`. `skin.lua` wins when a folder has more than one. The launcher
badges each installed skin with the format it was read from.

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

The area desc types are expanded rather than ignored: `dpad_area`,
`abxy_area`, `analog_left` and `analog_right` each become eight hitboxes over
the same area, one per 45 degree sector measured from its centre, the way
RetroArch resolves them: there is no neutral middle, and the four corner
sectors fire two inputs. Any `_up` / `_down` / `_left` / `_right` override and
the per-side reach are honoured, and the desc's own art is kept as decoration
over the top. Exporting a cfg folds the eight back into the one area desc they
came from. `retrok_<key>` is a keyboard bind.

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

**Delta `.deltaskin`.** A zip (any wrapping folder is stripped) holding an
`info.json` plus its art. The `representations` tree is walked
device / display type / orientation, and every orientation that exists becomes
a page; `page.orient` is the orientation key, so a portrait/landscape pair
auto-rotates like a RetroArch one. Item `frame` rects are top-left plus size in
`mappingSize` points and are converted to the native centre plus half extent;
`extendedEdges` merge per key into the reach fields; `mask: "circle"` becomes a
radial hitbox. A `dpad` or `thumbstick` item expands into the 3x3 grid, so the
corners fire two directions. `screens[1].outputFrame` (or the legacy
`gameScreenFrame`) becomes the screen cutout. A portrait page with neither
keeps `mappingSize` as the overlay aspect, sits at the bottom of the
window, and puts the Game Boy picture in the leftover space above -- the
usual GBA4iOS controller-deck layout. Pages that name a screen rect still
stretch to the window the way Delta does. Host functions map to
engine hotkeys: `menu` to `menu_toggle`, `fastForward` to
`hold_fast_forward`, `toggleFastForward` to `toggle_fast_forward`;
`quickSave` and `quickLoad` have nothing to bind to and drop to decoration.
Both `com.rileytestut.delta.game.*` and Manic's `public.aoshuang.game.*`
identifiers are accepted, and a non Game Boy system warns instead of failing.

PDF artwork is usually a JPEG wrapped so iOS can scale it (Delta's
Image-to-PDF skins, Preview exports, and the like). Import extracts that
JPEG and draws it; a true vector PDF with no embedded image is still refused,
with a message asking for a PNG version. GBA4iOS `.gbcskin` / `.gbaskin` files
are an older, incompatible schema and are refused by name.

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

Four roads, all of them landing in `skins/` in the save directory:

* **Import** on the Skins tab opens the host file picker for a `.zip` or a
  `.deltaskin`.
* **Paste a skin link** in the tab's URL row, then **Add**. The download runs
  on the fetch pool (`src/net/Fetch.lua`), so the launcher stays live, and the
  row shows a spinner until it lands. A link to a bare `overlay.cfg` is wrapped
  into an archive on the way in. This is the road that works on a phone, where
  there is no file picker to speak of.
* Drop a `.zip` or `.deltaskin` on the launcher window while the Skins tab is
  open.
* Copy a folder or archive into `skins/` by hand.

An archive is mounted in place, so there is nothing to unpack. It needs one
`skin.lua`, `.cfg` (`overlay.cfg` is preferred when there are several) or
`info.json`, plus the images it names.

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
resize. Arrow keys nudge the selection one canvas pixel, shift-arrow ten. While
a control is dragged it snaps to the centres and edges of the other controls
and of the page itself when it comes within a few pixels, and the guide it
snapped to is drawn. X / Y / W / H are in canvas pixels, so a control can be
typed to the coordinate its art was drawn at. **Back** and **Front** move the
selection through the draw order. Bind, hitbox shape, hit reach and idle and
pressed images are per control; the bezel, the pages and the screen cutout are
per page. The cutout is itself a draggable element with a 10:9 lock.

**Bind** opens a grid of every bind the engine understands: the eight Game Boy
buttons, the diagonal pairs, every hotkey, a few `key:` entries, and
decoration. The COMBINE chips at the top toggle one part at a time, which is
how a pipe bind like `left|down` is built without typing it.

**Undo** and **Redo** in the top bar cover every edit (ctrl+Z / ctrl+Y, or
`u` / shift+`u` without a keyboard modifier). The stack holds the last 50
actions. `L` toggles the bind captions drawn on the canvas.

Each page can **Lock** to portrait or landscape. With **Match canvas** on
(the default), the page list picks a matching mock device and the canvas preset
picks a matching page. Turn Match canvas off to look at a portrait page on a
landscape device. **Pages** opens the page list, where a page is selected,
renamed or deleted.

Starting a new skin, opening another one or closing the studio with unsaved
edits prompts first, with Save first / Discard / Cancel.

A RetroArch overlay whose pages are already named portrait / landscape
(the auto-rotate convention) locks those pages and turns Match canvas on
when you open it. You do not have to click Lock first.

**Art.** The **Bezel**, **Idle art** and **Pressed art** rows open a
thumbnail grid of the images already in the skin folder, with `(none)` first;
the **Import** button there and beside each row opens the host file picker (`src/core/FilePicker.lua`: osascript, PowerShell,
zenity/kdialog) and copies the chosen PNG or JPG into `img/` under the name in
the SKIN field, then assigns it to that slot. Dropping a PNG or JPG on the
window does the same for whichever slot was last touched. A new bezel does not
move the screen cutout: press **Detect screen from bezel** to measure it out of
the art's alpha.

**Testing.** **Test** makes the canvas live: clicking presses real Game Boy
buttons and the footer reports what is held. **Play** saves the skin, selects
it, and boots the game with it.

**Saving.** **Save** writes `skins/<name>/skin.lua` and copies every image the
skin names, so the folder stands alone. **Export** offers three formats, and
the Skins tab's gear offers the same three for any installed skin:

| Export | Contents |
| --- | --- |
| gen1recomp `.zip` | the native `skin.lua`, the images, and the original `.cfg` when it came from one |
| RetroArch `.zip` | an `overlay.cfg` generated from the model, plus the images |
| Delta `.deltaskin` | an `info.json` generated from the model, plus the images |

All three are written store-only (`src/core/SkinZip.lua`) into `skins/_export/`
in the save directory, which is outside the folder the skin list scans, so an
export can never shadow the skin it came from. The notice names the full path
so a phone can find the file in its own file manager. On desktop **Show the
exported file** opens that folder.

## Not implemented

True vector Delta skins (PDF artwork with no embedded JPEG). Those still need
a PDF renderer this engine does not carry, so they are refused with a message
rather than imported half-drawn. PDF files that wrap a JPEG, the usual Delta
skin case, extract on import.
