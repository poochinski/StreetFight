extends RefCounted
## Checkpoints: written on entering a place, removed on victory or defeat.
## Version 2 stores attributes, unspent points, equipment and the bag. Version 3
## adds the world: where the hero is, the run's seed, places visited, the stash
## and side quests. Version 2 saves still load, on the street of their floor.

const Items = preload("res://scripts/items.gd")
const VERSION = 3
const Zones = preload("res://scripts/zones.gd")
const AREA_KINDS = ["street", "mall", "park", "warehouse", "subway"]
const STAT_KEYS = ["hp","level","xp","gold","potions","mana","attributes","points","equipment","bag","class"]

static func write(path: String, player: Dictionary, floor_number: int, kills: int, elapsed: float, seed_value: int, world: Dictionary = {}) -> void:
	var stats = {}
	for key in STAT_KEYS: stats[key] = player[key]
	var file = FileAccess.open(path,FileAccess.WRITE)
	if file: file.store_string(JSON.stringify({"version":VERSION,"floor":floor_number,"stats":stats,"kills":kills,"time":elapsed,"seed":seed_value,"world":world}))

static func _number(value) -> bool:
	return value is float or value is int

static func _valid_item(item) -> bool:
	if item==null: return true
	if not item is Dictionary: return false
	if not item.get("name") is String or not item.get("slot") is String: return false
	if not _number(item.get("rarity")) or int(item.rarity)<0 or int(item.rarity)>4: return false
	if not _number(item.get("level")) or not _number(item.get("value")): return false
	if not item.get("affixes") is Array or not item.get("gems") is Array: return false
	for a in item.affixes:
		if not a is Array or a.size()!=2 or not Items.AFFIXES.has(a[0]) or not _number(a[1]): return false
	for gem in item.gems:
		if not gem is Dictionary or not Items.GEMS.has(gem.get("gem")) or not _number(gem.get("tier")): return false
	if item.slot=="weapon":
		for k in ["min","max","speed"]:
			if not _number(item.get(k)): return false
	if item.slot=="gem" and (not Items.GEMS.has(item.get("gem")) or not _number(item.get("tier"))): return false
	return true

static func read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or not (data.get("version") in [2.0,3.0]): return {}
	if not data.get("stats") is Dictionary or int(data.get("floor",0)) not in [1,2,3]: return {}
	var s = data.stats
	for k in ["hp","level","xp","gold","potions","mana","points"]:
		if not _number(s.get(k)): return {}
	if s.hp<=0 or s.level<1: return {}
	if not s.get("attributes") is Dictionary: return {}
	for k in Items.ATTRIBUTES:
		if not _number(s.attributes.get(k)): return {}
	if not s.get("equipment") is Dictionary or not s.get("bag") is Array: return {}
	for slot in Items.EQUIP_SLOTS:
		if not s.equipment.has(slot) or not _valid_item(s.equipment[slot]): return {}
		if s.equipment[slot]!=null and not Items.fits(s.equipment[slot],slot): return {}
	if s.bag.size()>Items.BAG_SIZE: return {}
	for item in s.bag:
		if not _valid_item(item): return {}
	var world = data.get("world",{})
	if not world is Dictionary: return {}
	if not world.is_empty():
		var area = world.get("area")
		if not area is Dictionary or not (area.get("kind") in AREA_KINDS) or not _number(area.get("level")): return {}
		if int(area.level)<1 or int(area.level)>Zones.STREETS: return {}
		if area.has("arrive") and not area.arrive is String: return {}
		if not _number(world.get("run_seed")) or not world.get("visited") is Array or not world.get("quests") is Dictionary: return {}
		if not world.get("stash") is Array or world.stash.size()>Zones.STASH_SIZE: return {}
		for item in world.stash:
			if not _valid_item(item): return {}
		world.run_seed = int(world.run_seed)
		area.level = int(area.level)
	# JSON stores every number as a float; counters go back to whole numbers.
	for k in ["level","xp","gold","potions","points"]: s[k] = int(s[k])
	for k in Items.ATTRIBUTES: s.attributes[k] = int(s.attributes[k])
	return data

static func erase(path: String) -> void:
	if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
