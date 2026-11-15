extends Resource
## The planet's detail relief, baked. One cubemap face per image.
##
## The surface shader used to synthesise this per fragment: three evaluations of a
## three-chain ridged noise field, 72 hashes and 9 `pow`, to obtain two finite
## differences and one curvature term. Stubbing the whole thing out measured a
## fifth of the frame at 5120 x 2880, so it is differentiated offline instead and
## shipped -- the fragment gets the same three numbers from one tap.
##
## Everything here is in object space, because the planet rolls under the ship and
## the terrain has to roll with it. Channels, in RGBA order:
##
##   R, G, B - the detail rise as a tangent-plane vector in object space, mapped
##       from -slope_range..slope_range onto 0..1. A vector and not two components
##       in the local frame: the tangent frame the shader builds has a
##       discontinuity ring, and a cubemap blends neighbours. See
##       `_detail_at()` in the bake for the full reason.
##   A - the cavity, mapped from -1..1 onto 0..1.
##
## Produced by `tools/bake_planet.gd`. Never edit by hand.

@export var faces: Array[Image] = []
## The slope the vector channels saturate at, in world units per world unit. The
## shader decodes with it, so it must agree with the bake that wrote the bytes.
@export var slope_range: float = 2.0
