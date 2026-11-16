class_name WeatherState
extends RefCounted
## Shared weather values other code reads: wind for hair, cloth and grass; time of day.
## The Weather node (scripts/weather.gd) drives them; tests and previews can set them directly.

## Wind strength, -1 (blowing left) .. 1 (blowing right). Gusts are added on top by readers.
static var wind := 0.25
## Seconds since start, for gust noise shared by every reader.
static var clock := 0.0

## Wind force (world px/s^2) at height `phase` for swaying things, gusty.
static func gust(phase: float) -> float:
	return wind * (0.75 + 0.35 * sin(clock * 1.7 + phase) + 0.2 * sin(clock * 4.3 + phase * 2.1))
