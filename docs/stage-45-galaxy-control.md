# Stage 45: Galaxy Control

**Status: CI-verified (format, lint, strict types, 227 unit tests, build, world and orbit
smoke tests). Not yet seen in Studio.**

A new **Galaxy Control** console stands on the hangar deck, beside Collect (9 studs to its
left), with a slowly spinning purple galaxy hologram on top. "Open Galaxy Control" opens one
panel for your whole galaxy:

- **Galaxy size:** "Galaxy size 2 of 3", stars placed out of what it holds, and the next
  expansion with its price: **Expand** (the same purchase as in the Shipyard, `ShopRequest
  "expand"`), or "Max size".
- **Every solar system:** star type and level, production per second and planets in use out of
  its orbits, with:
  - **Level up · price**, or **Evolve · price** at max level, or "Fully grown";
  - **Manage**: opens that star's own panel (planets, move);
  - **Inspect**: the system close up.
- **Buy a star**: opens the Star Shop.
- The header shows how many systems you have, their total production and your Stardust.

Only the owner can open their console; visitors are told it's someone else's. Everything is
checked by the server as before. The station is now 105 of its 110-part budget.

## Test in Studio

On your deck, open Galaxy Control: your stars are listed with the right levels; Level up and
Evolve work and the list updates; Manage and Inspect open the right star; Expand buys the next
size (when you can afford it); a second player can't open yours.
