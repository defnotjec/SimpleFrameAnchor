# SimpleFrameAnchor

A tiny World of Warcraft addon that anchors the **Player**, **Target**, and **Cooldown Manager** frames to each other.

Its main trick: anchor the Player and Target frames to the edges of the Cooldown Manager so that **when the Cooldown Manager grows (adds icons and spreads out from its centre), the Player and Target frames are pushed outward with it** — automatically, and always aligned. No polling, no CPU cost.

## Features

- Anchor the **Player Frame**, **Target Frame**, and **Cooldown Manager** to each other or to the screen.
- Pick each frame's **anchor point** and the **target's anchor point** from all nine points (Top / Bottom / Left / Right / corners / Center), plus X/Y offsets.
- **Flank preset** (the shipped default): Player hugs the left edge of the Cooldown Manager, Target hugs the right, both vertically centred — so they slide outward as the bar grows.
- **Reset** per-frame or all frames to defaults.
- Clean, dark, DCT-style config window.

## Usage

- `/sfa` or `/simpleframeanchor` — open/close the config window
- `/sfa preset` — apply the flank preset
- `/sfa reset` — reset all frames to defaults

## How it works (and the safe bits)

WoW keeps `SetPoint` relationships live: once the Player frame's **RIGHT** edge is anchored to the Cooldown Manager's **LEFT** edge, the Player frame follows that edge as the bar resizes. The Target frame mirrors it on the right. That's the whole "push outward" behaviour — it's free.

Because Blizzard unit frames and the Cooldown Viewer are governed by **Edit Mode**, SimpleFrameAnchor:

- only repositions frames **out of combat** (changes made in combat apply the instant combat ends);
- re-applies its anchors on login, zone-in, Edit Mode layout changes, and when you exit Edit Mode;
- captures each frame's original anchor once, so turning management **off** hands the frame back to Edit Mode.

## Notes / caveats

- "Cooldown Manager" here means Blizzard's **Essential** Cooldown Viewer (`EssentialCooldownViewer`). The **Anchor to** dropdown also lets you target the Utility and Buff viewers.
- If a Cooldown Manager bar is set to **hide when inactive**, frames anchored to it can drift when it hides. Keep the bar always shown for a steady layout.
- Moving the Cooldown Manager *itself* is off by default (Edit Mode owns it); enable it in the **Cooldown Manager** section if you want SimpleFrameAnchor to place it.

## Installation

Copy the `SimpleFrameAnchor` folder into `World of Warcraft/_retail_/Interface/AddOns/` (or your client's equivalent) and reload.

## License

[MIT](LICENSE)
