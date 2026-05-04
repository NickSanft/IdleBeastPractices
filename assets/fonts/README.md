# Fonts

Two TrueType fonts ship with the project as the visual foundation for Phase 10's theme:

| File | Family | License | Used for |
|---|---|---|---|
| `peniber_body.ttf` | EB Garamond (variable, weight axis) | SIL Open Font License 1.1 | Body text, default Theme font |
| `peniber_display.ttf` | Cinzel (variable, weight axis) | SIL Open Font License 1.1 | Headings, Peniber's overlay |

License texts are committed alongside as `EBGaramond-OFL.txt` and `Cinzel-OFL.txt` per OFL §3 (which requires the license to travel with redistributed copies of the font).

**Why these fonts:** EB Garamond evokes 17th-century printer's Garamond — the right register for Peniber's archaic, condescending voice. Cinzel reads as engraved Roman capitals, fitting for headings and the narrator's full title.

**Replacement:** swap either file for a different TTF/OTF with the same filename. Font filenames are referenced from `game/resources/main_theme.tres`; if you change the filename you'll need to re-import in Godot or update the theme.

Sources:

- EB Garamond — <https://github.com/google/fonts/tree/main/ofl/ebgaramond>
- Cinzel — <https://github.com/google/fonts/tree/main/ofl/cinzel>
