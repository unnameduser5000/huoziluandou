extends RefCounted
class_name EnemyAnimationCatalog
## Normalized anatomy, motion and effect origins for the previously missing cast.
## A zone is [pivot, influence rectangle]; all values refer to the source artwork.
const OBJECT_KINDS := ["debt","stone","edict","roller","tribunal","archive","guillotine"]
const DATA := {
	"bronze_seal": {"kind":"seal_beast", "effect":"seal", "release":0.34, "length":0.98, "head":Vector2(0.22,0.30), "left":Vector2(0.25,0.71), "right":Vector2(0.74,0.76), "prop":Vector2(0.30,0.55), "origin":Vector2(0.12,0.48), "origin_bone":"Head"},
	"iron_seal": {"kind":"crane", "effect":"blade", "release":0.32, "length":0.96, "head":Vector2(0.31,0.25), "left":Vector2(0.61,0.22), "right":Vector2(0.66,0.38), "prop":Vector2(0.45,0.53), "origin":Vector2(0.03,0.34), "origin_bone":"Head"},
	"paper_guard": {"kind":"fan", "effect":"paper", "release":0.34, "length":1.02, "head":Vector2(0.61,0.18), "left":Vector2(0.37,0.43), "right":Vector2(0.76,0.43), "prop":Vector2(0.53,0.63), "origin":Vector2(0.06,0.39), "origin_bone":"LimbL"},
	"rust_scribe": {"kind":"brush_beetle", "effect":"brush", "release":0.30, "length":0.92, "head":Vector2(0.32,0.48), "left":Vector2(0.48,0.72), "right":Vector2(0.80,0.64), "prop":Vector2(0.66,0.28), "origin":Vector2(0.04,0.69), "origin_bone":"Head"},
	"ember_imp": {"kind":"imp", "effect":"ember", "release":0.26, "length":0.78, "head":Vector2(0.44,0.66), "left":Vector2(0.23,0.78), "right":Vector2(0.75,0.79), "prop":Vector2(0.59,0.30), "origin":Vector2(0.42,0.77), "origin_bone":"Head"},
	"boss_lead_plate": {"kind":"guillotine", "effect":"press", "release":0.48, "length":1.24, "head":Vector2(0.50,0.42), "left":Vector2(0.18,0.54), "right":Vector2(0.82,0.54), "prop":Vector2(0.50,0.44), "origin":Vector2(0.50,0.67), "origin_bone":"Detail"},
	"boss_word_demon": {"kind":"serpent", "effect":"serpent", "release":0.38, "length":1.08, "head":Vector2(0.26,0.22), "left":Vector2(0.38,0.49), "right":Vector2(0.70,0.68), "prop":Vector2(0.69,0.75), "origin":Vector2(0.08,0.16), "origin_bone":"Head"},
	"boss_chaos_press": {"kind":"maw", "effect":"maw", "release":0.42, "length":1.16, "head":Vector2(0.50,0.35), "left":Vector2(0.40,0.30), "right":Vector2(0.43,0.65), "prop":Vector2(0.53,0.48), "origin":Vector2(0.24,0.47), "origin_bone":"LimbL"},
	"blank_child": {"kind":"robe", "effect":"paper", "release":0.36, "length":0.98, "head":Vector2(0.48,0.24), "left":Vector2(0.30,0.43), "right":Vector2(0.65,0.44), "prop":Vector2(0.51,0.78)},
	"corrosion_beetle": {"kind":"beetle", "effect":"serpent", "release":0.28, "length":0.82, "head":Vector2(0.23,0.53), "left":Vector2(0.35,0.66), "right":Vector2(0.66,0.66), "prop":Vector2(0.68,0.40)},
	"glutton": {"kind":"jaw", "effect":"maw", "release":0.38, "length":1.08, "head":Vector2(0.31,0.32), "left":Vector2(0.23,0.65), "right":Vector2(0.53,0.67), "prop":Vector2(0.38,0.53)},
	"furnace_beast": {"kind":"furnace", "effect":"ember", "release":0.40, "length":1.10, "head":Vector2(0.38,0.26), "left":Vector2(0.20,0.51), "right":Vector2(0.77,0.50), "prop":Vector2(0.48,0.66)},
	"charge_badger": {"kind":"badger", "effect":"arc", "release":0.30, "length":0.94, "head":Vector2(0.28,0.49), "left":Vector2(0.24,0.73), "right":Vector2(0.59,0.73), "prop":Vector2(0.58,0.28)},
	"ink_creditor": {"kind":"debt", "effect":"paper", "release":0.36, "length":1.02, "head":Vector2(0.62,0.29), "left":Vector2(0.22,0.40), "right":Vector2(0.77,0.69), "prop":Vector2(0.76,0.45)},
	"double_slip": {"kind":"slips", "effect":"paper", "release":0.34, "length":0.98, "head":Vector2(0.50,0.45), "left":Vector2(0.40,0.50), "right":Vector2(0.65,0.48), "prop":Vector2(0.52,0.48)},
	"nest_moth": {"kind":"moth", "effect":"paper", "release":0.30, "length":0.96, "head":Vector2(0.28,0.68), "left":Vector2(0.28,0.56), "right":Vector2(0.64,0.60), "prop":Vector2(0.50,0.30)},
	"bomb_press": {"kind":"press", "effect":"press", "release":0.44, "length":1.16, "head":Vector2(0.53,0.46), "left":Vector2(0.33,0.41), "right":Vector2(0.57,0.42), "prop":Vector2(0.80,0.36)},
	"copy_master": {"kind":"stone", "effect":"brush", "release":0.38, "length":1.04, "head":Vector2(0.55,0.30), "left":Vector2(0.22,0.43), "right":Vector2(0.86,0.43), "prop":Vector2(0.53,0.52)},
	"seal_officer": {"kind":"edict", "effect":"seal", "release":0.42, "length":1.12, "head":Vector2(0.45,0.22), "left":Vector2(0.20,0.30), "right":Vector2(0.78,0.25), "prop":Vector2(0.45,0.60)},
	"wheel_master": {"kind":"roller", "effect":"press", "release":0.40, "length":1.12, "head":Vector2(0.55,0.40), "left":Vector2(0.18,0.34), "right":Vector2(0.83,0.52), "prop":Vector2(0.63,0.49)},
	"leech": {"kind":"leech", "effect":"arc", "release":0.34, "length":0.96, "head":Vector2(0.25,0.30), "left":Vector2(0.34,0.49), "right":Vector2(0.67,0.66), "prop":Vector2(0.73,0.69)},
	"proof_boss": {"kind":"tribunal", "effect":"brush", "release":0.46, "length":1.20, "head":Vector2(0.40,0.33), "left":Vector2(0.14,0.19), "right":Vector2(0.75,0.27), "prop":Vector2(0.76,0.23)},
	"rail_boss": {"kind":"rail", "effect":"press", "release":0.52, "length":1.36, "head":Vector2(0.50,0.43), "left":Vector2(0.27,0.49), "right":Vector2(0.76,0.49), "prop":Vector2(0.49,0.36)},
	"compiler_boss": {"kind":"archive", "effect":"paper", "release":0.50, "length":1.30, "head":Vector2(0.50,0.19), "left":Vector2(0.27,0.34), "right":Vector2(0.78,0.30), "prop":Vector2(0.55,0.35)},
}


