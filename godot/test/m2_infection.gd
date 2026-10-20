extends SceneTree

const SimInfection = preload("res://sim/modules/infection.gd")

func _init() -> void:
	assert(SimInfection.Stage.Latent == 0, "Latent 0")
	assert(SimInfection.Stage.Onset == 1, "Onset 1")
	assert(SimInfection.Stage.Progression == 2, "Progression 2")
	assert(SimInfection.Stage.Critical == 3, "Critical 3")
	assert(SimInfection.Stage.Turned == 4, "Turned 4")
	assert(SimInfection.LATENT_TICKS == 36000, "LATENT 12 in-game h")
	assert(SimInfection.ONSET_TICKS_MIN == 36000, "ONSET_MIN 12 in-game h")
	assert(SimInfection.ONSET_TICKS_MAX == 72000, "ONSET_MAX 24 in-game h")
	assert(SimInfection.PROGRESSION_TICKS == 72000, "PROGRESSION 24 in-game h")
	assert(SimInfection.CRITICAL_TICKS == 36000, "CRITICAL 12 in-game h")
	assert(SimInfection.stage_duration_ticks(SimInfection.Stage.Latent) == 36000)
	assert(SimInfection.stage_duration_ticks(SimInfection.Stage.Progression) == 72000)
	assert(SimInfection.stage_duration_ticks(SimInfection.Stage.Turned) == 0)
	print("M2_INFECTION_STAGE_OK")
	quit(0)
