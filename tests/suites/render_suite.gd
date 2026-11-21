class_name RenderSuite
extends SmokeSuite
## Resolution governor: the arithmetic over the window size and the state
## machine over frame times. Neither needs a GPU.

## The resolution governor is arithmetic over the window size plus a state machine
## over frame times. Both are tested here: neither needs a GPU, and the state machine
## is the part that can be wrong without anything looking wrong.
func _test_render_scale() -> void:
	_check(
		RenderScale.scale_for(Vector2i(1280, 720)) == 1.0,
		"a 720p window renders at its own resolution"
	)
	_check(
		RenderScale.scale_for(Vector2i(1600, 900)) == 1.0,
		"a window at the cap is not scaled at all"
	)
	_check(
		is_equal_approx(RenderScale.scale_for(Vector2i(2560, 1440)), 1600.0 / 2560.0),
		"a 1440p window renders 1600 pixels wide"
	)
	_check(
		RenderScale.render_width_for(Vector2i(3200, 1800)) == 1600,
		"a 1800p window renders 1600 pixels wide too"
	)
	_check(
		RenderScale.render_width_for(Vector2i(3840, 2160)) == 1600,
		"a 4K window is capped at 1600 rather than left at its own size"
	)
	_check(
		RenderScale.render_width_for(Vector2i(800, 450)) == 800,
		"a window narrower than the floor is never upscaled"
	)
	_check(
		RenderScale.scale_for(Vector2i(0, 0)) == 1.0,
		"a window that has not been sized yet is not scaled"
	)
	_check(
		RenderScale.render_width_for(Vector2i(1280, 720), 0.5) == 640,
		"the softest rung renders half of a 720p window"
	)
	for factor in RenderScale.FACTORS:
		_check(
			RenderScale.render_width_for(Vector2i(1280, 720), factor)
				>= RenderScale.MIN_RENDER_WIDTH,
			"no rung goes under the floor (%.2f)" % factor
		)

	_test_render_governor()


## The governor's decision, driven by a simulated GPU rather than the real one. The
## model is a cost per pixel, so lowering a rung makes the frame faster the way it
## really does, and the vsync quantisation is applied because that is the signal the
## governor reads.
func _test_render_governor() -> void:
	var governor: Node = load("res://common/render_scale.gd").new()
	get_tree().current_scene.add_child(governor)
	# The real node drives itself from the frame loop; this one is driven by hand.
	governor.set_process(false)
	governor.set("enabled", true)

	_simulate(governor, 1.0, 8.0)
	_check(
		int(governor.get("_factor")) == 0,
		"a machine that holds 60 fps is left at full quality"
	)

	var hitched: Node = _fresh_governor()
	_simulate(hitched, 1.0, 10.0, 20)
	_check(
		int(hitched.get("_factor")) == 0,
		"one bad frame in twenty is not a reason to soften the image"
	)

	_simulate(governor, 4.0, 14.0)
	_check(
		int(governor.get("_factor")) > 0,
		"a machine four times slower steps down the ladder"
	)
	var settled: int = int(governor.get("_factor"))
	_check(
		is_equal_approx(governor.call("current_factor"), RenderScale.FACTORS[settled]),
		"and it sits on a rung of the ladder, not between two"
	)

	_simulate(governor, 1.0, 40.0)
	_check(
		int(governor.get("_factor")) == 0,
		"and it climbs back to full quality once the frames are cheap again"
	)

	var floored: Node = _fresh_governor()
	_simulate(floored, 40.0, 40.0)
	_check(
		int(floored.get("_factor")) == RenderScale.FACTORS.size() - 1,
		"a machine that can never keep up lands on the floor"
	)