static func profile(id: String) -> Dictionary:
	if DATA.has(id): return DATA[id]
	return {"kind":"robe","effect":EnemyAttackProfiles.get_profile(id).get("effect","paper"),"release":0.36,"length":1.0,"head":Vector2(0.40,0.30),"left":Vector2(0.25,0.58),"right":Vector2(0.75,0.58),"prop":Vector2(0.51,0.65)}


static func zones(p: Dictionary) -> Dictionary:
	var z := {
		"Head": [p.head, Rect2(p.head - Vector2(0.20,0.23),Vector2(0.40,0.36))],
		"LimbL": [p.left, Rect2(p.left - Vector2(0.24,0.06),Vector2(0.27,0.34))],
		"LimbR": [p.right, Rect2(p.right - Vector2(0.03,0.06),Vector2(0.27,0.34))],
		"Detail": [p.prop, Rect2(p.prop - Vector2(0.17,0.10),Vector2(0.34,0.26))],
		"HemL": [Vector2(0.34,0.72),Rect2(0.07,0.75,0.36,0.25)],
		"HemR": [Vector2(0.67,0.72),Rect2(0.57,0.75,0.36,0.25)],
	}
	if p.kind in OBJECT_KINDS:
		# Rigid books, stone, metal and furniture stay on Body; articulate only
		# the exposed paper, ink tethers, floating brush and archive bands.
		for id in z: z[id][1] = Rect2()
		match p.kind:
			"debt":
				z.LimbL[1] = Rect2(-0.03,0.27,0.31,0.53)
				z.LimbR[1] = Rect2(0.59,0.63,0.42,0.40)
			"stone":
				z.LimbL[1] = Rect2(-0.02,0.32,0.28,0.33)
				z.LimbR[1] = Rect2(0.80,0.35,0.22,0.40)
			"edict":
				z.LimbL[1] = Rect2(0.06,0.18,0.23,0.22)
				z.LimbR[1] = Rect2(0.70,0.10,0.26,0.30)
				z.HemL[1] = Rect2(0.30,0.78,0.24,0.24)
				z.HemR[1] = Rect2(0.55,0.78,0.42,0.24)
			"roller": z.LimbL[1] = Rect2(-0.02,-0.02,0.27,0.48)
			"tribunal":
				z.LimbL[1] = Rect2(-0.03,0.0,0.28,0.29)
				z.Detail[1] = Rect2(0.57,-0.05,0.46,0.43)
			"archive":
				z.Head[1] = Rect2(0.08,-0.04,0.88,0.34)
				z.LimbL[1] = Rect2(-0.02,0.15,0.40,0.55)
				z.LimbR[1] = Rect2(0.73,0.19,0.29,0.38)
				z.HemL[1] = Rect2(0.18,0.70,0.42,0.32)
				z.HemR[1] = Rect2(0.60,0.65,0.37,0.37)
			"guillotine": z.Detail[1] = Rect2(0.21,0.25,0.59,0.38)
		return z
	match p.kind:
		"crane":
			z.Head[1] = Rect2(-0.03,-0.02,0.53,0.61)
			z.LimbL[1] = Rect2(0.48,-0.02,0.52,0.39)
			z.LimbR[1] = Rect2(0.55,0.31,0.48,0.64)
			for id in ["Detail","HemL","HemR"]: z[id][1] = Rect2()
		"seal_beast":
			z.Head[1] = Rect2(-0.02,0.03,0.48,0.52)
			z.Detail[1] = Rect2()
			for id in ["HemL","HemR"]: z[id][1] = Rect2()
		"fan":
			z.Head[1] = Rect2(0.43,-0.03,0.45,0.36)
			z.LimbL[1] = Rect2(-0.03,0.22,0.52,0.53)
			z.LimbR[1] = Rect2(0.67,0.30,0.32,0.38)
			z.Detail[1] = Rect2(0.44,0.53,0.48,0.39)
		"brush_beetle":
			z.Head[1] = Rect2(-0.02,0.29,0.47,0.58)
			z.LimbL[1] = Rect2(0.35,0.57,0.28,0.40)
			z.LimbR[1] = Rect2(0.70,0.49,0.30,0.44)
			for id in ["Detail","HemL","HemR"]: z[id][1] = Rect2()
		"imp":
			z.Head[1] = Rect2(0.23,0.47,0.46,0.44)
			z.Detail[1] = Rect2(0.29,-0.03,0.62,0.50)
			for id in ["HemL","HemR"]: z[id][1] = Rect2()
		"serpent":
			z.Head[1] = Rect2(0.01,-0.02,0.49,0.41)
			z.Detail[1] = Rect2(0.50,0.54,0.49,0.44)
			for id in ["HemL","HemR"]: z[id][1] = Rect2()
		"maw":
			z.Head[1] = Rect2()
			z.LimbL[1] = Rect2(0.14,0.02,0.76,0.42)
			z.LimbR[1] = Rect2(0.12,0.54,0.76,0.43)
			for id in ["Detail","HemL","HemR"]: z[id][1] = Rect2()
		"rubbing":
			# Keep the broad ox horns on the same joint as the bronze mask.
			z.Head[1] = Rect2(0.29,-0.05,0.51,0.44)
		"slips":
			z.Head[1] = Rect2()
			z.LimbL[1] = Rect2(0.05,0.02,0.43,0.92)
			z.LimbR[1] = Rect2(0.55,0.02,0.43,0.92)
			z.Detail[1] = Rect2()
		"press", "rail":
			z.Head[1] = Rect2()
			z.Detail[1] = Rect2(0.08,0.08,0.85,0.50) if p.kind == "rail" else Rect2(0.66,0.12,0.32,0.47)
			z.LimbL[1] = Rect2(0.02,0.30,0.32,0.41)
			z.LimbR[1] = Rect2(0.32,0.30,0.26,0.40)
			if p.kind == "rail":
				z.Detail[1] = Rect2(0.40,0.10,0.35,0.46)
				for id in ["LimbL","LimbR","HemL","HemR"]: z[id][1] = Rect2()
		"moth":
			z.LimbL[1] = Rect2(0.00,0.26,0.33,0.42)
			z.LimbR[1] = Rect2(0.49,0.34,0.51,0.41)
			z.Detail[1] = Rect2(0.15,0.02,0.64,0.44)
		"leech":
			z.Head[1] = Rect2(0.00,0.03,0.42,0.46)
			z.LimbL[1] = Rect2(0.15,0.30,0.40,0.34)
			z.Detail[1] = Rect2(0.50,0.45,0.47,0.45)
		"scrolls":
			# Include both swept-back dragon antlers and the hanging bronze whiskers.
			z.Head[1] = Rect2(0.30,-0.06,0.39,0.39)
			# Include the fingers over the top rollers so the hands travel with paper.
			z.LimbL[1] = Rect2(0.00,0.18,0.39,0.80)
			z.LimbR[1] = Rect2(0.61,0.24,0.39,0.74)
			z.Detail[1] = Rect2()
		"seal":
			# Hand, seal handle and seal face form one connected moving assembly.
			z.LimbL[1] = Rect2(0.03,0.18,0.37,0.48)
			z.Detail[1] = Rect2()
		"official":
			# The desk stays rigid while face, slip and brush arm articulate above it.
			z.LimbL[1] = Rect2(0.14,0.12,0.25,0.36)
			z.LimbR[1] = Rect2(0.62,0.20,0.22,0.28)
			for id in ["Detail","HemL","HemR"]: z[id][1] = Rect2()
	return z
