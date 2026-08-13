extends SceneTree

const SimInfection = preload("res://sim/modules/infection.gd")

func _init() -> void:
	assert(SimInfection.Stage.Latent == 0, "Latent 0")
	assert(SimInfection.Stage.Onset == 1, "Onset 1")
	assert(SimInfection.Stage.Progression == 2, "Progression 2")
	assert(SimInfection.Stage.Critical == 3, "Critical 3")
	assert(SimInfection.Stage.Turned == 4, "Turned 4")
	assert(SimInfection.LATENT_TICKS == 864000, "LATENT 12h")
	assert(SimInfection.ONSET_TICKS_MIN == 864000, "ONSET_MIN 12h")
	assert(SimInfection.ONSET_TICKS_MAX == 1728000, "ONSET_MAX 24h")
	assert(SimInfection.PROGRESSION_TICKS == 1728000, "PROGRESSION 24h")
	assert(SimInfection.CRITICAL_TICKS == 864000, "CRITICAL 12h")
	assert(SimInfection.stage_duration_ticks(SimInfection.Stage.Latent) == 864000)
	assert(SimInfection.stage_duration_ticks(SimInfection.Stage.Progression) == 1728000)
	assert(SimInfection.stage_duration_ticks(SimInfection.Stage.Turned) == 0)
	print("M2_INFECTION_STAGE_OK")
	quit(0)
