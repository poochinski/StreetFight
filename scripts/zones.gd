extends RefCounted
## The places in the city and how they connect.
##
## The streets are the spine: Neon Row (level 1), The Burnt Mile (2) and Sunset
## Plaza (3). Each street has doorways into side areas, and the subway stairs
## lead down to a station whose far stairs come up on the next street. Every
## place can be visited again; its layout comes from the run's seed, so it is
## the same place each time, but its enemies come back.
##
## An area is {"kind", "level"}. Arrival points: "start" (a street's start, by
## the stairs up from the previous station), "subway" (beside a street's subway
## entrance), "door" (inside a side area, by its way out), "door:<kind>" (on
## the street, outside that side area's doorway), "west"/"east" (a station's
## two stairways) and "foodcourt" (the mall's food court).

const Data = preload("res://scripts/data.gd")

const STREETS = 3
## Side areas on each street, entered through a doorway on the sidewalk.
const DOORS = {1: ["mall", "park"], 2: ["warehouse"], 3: []}
const PLACES = {
	"mall": {"name":"Starlight Mall", "sign":"STARLIGHT MALL", "level":1},
	"park": {"name":"Liberty Park", "sign":"LIBERTY PARK", "level":1},
	"warehouse": {"name":"Warehouse 13", "sign":"WAREHOUSE 13", "level":2},
}
## Side quests: each side area has a gang boss to put down. Taken on entering
## the area, finished when the boss falls. kind: the boss's body.
const QUESTS = {
	"park": {"title":"Turf War", "boss":"Static Sally", "kind":"ranged",
		"task":"Drive Static Sally out of the park.",
		"intro":"The Hex Kids hold the bandshell. Nobody walks the park after dark."},
	"mall": {"title":"Mall Rats", "boss":"Joystick Joe", "kind":"brute",
		"task":"Put Joystick Joe out of business.",
		"intro":"The food court is safe. The shops past the gates are not."},
	"warehouse": {"title":"Graveyard Shift", "boss":"The Foreman", "kind":"brute",
		"task":"Find the boss of the night crew.",
		"intro":"Somebody keeps moving crates in there at night."},
}
## The Pawn Shop's stock refreshes with every visit to the food court.
const STOCK_SIZE = 12
const POTION_PRICE = 15
const STASH_SIZE = 40

static func key(kind: String, level: int) -> String:
	return "%s:%d" % [kind, level]

static func street_name(level: int) -> String:
	return Data.FLOOR_NAMES[clampi(level-1, 0, STREETS-1)]

static func name(kind: String, level: int) -> String:
	match kind:
		"street": return street_name(level)
		"subway": return "%s Station" % street_name(level)
	return PLACES[kind].name

## Which street a side area opens from.
static func home_street(kind: String) -> int:
	return PLACES[kind].level if PLACES.has(kind) else 1

## Places the transit kiosks can take you to, once visited.
static func destinations() -> Array:
	var out: Array = [{"key":"foodcourt", "kind":"mall", "level":1, "arrive":"foodcourt", "name":"Food Court"}]
	for level in range(1, STREETS+1):
		out.append({"key":key("street", level), "kind":"street", "level":level, "arrive":"start", "name":street_name(level)})
		for kind in DOORS[level]:
			out.append({"key":key(kind, level), "kind":kind, "level":level, "arrive":"door", "name":PLACES[kind].name})
		if level<STREETS:
			out.append({"key":key("subway", level), "kind":"subway", "level":level, "arrive":"west", "name":name("subway", level)})
	return out

## A stable seed for a place in this run, so it is built the same way each visit.
static func seed_for(run_seed: int, kind: String, level: int) -> int:
	return absi(hash("%d/%s" % [run_seed, key(kind, level)]))&0x7fffffff

static func indoor(kind: String) -> bool:
	return kind in ["mall", "warehouse", "subway"]
