# Third-party sources

World themes (`PhoneClient/Sources/Render/Shaders.metal`) are written for this project. Techniques taken from outside:

| Technique | Source | License |
| --- | --- | --- |
| Sun-tinted, height-dependent fog (`fogApply`) | Inigo Quilez, "better fog" — https://iquilezles.org/articles/fog/ | Code snippets on iquilezles.org are MIT (his shader art is *not*; none of it is used here) |
| Lighting principles (linear light, low albedo, bluish fill, warm key) | Inigo Quilez, "outdoors lighting" — https://iquilezles.org/articles/outdoorslighting/ | Ideas only; no shader art copied |

## Textures (CC0 / public domain)

Panoramas from Poly Haven (https://polyhaven.com/hdris), CC0, downloaded as their tone-mapped JPG and resized to 4096×2048
(`PhoneClient/Resources/Themes/`): `cobblestone_street_night` (Rain), `outdoor_umbrellas` (Sunny), `shanghai_bund` (Cyberpunk),
`venice_sunset` (Steampunk), `piazza_martin_lutero` (Solarpunk). Rain, neon flicker, airships, drones, birds and the café table are drawn on top.

Shadertoy itself returned HTTP 403 to automated access, and most Shadertoy shaders are CC BY-NC-SA by default, so no Shadertoy code is included.
