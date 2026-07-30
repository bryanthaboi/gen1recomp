# Build & install on your iPhone — step by step

This guide assumes **zero** programming experience. Follow it top to
bottom and you'll have the game running on your own iPhone in roughly an
hour (most of it is waiting for downloads).

## What you need

- A **Mac** (any Apple-silicon or recent Intel Mac on macOS 14 or newer)
- An **iPhone** and its **charging cable**
- A free **Apple ID** (the same account you use for the App Store)
- Your **own, legally obtained** Pokémon Red or Blue ROM file (a 1 MB
  `.gb` file). This project ships no game data — the app rebuilds
  everything from *your* cartridge dump and verifies it before use.
- About **15 GB free disk space** (Xcode is enormous; the game itself is
  tiny)

> **Free vs. paid Apple account:** a free Apple ID works. The only catch:
> apps signed with a free account stop launching after **7 days** — just
> re-run the install command (step 5) to re-sign; your save data is kept.
> A paid Apple Developer account ($99/yr) extends that to a year.

---

## Step 1 — Install Xcode (once)

1. On the Mac, open the **App Store**, search **Xcode**, click **Get**.
   It's a ~10 GB download — go make tea.
2. Open Xcode once. Accept the license. If it offers to install extra
   components or the **iOS platform**, say yes and let it finish.

## Step 2 — Sign Xcode into your Apple ID (once)

1. In Xcode's menu bar: **Xcode → Settings → Accounts**.
2. Click the **+** in the bottom-left → **Apple Account** → sign in.
3. Close the window. (This quietly creates the "signing certificate" the
   build uses — you never have to touch it again.)

## Step 3 — Get this project onto the Mac

If you received it as a folder, put it somewhere easy like your home
folder. If it's on GitHub, click the green **Code** button → **Download
ZIP**, then double-click the zip to unpack it.

## Step 4 — Build it (one command)

1. Open the **Terminal** app (press ⌘-space, type `terminal`, press
   return).
2. Type `cd ` (c, d, space — don't press return yet), then **drag the
   project folder** from Finder onto the Terminal window — it fills in
   the path — and press **return**.
3. Paste this and press return:

   ```sh
   scripts/build_ios.sh --fetch
   ```

   The first run downloads the LÖVE engine and compiles everything
   (5–15 minutes). Lines of build output scrolling by is normal. You're
   done when you see **`==> done`**.

## Step 5 — Put it on your iPhone

1. Plug the iPhone into the Mac with the cable. **Unlock it** and keep it
   unlocked. If it asks **"Trust This Computer?" → Trust**.
2. Paste this and press return:

   ```sh
   scripts/build_ios.sh --device --install
   ```

   The script finds your signing identity and your phone by itself. If it
   complains, it tells you exactly what to fix (usually: the phone was
   locked — unlock and re-run).

3. First time only, the iPhone will want two approvals:
   - **Developer Mode**: Settings → **Privacy & Security** → scroll to
     **Developer Mode** → turn on → restart the phone → confirm.
   - **Trust the developer**: Settings → **General** → **VPN & Device
     Management** → tap the entry under *Developer App* → **Trust**.

   Then re-run the command in step 5.2 if the install had failed.

## Step 6 — Give it your ROM and play

1. Get your `.gb` file onto the phone — AirDrop it to yourself, or save
   it in iCloud Drive / Files.
2. Open the app. On the **RED** tab, tap **Import ROM** and pick your
   `.gb` file in the file browser that appears. (Alternative: in the
   **Files** app, drop the `.gb` into **On My iPhone → the game's
   folder** and just reopen the app — it imports automatically.)
3. Import takes ~10 seconds, the button turns into **Play Red** — tap it.

## Optional goodies

- **Pokéwalker mode** (real steps → EXP): in-game **mod manager →
  POKEWALKER → SYNC STEPS on**, allow step access when iOS asks, and go
  for a walk.
- **Mods**: launcher → **MODS** tab → **Import mod .zip**.
- **Save import/export**: buttons on each game's tab, using the normal
  iOS file picker.

## When things go wrong

| Symptom | Fix |
|---|---|
| `xcodebuild not found` | Xcode isn't installed or wasn't opened once — do Step 1 |
| `no Apple signing identity found` | Do Step 2, then re-run |
| `no iPhone/iPad found` | Cable in? Phone unlocked? Tapped "Trust"? |
| Install fails with "locked" | Unlock the phone, keep it unlocked, re-run |
| App icon appears then won't open | Do the two approvals in Step 5.3 |
| App stops launching after a week | Free-account 7-day limit — re-run Step 5.2 |
| "That ROM could not be imported" | The file isn't a canonical 1 MB US Red/Blue dump — the importer checks its fingerprint |

Every build/install command is safe to re-run; your saves live on the
phone and survive reinstalls.
