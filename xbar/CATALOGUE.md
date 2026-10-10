# Submitting to the xbar plugin catalogue

Do this only when Flying Tulip has agreed to publish the plugin. The plugin is laid out to be copied as is.

What the catalogue ([matryer/xbar-plugins](https://github.com/matryer/xbar-plugins), CONTRIBUTING.md and `.test.py`)
requires, and where this plugin stands:

| requirement | status |
|---|---|
| refresh time in the file name (`{name}.{time}.{ext}`) | `flyingtulip.1m.sh` |
| executable file | yes (git mode 755) |
| shebang that CI accepts for the extension (`.sh`: bash, ksh, zsh, sh, fish) | `#!/usr/bin/env bash` |
| passes the language linter (`.sh`: shellcheck) | clean with the exclusions CI uses |
| required metadata: `xbar.title`, `xbar.author`, `xbar.author.github` | present |
| recommended metadata: `xbar.desc`, `xbar.version`, `xbar.image`, `xbar.dependencies`, `xbar.abouturl` | all but `xbar.image` |
| variables as `xbar.var` | six, in the plugin settings window |
| category folder | `Cryptocurrency/` (own sub-folder `FlyingTulip/`, like `Cryptocurrency/Bitcoin/`) |

Why a `.sh` and not `.js`: CI only accepts a `node` shebang for `.js`, and Node is not on stock macOS. The bash
file embeds the JXA logic and runs it with `/usr/bin/osascript`.

## Steps

1. On a Mac, install the plugin and take a screenshot of the dropdown (PNG, with a wallet that is not a real person's;
   use the `0x000000000000000000000000000000000000dEaD` example or a market-only view).
2. Fork `matryer/xbar-plugins` and create a branch.
3. Copy `xbar/Cryptocurrency/FlyingTulip/` into the fork's `Cryptocurrency/`. Add the screenshot there as
   `flyingtulip.png` and add this line to the metadata header (the URL only resolves after the merge, CI only warns):

       #  <xbar.image>https://raw.githubusercontent.com/matryer/xbar-plugins/main/Cryptocurrency/FlyingTulip/flyingtulip.png</xbar.image>

4. Keep the executable bit: `git update-index --chmod=+x Cryptocurrency/FlyingTulip/flyingtulip.1m.sh`.
5. Run the catalogue's checks locally (needs `shellcheck`): `python3 .test.py -vw` from the fork root.
6. Open the pull request with a short description: what it shows, public API only, no keys, optional wallet, tested in
   xbar and SwiftBar. Plugins are served on https://xbarapp.com once merged.
7. Afterwards, keep the catalogue copy in sync with this repository when the plugin changes (the catalogue has no
   release mechanism: update by pull request).
