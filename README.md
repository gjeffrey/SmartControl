# SmartControl

SmartControl is a native macOS GUI for `smartctl`. It discovers physical disks with Disk Utility, reads SMART data through `smartctl --json`, and turns that low-level output into clear health summaries, metrics, recommendations, and a raw pro view when you need the full detail.

## Recommended Installation

SmartControl depends on `smartctl`, which is usually installed through Homebrew.

```bash
brew install smartmontools
```

After installation, the common executable paths are:

- `/opt/homebrew/sbin/smartctl` on Apple Silicon Homebrew
- `/usr/local/sbin/smartctl` on Intel Homebrew

If SmartControl cannot find `smartctl` automatically, open Settings in the app and set the full path manually.

## What The App Does

- Shows real physical disks in a native macOS sidebar
- Uses `smartctl --json` so the UI is based on structured data, not terminal scraping
- Highlights health state, temperature, endurance, power-on time, and other key metrics
- Explains why a drive is healthy, needs attention, or is critical
- Surfaces recommended actions and SMART messages
- Lets you start short and extended SMART self-tests
- Preserves a raw JSON “Pro View” for deeper inspection

## Running Locally

Build the app:

```bash
swift build
```

Run it through the project script:

```bash
./script/build_and_run.sh
```

The Codex app Run button is wired to the same script through `.codex/environments/environment.toml`.

## Notes

- Some SMART operations require administrator access. SmartControl can prompt for that when needed.
- If `smartctl` is missing, the app falls back to limited drive data from Disk Utility and explains how to install `smartmontools`.
- Not every disk bridge or enclosure exposes full SMART data, especially over some USB adapters.
