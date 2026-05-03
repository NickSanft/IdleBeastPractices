#!/usr/bin/env bash
# v0.9.2 dialogue corpus expansion: 71 -> 150 lines.
#
# Idempotent: re-running overwrites; safe to invoke multiple times if
# you want to tweak text and re-render. All new files write into
# game/data/dialogue/. The existing 71 files are untouched.
#
# After running, re-import the project so Godot re-indexes the new
# .tres files: `godot --headless --path . --import`.

set -euo pipefail
cd "$(dirname "$0")/.."

write_line() {
  local filename="$1" id="$2" trigger="$3" text="$4" mood="$5" max_uses="$6"
  cat > "game/data/dialogue/$filename" <<TRES
[gd_resource type="Resource" script_class="DialogueLineResource" load_steps=2 format=3]

[ext_resource type="Script" path="res://game/resources/dialogue_line_resource.gd" id="1"]

[resource]
script = ExtResource("1")
id = &"$id"
trigger_id = &"$trigger"
text = "$text"
mood = &"$mood"
weight = 1.0
max_uses = $max_uses
TRES
}

# ── Tier 4-20 first-catch lines (one per tier; lead alphabetical species) ──

write_line "on_first_catch_dross_wraith.tres" \
  "first_catch_dross_wraith" "on_first_catch_dross_wraith" \
  "A dross-wraith. The metalmongers' refuse, condensed into petulant motion. Avoid the iron filings; they bite." \
  "smug" 1

write_line "on_first_catch_agate_golem.tres" \
  "first_catch_agate_golem" "on_first_catch_agate_golem" \
  "An agate golem. Stone, but with a chip on its shoulder — and the rest of its body besides. The Synod consulted geologists; none were helpful." \
  "weary" 1

write_line "on_first_catch_ripple_surge.tres" \
  "first_catch_ripple_surge" "on_first_catch_ripple_surge" \
  "A ripple-surge. Water with intent, which is the most ill-mannered configuration of water. Bring a towel; do not bring etiquette, it will mock you." \
  "smug" 1

write_line "on_first_catch_brood_glimmer.tres" \
  "first_catch_brood_glimmer" "on_first_catch_brood_glimmer" \
  "A brood-glimmer. The Synod used to keep these in jars, until the jars staged what is, on consideration, the only documented insurrection in the history of glassware." \
  "smug" 1

write_line "on_first_catch_briar_hedge.tres" \
  "first_catch_briar_hedge" "on_first_catch_briar_hedge" \
  "A briar-hedge. The thorns are decorative; the hedge is not. I once spent a fortnight in one. The Synod considered it a sabbatical." \
  "weary" 1

write_line "on_first_catch_brass_gleam.tres" \
  "first_catch_brass_gleam" "on_first_catch_brass_gleam" \
  "A brass gleamer. Polishing-cloth on the left, polishing-cloth on the right; the creature is, in a word, gilt. In a longer and more honest word: ostentatious." \
  "smug" 1

write_line "on_first_catch_floe_drift.tres" \
  "first_catch_floe_drift" "on_first_catch_floe_drift" \
  "A floe-drift. Cold to the touch and colder in disposition. The Synod's bestiary lists their favourite music as 'silence, lengthy, unaccompanied.'" \
  "weary" 1

write_line "on_first_catch_ash_scour.tres" \
  "first_catch_ash_scour" "on_first_catch_ash_scour" \
  "An ash-scour. Born of cinder, sustained by grievance. The Synod pays them in lukewarm tea, which is, I am informed, the cruellest insult yet devised." \
  "exasperated" 1

write_line "on_first_catch_index_muddler.tres" \
  "first_catch_index_muddler" "on_first_catch_index_muddler" \
  "An index-muddler. They reorder catalogues for fun. The Synod has lost two libraries this way, and counts itself, on balance, fortunate." \
  "weary" 1

write_line "on_first_catch_canto_refrain.tres" \
  "first_catch_canto_refrain" "on_first_catch_canto_refrain" \
  "A canto-refrain. They sing, after a fashion. The fashion is unfashionable. Bring earplugs; the Synod does, and the Synod is rarely wrong about earplugs." \
  "exasperated" 1

write_line "on_first_catch_gossamer_knot.tres" \
  "first_catch_gossamer_knot" "on_first_catch_gossamer_knot" \
  "A gossamer-knot. Silk wound around silk wound around the part where you used to keep your patience. The Synod has stopped untying them — purely, it claims, on principle." \
  "weary" 1

