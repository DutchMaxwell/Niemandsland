class_name Units
extends RefCounted
## Unit conversions shared by the game: board measures are in inches, the 3D world is in metres,
## base sizes in millimetres.

## Inches to metres: value_in * INCHES_TO_METERS.
const INCHES_TO_METERS := 0.0254
## Metres to inches: value_m * METERS_TO_INCHES.
const METERS_TO_INCHES := 1.0 / 0.0254
## Millimetres to metres (base sizes): value_mm * MM_TO_METERS.
const MM_TO_METERS := 0.001
