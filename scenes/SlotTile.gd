extends Node2D
class_name SlotTile

signal move_completed

var size := Vector2.ZERO
var speed :float = 1.0

func _ready():
	pass

func set_texture(tex):
	$Sprite2D.texture = tex
	if size != Vector2.ZERO:
		$Sprite2D.scale = size / tex.get_size()

func set_size(new_size: Vector2):
	size = new_size
	if $Sprite2D.texture != null:
		$Sprite2D.scale = size / $Sprite2D.texture.get_size()

func set_velocity(new_speed):
	speed = new_speed

func move_to(to: Vector2):
	var tween = create_tween()
	tween.set_speed_scale(speed)
	tween.tween_property(self, "position", to, 1.0).set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT)
	tween.finished.connect(_on_tween_finished)

func _on_tween_finished():
	emit_signal("move_completed")

func move_by(by: Vector2):
	move_to(position + by)

func spin_up():
	$Animations.play('SPIN_UP')

func spin_down():
	$Animations.play('SPIN_DOWN')