write_line "on_first_catch_candle_vigil.tres" \
  "first_catch_candle_vigil" "on_first_catch_candle_vigil" \
  "A candle-vigil. They keep watch over things that have, frankly, never asked. The Synod respects the tradition. I, for the record, do not." \
  "begrudging" 1

write_line "on_first_catch_mirror_refract.tres" \
  "first_catch_mirror_refract" "on_first_catch_mirror_refract" \
  "A mirror-refract. They cast images that are, as a rule, slightly truer than the original. The Synod finds this distasteful. I find it, against my better judgement, illuminating." \
  "reverent" 1

write_line "on_first_catch_parchment_palimpsest.tres" \
  "first_catch_parchment_palimpsest" "on_first_catch_parchment_palimpsest" \
  "A parchment-palimpsest. Written upon, written under, written through. Each layer disagrees with the last. The Synod calls this 'institutional history.'" \
  "weary" 1

write_line "on_first_catch_cipher_whisper.tres" \
  "first_catch_cipher_whisper" "on_first_catch_cipher_whisper" \
  "A cipher-whisper. They speak in the spaces between meanings. The Synod has decoded three; the rest are, in a word, ongoing. The word is unsatisfactory." \
  "begrudging" 1

write_line "on_first_catch_lacuna_hollow.tres" \
  "first_catch_lacuna_hollow" "on_first_catch_lacuna_hollow" \
  "A lacuna-hollow. Where there ought to be substance, there is instead an absence with opinions. I find them, against custom, agreeable company." \
  "reverent" 1

write_line "on_first_catch_aether_nadir.tres" \
  "first_catch_aether_nadir" "on_first_catch_aether_nadir" \
  "An aether-nadir. Whatever this is, it is the bottom of something — and you have, somehow, reached it. The Synod prepares its citation now." \
  "reverent" 1

# ── Pool variants: extend each major pool by 4-5 lines ──

# on_battle_loss_pool 6-10 (existing 1-5)
write_line "on_battle_loss_pool_6.tres" "battle_loss_pool_6" "on_battle_loss" \
  "Loss. I have, on consideration, devised three distinct theories of consolation. None apply. We shall move on." \
  "exasperated" 0
write_line "on_battle_loss_pool_7.tres" "battle_loss_pool_7" "on_battle_loss" \
  "Defeat. The pets are in the back; you may, if you wish, apologize to them. They will pretend to listen." \
  "exasperated" 0
write_line "on_battle_loss_pool_8.tres" "battle_loss_pool_8" "on_battle_loss" \
  "A loss. Recorded, as the Synod requires, with two extra exclamation marks the Synod also requires me to redact." \
  "exasperated" 0
write_line "on_battle_loss_pool_9.tres" "battle_loss_pool_9" "on_battle_loss" \
  "The opposing party prevailed. The Synod's commiseration is on order; expect it sometime in the next fiscal quarter." \
  "weary" 0
write_line "on_battle_loss_pool_10.tres" "battle_loss_pool_10" "on_battle_loss" \
  "Defeat. My counsel: lower expectations until they fit. They almost fit already." \
  "exasperated" 0

# on_battle_win_pool 4-8 (existing 1-3)
write_line "on_battle_win_pool_4.tres" "battle_win_pool_4" "on_battle_win" \
  "A win. The opposing parties have been, in the Synod's measured phrasing, 'tabled.' I find the phrasing pleasing." \
  "begrudging" 0
write_line "on_battle_win_pool_5.tres" "battle_win_pool_5" "on_battle_win" \
  "Triumph. The Rancher Points are deposited. Peniber's notebook records it; Peniber's notebook is, regrettably, the official ledger." \
  "smug" 0
write_line "on_battle_win_pool_6.tres" "battle_win_pool_6" "on_battle_win" \
  "Victory. I shall let the precedent stand. The Synod, normally averse to precedents, is too tired to object." \
  "weary" 0
write_line "on_battle_win_pool_7.tres" "battle_win_pool_7" "on_battle_win" \
  "A win. The Synod's accountant has, against all custom, smiled. The smile is on the smaller side, but I am cataloguing it." \
  "begrudging" 0
write_line "on_battle_win_pool_8.tres" "battle_win_pool_8" "on_battle_win" \
  "Triumph. I confess to a brief, unfraternal pleasure. It will pass. Most pleasures do, in this office." \
  "begrudging" 0

