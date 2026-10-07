extends RefCounted
## Bag and equipment rules: picking items up, equipping and swapping, socketing
## gems, salvaging for gold, sorting, and dropping items back on the ground.
## g.held is the item on the mouse cursor while the panels are open.

const Items = preload("res://scripts/items.gd")
const Data = preload("res://scripts/data.gd")

static func first_free(g) -> int:
	for i in Items.BAG_SIZE:
		if g.player.bag[i]==null: return i
	return -1

## Puts a found item away: into an empty matching equipment slot if there is
## one the hero can use, otherwise into the bag. Returns false when the bag is full.
static func store(g, item: Dictionary) -> bool:
	if not Items.is_gem(item) and int(item.level)<=int(g.player.level):
		var slot = Items.compared_slot(item, g.player.equipment)
		if slot!="" and g.player.equipment[slot]==null:
			g.player.equipment[slot] = item
			g._recalc()
			return true
	var index = first_free(g)
	if index<0: return false
	g.player.bag[index] = item
	return true

## Why an item cannot go in a slot, or "" if it can.
static func refusal(g, item, slot: String) -> String:
	if item==null: return ""
	if Items.is_gem(item): return "Gems go into an item’s empty socket."
	if not Items.fits(item, slot): return "That goes in the %s slot." % Items.SLOT_LABELS.get(item.slot if item.slot!="ring" else "ring1", item.slot)
	if int(item.level)>int(g.player.level): return "Requires level %d." % int(item.level)
	return ""

static func _refuse(g, reason: String) -> void:
	g._notice(reason)
	g._tone(120, 0.12, "triangle", 0.03)

static func equip_from_bag(g, index: int, slot: String = "") -> void:
	var item = g.player.bag[index]
	if item==null: return
	if Items.is_gem(item):
		_refuse(g, "Pick up the gem, then click an item with an empty socket.")
		return
	if slot=="": slot = Items.compared_slot(item, g.player.equipment)
	var reason = refusal(g, item, slot)
	if reason!="":
		_refuse(g, reason)
		return
	g.player.bag[index] = g.player.equipment[slot]
	g.player.equipment[slot] = item
	g._recalc()
	_equip_sound(g, item)

static func unequip(g, slot: String) -> void:
	var item = g.player.equipment[slot]
	if item==null: return
	var index = first_free(g)
	if index<0:
		_refuse(g, "Your bag is full.")
		return
	g.player.bag[index] = item
	g.player.equipment[slot] = null
	g._recalc()
	g._tone(330, 0.08, "triangle", 0.02)

static func _equip_sound(g, item: Dictionary) -> void:
	g._tone(520+int(item.rarity)*90, 0.12, "triangle", 0.03)

static func socket(g, gem: Dictionary, item: Dictionary) -> void:
	item.gems.append(gem)
	g._recalc()
	g._notice("%s set into %s." % [gem.name, item.name])
	g._tone(880, 0.25, "sine", 0.035)

## Left click on a bag slot: pick up, put down, swap, or socket the held gem.
static func click_bag(g, index: int, shift: bool) -> void:
	var item = g.player.bag[index]
	if g.held!=null:
		if Items.is_gem(g.held) and item!=null and Items.open_sockets(item)>0:
			socket(g, g.held, item)
			g.held = null
			return
		g.player.bag[index] = g.held
		g.held = item
		g._tone(300, 0.05, "triangle", 0.015)
		return
	if item==null: return
	if shift:
		salvage(g, index)
		return
	g.held = item
	g.player.bag[index] = null
	g._tone(260, 0.05, "triangle", 0.015)

## Left click on an equipment slot: equip the held item, swap, or pick up.
static func click_equipment(g, slot: String) -> void:
	var item = g.player.equipment[slot]
	if g.held!=null:
		if Items.is_gem(g.held):
			if item!=null and Items.open_sockets(item)>0:
				socket(g, g.held, item)
				g.held = null
			else: _refuse(g, "Choose an item with an empty socket.")
			return
		var reason = refusal(g, g.held, slot)
		if reason!="":
			_refuse(g, reason)
			return
		g.player.equipment[slot] = g.held
		_equip_sound(g, g.held)
		g.held = item
		g._recalc()
		return
	if item==null: return
	g.held = item
	g.player.equipment[slot] = null
	g._recalc()

static func salvage(g, index: int) -> void:
	var item = g.player.bag[index]
	if item==null: return
	g.player.bag[index] = null
	g.player.gold += int(item.value)
	g._feed("Salvaged %s  +%d gold" % [item.name, int(item.value)], Data.GOLD)
	g._tone(700, 0.08, "sine", 0.02)

