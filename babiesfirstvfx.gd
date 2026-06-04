extends Node3D

signal finished

@onready var particles: GPUParticles3D = $GPUParticles3D

func play() -> void:
	particles.restart()
	await particles.finished
	finished.emit()
