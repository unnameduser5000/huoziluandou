extends RefCounted
## Anticipation, strike, follow-through and recovery on the current illustration.
## Offsets are normalized; rigid scenery stays on Body while exposed parts articulate.
const MOTIONS := {
	# body strike, head angle, left/right articulation, detail, head thrust
	"seal_beast": [Vector2(-0.040,0.018), -0.075, -0.06, 0.04, 0.0, Vector2(-0.022,0.013)],
	"crane": [Vector2(-0.025,0.0), -0.045, -0.10, 0.12, 0.0, Vector2(-0.045,0.008)],
	"fan": [Vector2(-0.024,0.0), -0.035, -0.14, 0.08, 0.045, Vector2(-0.005,0.0)],
	"brush_beetle": [Vector2(-0.044,0.006), -0.045, -0.10, 0.06, 0.0, Vector2(-0.035,0.008)],
	"imp": [Vector2(-0.070,0.014), 0.07, -0.15, 0.12, -0.12, Vector2(-0.012,0.010)],
	"guillotine": [Vector2.ZERO, 0.0, 0.0, 0.0, 0.0, Vector2.ZERO],
	"serpent": [Vector2(-0.028,0.0), -0.09, 0.055, -0.04, 0.04, Vector2(-0.044,-0.006)],
	"maw": [Vector2(-0.032,0.006), 0.0, 0.045, -0.045, 0.0, Vector2.ZERO],
	"robe": [Vector2(-0.018,0.0), -0.035, -0.12, 0.15, 0.025, Vector2.ZERO],
	"beetle": [Vector2(-0.047,0.004), -0.05, -0.10, 0.075, -0.02, Vector2(-0.014,0.006)],
	"jaw": [Vector2(-0.034,0.014), -0.055, 0.06, -0.06, -0.09, Vector2(-0.024,0.006)],
	"furnace": [Vector2(-0.025,0.010), -0.04, -0.12, 0.10, 0.025, Vector2.ZERO],
	"badger": [Vector2(-0.060,0.010), -0.065, -0.14, -0.09, -0.06, Vector2(-0.010,0.0)],
	"debt": [Vector2(-0.008,0.0), 0.0, 0.08, -0.09, 0.0, Vector2.ZERO],
	"slips": [Vector2(-0.018,0.0), 0.0, -0.11, 0.11, 0.0, Vector2.ZERO],
	"moth": [Vector2(-0.045,-0.025), -0.04, 0.16, -0.16, 0.04, Vector2(-0.013,0.0)],
	"press": [Vector2(-0.010,0.012), 0.0, -0.08, -0.10, -0.10, Vector2.ZERO],
	"stone": [Vector2.ZERO, 0.0, -0.045, -0.07, 0.0, Vector2.ZERO],
	"edict": [Vector2.ZERO, 0.0, -0.035, 0.035, 0.0, Vector2.ZERO],
	"roller": [Vector2(-0.028,0.0), 0.0, -0.06, 0.0, 0.0, Vector2.ZERO],
	"leech": [Vector2(-0.022,0.0), -0.04, -0.04, 0.025, 0.015, Vector2(-0.045,-0.012)],
	"tribunal": [Vector2.ZERO, 0.0, -0.06, 0.0, -0.12, Vector2.ZERO],
	"rail": [Vector2.ZERO, 0.0, 0.0, 0.0, 0.0, Vector2.ZERO],
	"archive": [Vector2.ZERO, 0.0, -0.065, 0.065, 0.0, Vector2.ZERO],
}