# on_idle_too_long 6-10 (existing 1-5)
write_line "on_idle_too_long_6.tres" "idle_too_long_6" "on_idle_too_long" \
  "Are you composing? Composing what? The Synod composes correspondence; the wisplets compose grievances. You compose nothing yet." \
  "weary" 0
write_line "on_idle_too_long_7.tres" "idle_too_long_7" "on_idle_too_long" \
  "If you have stepped away to re-evaluate priorities, may I suggest the catching screen — directly to the left of where you are not currently looking." \
  "exasperated" 0
write_line "on_idle_too_long_8.tres" "idle_too_long_8" "on_idle_too_long" \
  "The wisplets are taking advantage of your absence to rehearse. I do not know what they are rehearsing. Perhaps a reply." \
  "weary" 0
write_line "on_idle_too_long_9.tres" "idle_too_long_9" "on_idle_too_long" \
  "Idleness, the Synod's bulletin notes, is the one virtue practitioners excel at without prompting. You have, on this front, exceeded expectation." \
  "exasperated" 0
write_line "on_idle_too_long_10.tres" "idle_too_long_10" "on_idle_too_long" \
  "I have, in your absence, composed a long letter to no one. The wisplets have, in your absence, multiplied. We are, in different ways, productive." \
  "weary" 0

# on_ledger_opened 6-10 (existing 1-5)
write_line "on_ledger_opened_6.tres" "ledger_opened_6" "on_ledger_opened" \
  "The Ledger is, to be clear, mostly numbers. I find numbers preferable to the alternative, which is, generally, opinions." \
  "weary" 0
write_line "on_ledger_opened_7.tres" "ledger_opened_7" "on_ledger_opened" \
  "You have opened the Ledger. Among the documented sins of practitioners, this one is — at last — defensible." \
  "begrudging" 0
write_line "on_ledger_opened_8.tres" "ledger_opened_8" "on_ledger_opened" \
  "The Ledger. A monument to your patience and the Synod's bookkeeping. One of these two has, demonstrably, more of itself." \
  "weary" 0
write_line "on_ledger_opened_9.tres" "ledger_opened_9" "on_ledger_opened" \
  "Examining the figures. The figures, I am informed, examine you in return. The Synod calls this 'reciprocity.' I call it Tuesday." \
  "weary" 0
write_line "on_ledger_opened_10.tres" "ledger_opened_10" "on_ledger_opened" \
  "The Ledger is open. The numbers are, as ever, both larger and smaller than expected. The Synod calls this 'accurate.'" \
  "weary" 0

# on_offline_return_short 4-7 (existing 1-3)
write_line "on_offline_return_short_4.tres" "offline_return_short_4" "on_offline_return_short" \
  "You are returned. The wisplets did, in your absence, the bare minimum. They are extremely consistent on this point." \
  "smug" 0
write_line "on_offline_return_short_5.tres" "offline_return_short_5" "on_offline_return_short" \
  "Welcome back. Nothing has happened. This is, technically, a kind of stability. I take what I can get." \
  "weary" 0
write_line "on_offline_return_short_6.tres" "offline_return_short_6" "on_offline_return_short" \
  "Returned, and just in time. The auto-net is, as ever, indifferent to whether anyone is watching, but I am — and so I notice." \
  "smug" 0
write_line "on_offline_return_short_7.tres" "offline_return_short_7" "on_offline_return_short" \
  "You have come back. I should, the Synod insists, greet you. Greetings." \
  "weary" 0

# on_offline_return_long 4-7 (existing 1-3)
write_line "on_offline_return_long_4.tres" "offline_return_long_4" "on_offline_return_long" \
  "Returned at last. I am — purely, you understand, for completeness — pleased to see the figures. Not the figure who carries them; the figures themselves." \
  "begrudging" 0
write_line "on_offline_return_long_5.tres" "offline_return_long_5" "on_offline_return_long" \
  "Welcome back. The wisplets have lost interest in being caught and have begun, instead, to compose ballads. The ballads are unflattering." \
  "weary" 0
write_line "on_offline_return_long_6.tres" "offline_return_long_6" "on_offline_return_long" \
  "You have returned after an extended absence. I have, purely as a point of professional pride, kept the lights on. They are, of course, your lights." \
  "weary" 0
