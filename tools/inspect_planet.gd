extends Node
## Dumps the baked planet field to PNGs so it can be inspected without a camera.
##
##     ./run.sh --headless tools/inspect_planet.tscn
##
## Writes `/tmp/planet_channel_*.png` (one image per channel, all six faces in a
## 3x2 grid) and `/tmp/planet_elev_*.png` (elevation as a signed false colour).

const FIELD: String = "res://levels/arena/planet_field.res"
const N: int = 512
const COLUMNS: int = 3
const ROWS: int = 2


func _ready() -> void:
	var field: Resource = load(FIELD)
	if field == null:
		print("no field at ", FIELD)
		get_tree().quit()
		return

	var faces: Array = field.faces
	print("faces: ", faces.size(), "  relief_units: ", field.relief_units, "  river max: ", field.river_max_distance)

	var stats: Array[String] = ["R", "G", "B", "A"]
	for channel in 4:
		var low: float = INF
		var high: float = -INF
		var total: float = 0.0
		var count: float = 0.0
		for face in faces:
			var image: Image = face
			for j in N:
				for i in N:
					var value: float = image.get_pixel(i, j)[channel]
					low = minf(low, value)
					high = maxf(high, value)
					total += value
					count += 1.0
		print("  %s  min %.4f  max %.4f  mean %.4f" % [stats[channel], low, high, total / count])

	# Elevation histogram. The interesting question is not the range but how much
	# of the land sits in each band: a field whose land is all at 0.2 has no
	# mountains, whatever its maximum says.
	var land_bins: PackedInt32Array = PackedInt32Array()
	land_bins.resize(10)
	land_bins.fill(0)
	var land: int = 0
	var water: int = 0
	for face in faces:
		var image: Image = face
		for j in N:
			for i in N:
				var e: float = image.get_pixel(i, j).r
				if e <= 0.0:
					water += 1
					continue
				land += 1
				land_bins[clampi(int(e * 10.0), 0, 9)] += 1
	print("  land %.1f%%  water %.1f%%" % [
		100.0 * float(land) / float(land + water), 100.0 * float(water) / float(land + water)
	])
	var line: String = "  land by elevation band: "
	for b in 10:
		line += "%.2f-%0.2f %.1f%%  " % [float(b) * 0.1, float(b + 1) * 0.1, 100.0 * float(land_bins[b]) / maxf(float(land), 1.0)]
	print(line)

	for channel in 4:
		var sheet: Image = Image.create_empty(N * COLUMNS, N * ROWS, false, Image.FORMAT_RGB8)
		for f in faces.size():
			var image: Image = faces[f]
			var ox: int = (f % COLUMNS) * N
			var oy: int = (f / COLUMNS) * N
			for j in N:
				for i in N:
					var value: float = image.get_pixel(i, j)[channel]
					sheet.set_pixel(ox + i, oy + j, Color(value, value, value))
		sheet.save_png("/tmp/planet_channel_%d.png" % channel)

	# Signed elevation as a colour ramp, so the sea floor and the peaks are told
	# apart in one look.
	var relief: Image = Image.create_empty(N * COLUMNS, N * ROWS, false, Image.FORMAT_RGB8)
	for f in faces.size():
		var image: Image = faces[f]
		var ox: int = (f % COLUMNS) * N
		var oy: int = (f / COLUMNS) * N
		for j in N:
			for i in N:
				var e: float = image.get_pixel(i, j).r
				var colour: Color
				if e <= 0.0:
					colour = Color(0.0, 0.0, 0.10 + -e * 0.9)
				else:
					colour = Color(0.25 + e * 0.75, 0.55 + e * 0.45, 0.25 + e * 0.20)
				relief.set_pixel(ox + i, oy + j, colour)
	relief.save_png("/tmp/planet_relief.png")
	print("wrote /tmp/planet_channel_0..3.png and /tmp/planet_relief.png")
	get_tree().quit()
