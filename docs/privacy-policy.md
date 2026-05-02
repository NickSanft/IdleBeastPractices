---
layout: default
title: Privacy Policy — IdleBeastPractices
permalink: /privacy-policy/
---

# Privacy Policy

**Effective date:** May 2, 2026

This privacy policy applies to the **IdleBeastPractices** mobile game (package `com.divora.beast`), distributed through the Google Play Store. The app is developed and maintained by **Divora** (the "Developer", "we", "us", "our"). If you have any questions about this policy or your data, contact **dartdivora@gmail.com**.

By installing or using IdleBeastPractices, you agree to the practices described here. If you don't agree, please don't install the app.

## TL;DR

- We don't collect, store, or transmit any personal data on the developer side.
- The game shows **rewarded video ads** through Google AdMob. AdMob collects a limited set of device identifiers and approximate location for ad delivery, exactly as documented in [Google's policy](https://policies.google.com/technologies/partner-sites). You can opt out of personalized ads at any time on your device.
- Game state is saved **locally** on your device only.
- The game is intended for players **13 and older**.

## What we collect ourselves

**Nothing.** The app has no analytics SDK, no telemetry endpoint, no developer-side server. Game state — your gold, pets, bestiary entries, settings — is stored entirely on your device under Android's `user://` path (`/data/data/com.divora.beast/files/...`) and never leaves it. Uninstalling the app deletes all local game state. We have no way to recover it on your behalf.

## What Google AdMob collects (when you see an ad)

The game integrates Google AdMob to show rewarded video ads — short videos you can choose to watch in exchange for an in-game bonus. Rewarded ads are **always optional**; nothing in the game is gated behind them.

When AdMob serves an ad, it may collect:

- A device-resettable advertising ID (Android Advertising ID)
- General device information: model, OS version, screen size, language, app version
- Approximate location, derived from IP address — coarse city / region level
- Whether the ad was viewed and any standard ad-interaction signals

AdMob uses this data to choose which ad to show, prevent ad fraud, and report aggregated analytics back to advertisers. We (the Developer) do not receive personally identifying information from this process — only aggregate counts and revenue figures.

For full details on what AdMob collects, how long it retains data, and how to opt out, see Google's policy:
- [How Google uses information from sites or apps that use our services](https://policies.google.com/technologies/partner-sites)

## Opting out of personalized ads

You can opt out of personalized advertising on your Android device at any time:

1. Open **Settings → Privacy → Ads**.
2. Toggle on **Opt out of Ads Personalization** (or, on newer devices, **Delete advertising ID** — this resets it to a string of zeroes).

After opting out, you'll still see ads, but they will be non-personalized. The game will still award the in-game bonus for watching them.

## Children's privacy

IdleBeastPractices is **not directed to children under 13**. We don't knowingly collect any data from children under 13 ourselves. Because the app uses AdMob, in-app advertisements may be subject to additional restrictions when shown to users under 13 — Google AdMob applies COPPA-compliant filtering automatically when the device's age signal indicates a minor.

If you are a parent or guardian and believe your child under 13 has used the app, please contact us at **dartdivora@gmail.com** so we can confirm no data has been retained on our side (it hasn't — see "What we collect ourselves" above).

## Permissions the app requests

IdleBeastPractices requests the **`INTERNET`** permission. This is required for AdMob to fetch ads from Google's servers; the app uses no other network endpoints.

The app does **not** request access to your camera, microphone, contacts, location services, photos, or files outside its own sandbox.

## Changes to this policy

If we materially change this policy — for example, adding a new third-party service or starting to collect data ourselves — we'll update the **Effective date** at the top of this page and post a note on the [GitHub repository's release notes](https://github.com/NickSanft/IdleBeastPractices/releases). We won't apply changes retroactively to data already collected (which, as noted, is none on our side).

The current version of this policy is always available at:

> [https://nicksanft.github.io/IdleBeastPractices/privacy-policy/](https://nicksanft.github.io/IdleBeastPractices/privacy-policy/)

## Contact

- **Email:** dartdivora@gmail.com
- **GitHub issues:** [github.com/NickSanft/IdleBeastPractices/issues](https://github.com/NickSanft/IdleBeastPractices/issues)