## Orders the bag: gear by slot, best rarity and level first, then gems.
static func sort(g) -> void:
	var order = ["weapon", "helmet", "chest", "gloves", "boots", "belt", "amulet", "ring", "gem"]
	var items: Array = g.player.bag.filter(func(i): return i!=null)
	items.sort_custom(func(a, b):
		var sa = order.find(a.slot)
		var sb = order.find(b.slot)
		if sa!=sb: return sa<sb
		if int(a.rarity)!=int(b.rarity): return int(a.rarity)>int(b.rarity)
		return int(a.level)>int(b.level))
	g.player.bag = Items.empty_bag()
	for i in items.size(): g.player.bag[i] = items[i]
	g._tone(400, 0.06, "triangle", 0.015)

static func drop_held(g) -> void:
	if g.held==null: return
	g._drop_item(g.player.pos, g.held, true)
	g.held = null
	g._tone(200, 0.08, "triangle", 0.02)

## Puts the held item back in the bag (or on the ground when the bag is full).
static func stow_held(g) -> void:
	if g.held==null: return
	var index = first_free(g)
	if index>=0:
		g.player.bag[index] = g.held
		g.held = null
	else: drop_held(g)

# --- Food court: the Pawn Shop, the Juice Bar and the stash ----------------------

const PRICE_MULT = 3
const Zones = preload("res://scripts/zones.gd")

## What the Pawn Shop sells this visit: gear near the hero's level, mostly
## Uncommon and Rare, the odd Epic.
static func make_stock(g) -> Array:
	var out: Array = []
	for i in Zones.STOCK_SIZE:
		var roll = g._random()
		var rarity = 3 if roll<0.08 else 2 if roll<0.45 else 1 if roll<0.85 else 0
		var item = Items.generate(g, int(g.player.level)+floori(g._random()*3)-1, rarity, ["weapon", "chest", "helmet", "gloves", "boots", "belt", "ring", "amulet", "weapon", "chest", "ring", "helmet"][i])
		item.price = int(item.value)*PRICE_MULT
		out.append(item)
	return out

static func price(item: Dictionary) -> int:
	return int(item.get("price", int(item.value)*PRICE_MULT))

static func buy(g, index: int) -> void:
	if index>=g.stock.size() or g.stock[index]==null: return
	var item: Dictionary = g.stock[index]
	if g.player.gold<price(item):
		_refuse(g, "Not enough gold.")
		return
	if first_free(g)<0:
		_refuse(g, "Your bag is full.")
		return
	g.player.gold -= price(item)
	var bought = item.duplicate(true)
	bought.erase("price")
	g.player.bag[first_free(g)] = bought
	g.stock[index] = null
	g._feed("Bought %s  −%d gold" % [item.name, price(item)], Items.color(item))
	g._tone(880, 0.12, "sine", 0.03)

## Sells a bag item to the Pawn Shop for its full value.
static func sell(g, index: int) -> void:
	var item = g.player.bag[index]
	if item==null: return
	g.player.bag[index] = null
	g.player.gold += int(item.value)
	g._feed("Sold %s  +%d gold" % [item.name, int(item.value)], Data.GOLD)
	g._tone(700, 0.08, "sine", 0.02)

static func sell_held(g) -> void:
	if g.held==null: return
	g.player.gold += int(g.held.value)
	g._feed("Sold %s  +%d gold" % [g.held.name, int(g.held.value)], Data.GOLD)
	g.held = null
	g._tone(700, 0.08, "sine", 0.02)

static func buy_potion(g) -> void:
	if g.player.gold<Zones.POTION_PRICE:
		_refuse(g, "Not enough gold.")
		return
	g.player.gold -= Zones.POTION_PRICE
	g.player.potions += 1
	g._feed("Health Potion  −%d gold" % Zones.POTION_PRICE, Color("ff8aa0"))
	g._tone(620, 0.08, "sine", 0.02)

## Left click on a stash slot: pick up, put down or swap, like the bag.
static func click_stash(g, index: int) -> void:
	var item = g.stash[index]
	if g.held!=null and Items.is_gem(g.held) and item!=null and Items.open_sockets(item)>0:
		socket(g, g.held, item)
		g.held = null
		return
	g.stash[index] = g.held
	g.held = item
	if g.held!=null or item!=null: g._tone(280, 0.05, "triangle", 0.015)

## Right click moves an item between the bag and the stash.
static func to_stash(g, index: int) -> void:
	var item = g.player.bag[index]
	if item==null: return
	var slot = g.stash.find(null)
	if slot<0:
		_refuse(g, "Your stash is full.")
		return
	g.stash[slot] = item
	g.player.bag[index] = null
	g._tone(300, 0.05, "triangle", 0.015)

static func from_stash(g, index: int) -> void:
	var item = g.stash[index]
	if item==null: return
	var slot = first_free(g)
	if slot<0:
		_refuse(g, "Your bag is full.")
		return
	g.player.bag[slot] = item
	g.stash[index] = null
	g._tone(260, 0.05, "triangle", 0.015)