write_line "on_offline_return_long_7.tres" "offline_return_long_7" "on_offline_return_long" \
  "Long away, then. The auto-net does not tire. I, by contrast, am made entirely of tiredness today." \
  "weary" 0

# on_pet_acquired_pool 4-8 (existing 1-3)
write_line "on_pet_acquired_pool_4.tres" "pet_acquired_pool_4" "on_pet_acquired" \
  "A pet, granted. The Synod's livestock-clerk has updated her ledger. Her smile is, by her own admission, transactional." \
  "smug" 0
write_line "on_pet_acquired_pool_5.tres" "pet_acquired_pool_5" "on_pet_acquired" \
  "Another companion. I am informed they have small, definite preferences regarding hay. None of which the Synod has, on principle, met." \
  "weary" 0
write_line "on_pet_acquired_pool_6.tres" "pet_acquired_pool_6" "on_pet_acquired" \
  "A pet has joined you. They will, in due course, develop opinions. The Synod is preparing the standard disclaimer." \
  "smug" 0
write_line "on_pet_acquired_pool_7.tres" "pet_acquired_pool_7" "on_pet_acquired" \
  "Another beast in your retinue. The Synod is, on the record, pleased — which is the Synod's polite way of saying 'concerned.'" \
  "smug" 0
write_line "on_pet_acquired_pool_8.tres" "pet_acquired_pool_8" "on_pet_acquired" \
  "A new pet. The Synod's veterinarian charges by the consultation. I would, I should say, save my consultations for emergencies." \
  "weary" 0

# on_prestige_pool 4-8 (existing 1-3)
write_line "on_prestige_pool_4.tres" "prestige_pool_4" "on_prestige" \
  "Another prestige. The Synod's archivist has begun assigning you a small, dedicated drawer. It will, by year's end, require its own room." \
  "begrudging" 0
write_line "on_prestige_pool_5.tres" "prestige_pool_5" "on_prestige" \
  "Prestige completed. The accountants are, on consideration, no longer willing to print the figure. They mutter the figure, instead, and the figure is content." \
  "reverent" 0
write_line "on_prestige_pool_6.tres" "prestige_pool_6" "on_prestige" \
  "A prestige. The wisplets have been, between rounds, taking notes. The notes are — and I cannot stress this enough — complimentary." \
  "begrudging" 0
write_line "on_prestige_pool_7.tres" "prestige_pool_7" "on_prestige" \
  "Another prestige. I should, the Synod's etiquette pamphlet insists, congratulate you. Congratulations. The pamphlet is appeased." \
  "weary" 0
write_line "on_prestige_pool_8.tres" "prestige_pool_8" "on_prestige" \
  "Prestige logged. The Synod has, in private, raised a brow. In public, the Synod denies the existence of brows." \
  "begrudging" 0

# on_shiny_pool 5-8 (existing 1-4)
write_line "on_shiny_pool_5.tres" "shiny_pool_5" "on_shiny" \
  "A shiny. The iridescence is, I should mention, diagnostic — of what, the Synod has not specified. Three theories, none of them coherent." \
  "reverent" 0
write_line "on_shiny_pool_6.tres" "shiny_pool_6" "on_shiny" \
  "Another shiny. The Synod's aestheticians convene. By 'convene' I mean argue. By 'argue' I mean, frankly, screech." \
  "weary" 0
write_line "on_shiny_pool_7.tres" "shiny_pool_7" "on_shiny" \
  "A shiny variant. The pigment, I am told, is sourced from a region the Synod no longer acknowledges. The pigment, fortunately, does not require acknowledgement." \
  "reverent" 0
write_line "on_shiny_pool_8.tres" "shiny_pool_8" "on_shiny" \
  "An iridescent specimen. I shall record the precise hue, because we are, as I believe I have mentioned, tedious in a deliberate, principled fashion." \
  "smug" 0

# ── New trigger types ──

# Late-game catch milestones
write_line "on_milestone_100000.tres" "milestone_100000" "on_milestone_100000" \
  "One hundred thousand. The Synod's mathematicians, on review, have demanded a vacation. They will not return." \
  "weary" 1
write_line "on_milestone_1000000.tres" "milestone_1000000" "on_milestone_1000000" \
  "A million catches. I shall, against custom, decline to belabour the point. The point belabours itself." \
  "reverent" 1

# Prestige milestones
write_line "on_5_prestiges.tres" "five_prestiges" "on_5_prestiges" \
  "Five prestiges. The Synod's archivist has stopped flinching when your name appears. This is, by archivists' standards, intimate." \
  "begrudging" 1
