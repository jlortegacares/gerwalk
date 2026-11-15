extends Resource
## A baked planet terrain field, one cubemap face per image.
##
## The surface shader samples this with the object-space direction, so the field
## belongs to the planet and rolls with it. Channels, in RGBA order:
##
##   R - signed elevation. Zero is the waterline, `1` is the highest peak and `-1`
##       the deepest trench. Signed so one channel carries both the land height and
##       the water depth, which are never both meaningful at the same point.
##   G - distance to the nearest river, normalised by `river_max_distance`. A
##       distance field rather than a mask: bilinear sampling reconstructs a river
##       far thinner than a texel, which a mask could never do.
##   B - urban suitability, 0..1. The shader reads it once per city district, so a
##       district is whole instead of being cut by a soft boundary.
##   A - moisture, 0..1. Drives the grass tone; without it every landmass is the
##       same olive.
##
## Produced by `tools/bake_planet.gd`. Never edit by hand.

@export var faces: Array[Image] = []
## The relief the elevation channel is scaled by, in world units. The shader needs
## it to turn the gradient into slopes, and slopes into normals.
@export var relief_units: float = 60.0
## The distance the river channel saturates at, in world units.
@export var river_max_distance: float = 24.0