static func build(actor: Node2D, action: String) -> Animation:
	var kind: String = actor.profile.kind
	var motion: Array = MOTIONS[kind]
	var fast := 0.76 if action == "followup" else 1.0
	var clip := Animation.new()
	clip.length = float(actor.profile.length) * fast
	var impact := float(actor.profile.release) * fast
	var times := [0.0, impact * 0.60, impact * 0.86, impact, impact + 0.09 * fast, clip.length * 0.80, clip.length]
	var forward: Vector2 = motion[0]
	var windup := -forward * 0.45
	if kind == "imp": windup += Vector2(0,-0.045)
	if kind == "badger": windup += Vector2(0,0.012)
	if kind == "moth": windup += Vector2(0,-0.018)
	actor._shift(clip,"Body",times,[Vector2.ZERO,windup,windup*0.55,forward,forward*0.90,-forward*0.10,Vector2.ZERO])
	for entry in [["Head",motion[1]], ["LimbL",motion[2]], ["LimbR",motion[3]], ["Detail",motion[4]]]:
		var angle: float = entry[1]
		# Left/right limbs overlap their recovery so each blow has a clear follow-through.
		if action == "followup" and entry[0] in ["LimbL","LimbR"]: angle *= -0.80 if kind in ["imp","robe","moth","slips"] else 0.85
		actor._rotation(clip,entry[0],times,[0.0,-angle*0.55,-angle*0.32,angle,angle*1.08,angle*0.15,0.0])
	var thrust: Vector2 = motion[5]
	actor._shift(clip,"Head",times,[Vector2.ZERO,-thrust*0.4,-thrust*0.2,thrust,thrust*0.85,thrust*0.1,Vector2.ZERO])
	var sway := 0.025 if kind in ["robe","fan","moth","archive"] else 0.0
	actor._rotation(clip,"HemL",times,[0.0,-sway,-sway*0.5,sway,sway*1.2,sway*0.2,0.0])
	actor._rotation(clip,"HemR",times,[0.0,sway,sway*0.5,-sway,-sway*1.2,-sway*0.2,0.0])
	match kind:
		"guillotine": _stroke(actor,clip,"Detail",times,Vector2(0,0.055),Vector2(0,-0.030))
		"rail": _stroke(actor,clip,"Detail",times,Vector2(0,0.055),Vector2(0,-0.030))
		"press": _stroke(actor,clip,"LimbL",times,Vector2(0,0.045),Vector2(0,-0.026))
		"edict":
			actor._shift(clip,"Body",times,[Vector2.ZERO,Vector2(0,-0.022),Vector2(0,-0.012),Vector2(0,0.042),Vector2(0,0.036),Vector2(0,-0.004),Vector2.ZERO])
		"maw":
			_stroke(actor,clip,"LimbL",times,Vector2(0,0.012),Vector2(0,-0.015))
			_stroke(actor,clip,"LimbR",times,Vector2(0,-0.012),Vector2(0,0.015))
		"slips":
			_stroke(actor,clip,"LimbL",times,Vector2(0.014,0),Vector2(-0.012,0))
			_stroke(actor,clip,"LimbR",times,Vector2(-0.014,0),Vector2(0.012,0))
		"debt":
			_stroke(actor,clip,"LimbL",times,Vector2(-0.028,0.015),Vector2(0.010,-0.008))
			_stroke(actor,clip,"LimbR",times,Vector2(-0.022,-0.010),Vector2(0.008,0.008))
		"stone": _stroke(actor,clip,"LimbR",times,Vector2(-0.035,0.012),Vector2(0.015,-0.007))
		"roller": _stroke(actor,clip,"LimbL",times,Vector2(-0.035,0.015),Vector2(0.016,-0.010))
		"tribunal": _stroke(actor,clip,"Detail",times,Vector2(-0.028,0.035),Vector2(0.015,-0.020))
		"archive":
			_stroke(actor,clip,"LimbL",times,Vector2(-0.018,0.012),Vector2(0.010,-0.006))
			_stroke(actor,clip,"LimbR",times,Vector2(-0.018,-0.012),Vector2(0.010,0.006))
	return clip


static func _stroke(actor: Node2D, clip: Animation, bone: String, times: Array, strike: Vector2, lift: Vector2) -> void:
	actor._shift(clip,bone,times,[Vector2.ZERO,lift,lift*0.65,strike,strike*0.9,strike*0.12,Vector2.ZERO])