write_line "on_10_prestiges.tres" "ten_prestiges" "on_10_prestiges" \
  "Ten prestiges. The Synod has, against centuries of policy, requested an audience. You may decline. I would. I have." \
  "reverent" 1
write_line "on_25_prestiges.tres" "twentyfive_prestiges" "on_25_prestiges" \
  "Twenty-five prestiges. The pets, I am told by my own ledger, now have ledgers. Their ledgers describe you in terms I shall not — for the comfort of my own notebook — transcribe." \
  "reverent" 1

# Per-recipe first-craft (top 3 most-likely-crafted)
write_line "on_first_craft_tier2_net.tres" "first_craft_tier2_net" "on_first_craft_recipe_tier2_net" \
  "Your first crafted net — the Tier-2 model. The Synod's quartermaster will, on request, supply mocking applause. She charges by the clap." \
  "smug" 1
write_line "on_first_craft_pet_collar.tres" "first_craft_pet_collar" "on_first_craft_recipe_pet_collar" \
  "A collar. The pet, I should mention, was not consulted. The pet, I should also mention, has opinions on the matter — none of them favourable." \
  "weary" 1
write_line "on_first_craft_shiny_lure.tres" "first_craft_shiny_lure" "on_first_craft_recipe_shiny_lure" \
  "A shiny-lure. The Synod once banned these on aesthetic grounds; the ban was lifted on the grounds that aesthetics had, in the meantime, expired." \
  "begrudging" 1

echo "Wrote $(ls game/data/dialogue/*.tres | wc -l) total dialogue files."

# ── Round 2: top-up to 150 ──

# 3 more battle_loss
write_line "on_battle_loss_pool_11.tres" "battle_loss_pool_11" "on_battle_loss" \
  "Another defeat. The Synod, ever the optimist, calls this 'character-building.' The character is, by my count, almost completely built." \
  "exasperated" 0
write_line "on_battle_loss_pool_12.tres" "battle_loss_pool_12" "on_battle_loss" \
  "Loss. The auto-battler, I should clarify, is not actually trying. Whether the alternative would be worse is, by Synod policy, unanswered." \
  "weary" 0
write_line "on_battle_loss_pool_13.tres" "battle_loss_pool_13" "on_battle_loss" \
  "Defeat, the formality completed. We move to the next item on the agenda, which is also defeat. I shall, eventually, find a new agenda." \
  "exasperated" 0

# 3 more idle_too_long
write_line "on_idle_too_long_11.tres" "idle_too_long_11" "on_idle_too_long" \
  "Tea? Letter? Existential review? Whatever it is, the wisplets are not on hold. Wisplets do not hold. The Synod has tried." \
  "weary" 0
write_line "on_idle_too_long_12.tres" "idle_too_long_12" "on_idle_too_long" \
  "Stillness, the third hour of. I have begun to take it personally. The Synod is, I am told, prouder of me than ever for that." \
  "exasperated" 0
write_line "on_idle_too_long_13.tres" "idle_too_long_13" "on_idle_too_long" \
  "If you are listening to a podcast, I should mention that the Synod runs one. It is short. It is bad. It is also free, on principle." \
  "weary" 0

# 3 more "first-catch" for additional tier 4-20 variant species
# (covers the second species in tiers where the lead drew an
# especially strong reaction in the first-pass lines)
write_line "on_first_catch_scoria_wraith.tres" \
  "first_catch_scoria_wraith" "on_first_catch_scoria_wraith" \
  "A scoria-wraith. Sister to the dross variety; the Synod's classifier had a bad afternoon and listed both under 'unclassifiable.'" \
  "smug" 1
write_line "on_first_catch_geode_golem.tres" \
  "first_catch_geode_golem" "on_first_catch_geode_golem" \
  "A geode-golem. Hollow at the centre, faceted everywhere else. The Synod once shipped one as a gift; the recipient, on opening it, gifted it back." \
  "weary" 1
write_line "on_first_catch_eon_nadir.tres" \
  "first_catch_eon_nadir" "on_first_catch_eon_nadir" \
  "An eon-nadir. Time, condensed into a creature, condensed into a posture of profound disinterest. I sympathize. The Synod sympathizes by proxy." \
  "reverent" 1

echo "Round 2 wrote: $(ls game/data/dialogue/*.tres | wc -l) total dialogue files."
