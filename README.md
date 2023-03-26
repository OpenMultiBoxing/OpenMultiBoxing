![CI](https://github.com/OpenMultiBoxing/OpenMultiBoxing/workflows/CI/badge.svg)
# OpenMultiBoxing
<img src="https://OpenMultiBoxing.org/sshot5_2.png" alt="OMB 5.2 Screenshot" align="right">

Open source software for MultiBoxing any game or app. This is the continuation of [WowOpenBox](https://wowopenbox.org/).

Since version 2.0 you can also manage the windows of any Windows10 application or game (Eve online, Path of Exile, Browser Games, etc... under the "OpenMultiBoxing" moniker but this is the same code that started for just Wow and now works for both/all)

Web home: https://OpenMultiBoxing.org/

Github home: https://github.com/OpenMultiBoxing/OpenMultiBoxing#OpenMultiBoxing

The source for the [binary distribution](https://github.com/OpenMultiBoxing/OpenMultiBoxing/releases) (and the round robin wrapper) is built from https://github.com/OpenMultiBoxing/BuildKit (just mentioning that if you're curious, you don't need to look there to **use** OpenMultiBoxing)

## Main features

- Window Layout wizard and manual tweaking; get your game windows exactly how you want them to be to play.
- Instant swapping of windows; with keyboard hotkeys for fast switching to the next or any specific window.
- Left and right mouse click broadcasting option (press W or both buttons or hold them for more than half a second to avoid broadcasting)
- Secure text (password) broadcasting option (can also broadcast slash commands, etc)
- Many additional options to switch which window your keys are going to:
  - Swap windows with hotkeys.
  - Focus follow mouse: turns on/off the Windows&trade; accessibility feature so you just hover a window to make it receive keys (note that mouse click broadcast only works if focus follow mouse is off, which )
  - Focus next/previous/specific windows with hotkeys.
  - Optional simple **key broadcasting**: press configurable keys, they are sent to next window automatically.
- Free, OpenSource and the Safest option available.
- Online [help](https://OpenMultiBoxing.org/help), menus and tooltips on most UI element to help discovering features.

Note: key broadcasting replaces round robin in latest version of OpenMultiBoxing (WowOpenBox still only has optional Round Robin and no possibility of broadcasting, per Blizzard's multiboxing changes). Not all the help/doc/screenshots have been updated, use version 6 or below for RoundRobin instead of broadcasting.

## Installation

OpenMultiBoxing is optimized for Microsoft Windows 10 or newer (works great with Windows 11).

New since version 2.2 we made a compact all in one .exe binary distribution. Just grab the latest binary Zip file (e.g `OpenMultiBoxing-vX.Y.Z.zip`, not the source zip) and extract all to your desktop for instance. The binaries are built automatically by the Github CI and can be found on the [releases page](https://github.com/OpenMultiBoxing/OpenMultiBoxing/releases).

Go through the Window Layout Wizard to pick how many game windows you plan on playing with and their layout, save and apply.

Then start your game windows (e.g World of Warcraft) using battle.net launcher is fine/best (that way you don't need to keep typing your password). OMB since version 4.1 will automatically capture and place the windows in their respective position for you (you can turn that option off in the Option menu)

See the various `.bat` files for example of launching game windows automatically.

![OMB Window Layout GUI Screenshot](https://wowopenbox.org/sshotWindowLayout.png?src=github)

Also checkout our [FAQ](https://github.com/OpenMultiBoxing/OpenMultiBoxing/wiki/FAQ)
