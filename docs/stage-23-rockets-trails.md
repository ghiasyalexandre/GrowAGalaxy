# Stage 23: Pilot becomes the ship, ship colours, rockets, trails, top flight HUD

**Status: code complete, CI-verified (format, lint, strict types, 175 unit tests, build, world
and orbit smoke tests). Not yet playtested in Studio.**

## You are the ship

**The pilot is hidden:** while someone sits in a pilot seat, every client hides their character
(each part and decal, through LocalTransparencyModifier) until they leave the seat. Nothing
about the seat or physics changed; the character just isn't drawn.

**Trails:** while piloting, an equipped trail follows only the ship, not the hidden pilot.

## Ship editor: laser and boost colours (replaces paint and finish)

The Shipyard's **Colors** tab (it was Paint) now edits, per ship:
- **Laser colour:** 14 swatches or **S** for the standard orange. It colours your beam, its
  sparks and your rocket blasts. A chosen colour overrides the Golden Beam cosmetic; with none
  chosen, the Golden Beam still applies.
- **Boost colour:** the engine glow, the exhaust particles and the wing trails. Standard is the
  usual blue.

Each ship has its own colours, shown as two glowing chips next to its turning preview. The
Showcase Dock picker stays on this tab.

Hull paint and finishes are gone, along with the texture-tinting code. Ships always wear their
factory look.

## Rockets

- **Fire:** **Q** / gamepad **B** / the touch **Rocket** button while flying fires a heavy
  rocket at the reticle. The aim can be up to 60° off the nose.
- **Cooldown:** 12 s. The flight readout shows `Rocket ready` or `Rocket 8s`.
- **Flight:** the server flies the rocket at 240 studs per second, and it bursts on the first
  thing it touches, or after 3 s.
- **Blast:**
  - It has a radius of 45 studs and a strength of beam power × 12.
  - It adds extraction progress to every asteroid it catches. Any that break pay out as usual,
    golden ones included.
  - In a raid it damages the Death Star and pops drones.
  - It damages PvP ships under the usual PvP rules.
- **Look:**
  - The missile is dark, with a glowing nose in your laser colour and a trail of fire.
  - The explosion has a white-hot core, a fireball, a shimmering shell and a shockwave ring, all
    in your laser colour, plus sparks, smoke, a flash of light and a camera shake nearby.

## Flight HUD at the top

While flying, the speed and rocket readout and the four gauges (laser heat, boost, hull and
extraction) sit at the top centre of the screen, in a 2 × 2 block. Other top-centre elements
move out of the way:
- The raid boss bar moved down below them.
- The tutorial hint moves below them while you fly.

## Settings: controls hint

A new **Controls hint** toggle hides the list of controls along the bottom of the screen. It is
saved with your other settings.

## Trails (Shipyard > Trails)

Trails are bought with Stardust. The equipped trail streams behind you while floating and
behind your ship (at double width), and multiplies every Stardust you earn, from mining and from
stars, on top of passes and boosts.

| Trail | Multiplier | Price |
|---|---|---|
| Comet Dust | ×1.5 | 25,000 |
| Nebula Ribbon | ×2.0 | 150,000 |
| Solar Flare | ×2.5 | 750,000 |
| Aurora Veil | ×3.0 | 3,000,000 |
| Quasar Stream | ×3.5 | 12,000,000 |

Buying a trail equips it. Owned trails can be equipped or unequipped any time; only one at a
time.

## Golden asteroids

Swarm asteroids are now worth **5×** (was 3×) and are **2×** as tough to break.

## Save data

Version 11:
- Loadouts save `laserColor` and `boostColor`; old paint and finish values are dropped.
- New `ownedTrails` and `trail`.
- New setting `showControls`.

Older saves start with standard colours, no trails, and the controls shown.

## Test in Studio

1. **Pilot:** launch your ship. Your character should be invisible while you fly and come back
   when you exit.
2. **Flight HUD:** the speed readout and gauges should be at the top; the raid bar sits below
   them.
3. **Rocket:** press Q at an asteroid. Check the missile, the explosion in your laser colour,
   the progress or payout, and the reload countdown.
4. **Colours:** in Shipyard > Colors, pick a laser and a boost colour and fly. The beam,
   exhaust, engine glow and wing trails should change.
5. **Trails:** buy Comet Dust and check the trail on your suit, then on your ship. Mine an
   asteroid and check the reward is ×1.5.
6. **Settings:** hide the controls hint.
7. **Golden swarm:** golden asteroids take twice as long and pay 5×.
