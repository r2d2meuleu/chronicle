extends ChronicleTestSuite

const BuiltinTypes := preload("res://addons/chronicle/core/serialization/builtin_types.gd")

var _registry: ChronicleTypeRegistry
var _codec: ChronicleTypeCodec


func before_each() -> void:
	super.before_each()
	_registry = ChronicleTypeRegistry.new()
	_codec = ChronicleTypeCodec.new(_registry)
	BuiltinTypes.register_all(_registry, _codec)


# Vector2 set/get roundtrip preserves value and type
func test_vector2_set_get_roundtrip() -> void:
	_chronicle.set_fact("player.position", Vector2(100.5, 200.75))
	var val: Variant = _chronicle.get_fact("player.position")
	assert_true(val is Vector2, "should be Vector2")
	assert_eq(val, Vector2(100.5, 200.75))


# Vector2i set/get roundtrip preserves integer components
func test_vector2i_set_get_roundtrip() -> void:
	_chronicle.set_fact("grid.cell", Vector2i(3, 7))
	var val: Variant = _chronicle.get_fact("grid.cell")
	assert_true(val is Vector2i, "should be Vector2i")
	assert_eq(val, Vector2i(3, 7))


# Vector3 set/get roundtrip
func test_vector3_set_get_roundtrip() -> void:
	_chronicle.set_fact("player.position3d", Vector3(1.5, 2.5, 3.5))
	var val: Variant = _chronicle.get_fact("player.position3d")
	assert_true(val is Vector3, "should be Vector3")
	assert_eq(val, Vector3(1.5, 2.5, 3.5))


# Vector3i set/get roundtrip
func test_vector3i_set_get_roundtrip() -> void:
	_chronicle.set_fact("grid.cell3d", Vector3i(1, 2, 3))
	var val: Variant = _chronicle.get_fact("grid.cell3d")
	assert_true(val is Vector3i, "should be Vector3i")
	assert_eq(val, Vector3i(1, 2, 3))


# Vector4 set/get roundtrip
func test_vector4_set_get_roundtrip() -> void:
	_chronicle.set_fact("shader.params", Vector4(0.1, 0.2, 0.3, 0.4))
	var val: Variant = _chronicle.get_fact("shader.params")
	assert_true(val is Vector4, "should be Vector4")
	assert_eq(val, Vector4(0.1, 0.2, 0.3, 0.4))


# Vector4i set/get roundtrip
func test_vector4i_set_get_roundtrip() -> void:
	_chronicle.set_fact("tile.corners", Vector4i(1, 2, 3, 4))
	var val: Variant = _chronicle.get_fact("tile.corners")
	assert_true(val is Vector4i, "should be Vector4i")
	assert_eq(val, Vector4i(1, 2, 3, 4))


# Color set/get roundtrip
func test_color_set_get_roundtrip() -> void:
	_chronicle.set_fact("ui.tint", Color(1.0, 0.5, 0.0, 0.8))
	var val: Variant = _chronicle.get_fact("ui.tint")
	assert_true(val is Color, "should be Color")
	assert_eq(val, Color(1.0, 0.5, 0.0, 0.8))


# Quaternion set/get roundtrip
func test_quaternion_set_get_roundtrip() -> void:
	_chronicle.set_fact("camera.rotation", Quaternion(0.0, 0.707, 0.0, 0.707))
	var val: Variant = _chronicle.get_fact("camera.rotation")
	assert_true(val is Quaternion, "should be Quaternion")
	assert_eq(val, Quaternion(0.0, 0.707, 0.0, 0.707))


# prepare_for_json produces correct tagged dict for Vector2
func test_prepare_for_json_vector2_format() -> void:
	var result: Variant = _codec.encode_value(Vector2(1.5, 2.5))
	assert_true(result is Dictionary)
	assert_eq(result["_chronicle_type"], "Vector2")
	assert_eq(result["x"], 1.5)
	assert_eq(result["y"], 2.5)


# prepare_for_json produces correct tagged dict for Color
func test_prepare_for_json_color_format() -> void:
	var result: Variant = _codec.encode_value(Color(0.75, 0.5, 0.25, 0.125))
	assert_true(result is Dictionary)
	assert_eq(result["_chronicle_type"], "Color")
	assert_eq(result["r"], 0.75)
	assert_eq(result["g"], 0.5)
	assert_eq(result["b"], 0.25)
	assert_eq(result["a"], 0.125)


# restore_from_json reconstructs Vector2 from tagged dict
func test_restore_from_json_vector2() -> void:
	var tagged: Dictionary = {"_chronicle_type": "Vector2", "x": 1.0, "y": 2.0}
	var result: Variant = _codec.decode_value(tagged)
	assert_true(result is Vector2, "should reconstruct to Vector2")
	assert_eq(result, Vector2(1.0, 2.0))


# restore_from_json reconstructs Vector2i with int components
func test_restore_from_json_vector2i_int_components() -> void:
	var tagged: Dictionary = {"_chronicle_type": "Vector2i", "x": 3.0, "y": 7.0}
	var result: Variant = _codec.decode_value(tagged)
	assert_true(result is Vector2i, "should reconstruct to Vector2i")
	assert_eq(result, Vector2i(3, 7))


# restore_from_json int restoration still works for plain floats
func test_restore_from_json_int_restoration() -> void:
	var data: Dictionary = {"gold": 500.0, "name": "hero", "ratio": 3.14}
	var result: Variant = _codec.decode_value(data)
	assert_eq(result["gold"], 500)
	assert_eq(typeof(result["gold"]), TYPE_INT)
	assert_eq(result["name"], "hero")
	assert_eq(result["ratio"], 3.14)
	assert_eq(typeof(result["ratio"]), TYPE_FLOAT)


# Deep copy isolation — mutating returned Vector2 does not affect store
func test_deep_copy_vector2_isolation() -> void:
	_chronicle.set_fact("player.pos", Vector2(10.0, 20.0))
	var val: Variant = _chronicle.get_fact("player.pos")
	val.x = 999.0
	assert_fact("player.pos", Vector2(10.0, 20.0))


# Value type inside Array roundtrips correctly
func test_array_of_vectors_set_get() -> void:
	var waypoints: Array = [Vector2(0, 0), Vector2(10, 5), Vector2(20, 0)]
	_chronicle.set_fact("path.waypoints", waypoints)
	var val: Variant = _chronicle.get_fact("path.waypoints")
	assert_true(val is Array)
	assert_eq(val.size(), 3)
	assert_true(val[0] is Vector2)
	assert_eq(val[0], Vector2(0, 0))
	assert_eq(val[1], Vector2(10, 5))
	assert_eq(val[2], Vector2(20, 0))


# Value type inside Dictionary roundtrips correctly
func test_dict_with_vector_values_set_get() -> void:
	var data: Dictionary = {"spawn": Vector3(1, 2, 3), "target": Vector3(4, 5, 6)}
	_chronicle.set_fact("level.points", data)
	var val: Variant = _chronicle.get_fact("level.points")
	assert_true(val is Dictionary)
	assert_true(val["spawn"] is Vector3)
	assert_eq(val["spawn"], Vector3(1, 2, 3))
	assert_eq(val["target"], Vector3(4, 5, 6))


# prepare_for_json recurses into arrays containing vectors
func test_prepare_for_json_array_of_vectors() -> void:
	var input: Array = [Vector2(1.5, 2.5), Vector2(3.5, 4.5)]
	var result: Variant = _codec.encode_value(input)
	assert_true(result is Array)
	assert_true(result[0] is Dictionary)
	assert_eq(result[0]["_chronicle_type"], "Vector2")
	assert_eq(result[0]["x"], 1.5)


# _chronicle_type collision — unknown type tag returns null (fact dropped)
func test_chronicle_type_collision_unknown_type() -> void:
	var raw: Dictionary = {"_chronicle_type": "FakeType", "x": 1.0, "y": 2.0}
	var result: Variant = _codec.decode_value(raw)
	assert_null(result, "unknown type tag should return null so the fact is dropped")


# _chronicle_type collision — known type but missing required keys returns null
func test_chronicle_type_collision_missing_keys() -> void:
	var raw: Dictionary = {"_chronicle_type": "Vector2", "x": 1.0}
	var result: Variant = _codec.decode_value(raw)
	assert_null(result, "missing required key should return null so fact is dropped")


# Rect2 set/get roundtrip
func test_rect2_set_get_roundtrip() -> void:
	_chronicle.set_fact("ui.bounds", Rect2(10, 20, 100, 50))
	var val: Variant = _chronicle.get_fact("ui.bounds")
	assert_true(val is Rect2, "should be Rect2")
	assert_eq(val, Rect2(10, 20, 100, 50))


# Rect2i set/get roundtrip
func test_rect2i_set_get_roundtrip() -> void:
	_chronicle.set_fact("grid.region", Rect2i(0, 0, 16, 16))
	var val: Variant = _chronicle.get_fact("grid.region")
	assert_true(val is Rect2i, "should be Rect2i")
	assert_eq(val, Rect2i(0, 0, 16, 16))


# AABB set/get roundtrip
func test_aabb_set_get_roundtrip() -> void:
	_chronicle.set_fact("zone.bounds", AABB(Vector3(0, 0, 0), Vector3(10, 10, 10)))
	var val: Variant = _chronicle.get_fact("zone.bounds")
	assert_true(val is AABB, "should be AABB")
	assert_eq(val, AABB(Vector3(0, 0, 0), Vector3(10, 10, 10)))


# Plane set/get roundtrip
func test_plane_set_get_roundtrip() -> void:
	_chronicle.set_fact("level.floor", Plane(Vector3(0, 1, 0), 5.0))
	var val: Variant = _chronicle.get_fact("level.floor")
	assert_true(val is Plane, "should be Plane")
	assert_eq(val, Plane(Vector3(0, 1, 0), 5.0))


# Transform2D set/get roundtrip
func test_transform2d_set_get_roundtrip() -> void:
	var t := Transform2D(0.5, Vector2(100, 200))
	_chronicle.set_fact("sprite.transform", t)
	var val: Variant = _chronicle.get_fact("sprite.transform")
	assert_true(val is Transform2D, "should be Transform2D")
	assert_eq(val, t)


# Basis set/get roundtrip
func test_basis_set_get_roundtrip() -> void:
	var b := Basis(Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))
	_chronicle.set_fact("camera.basis", b)
	var val: Variant = _chronicle.get_fact("camera.basis")
	assert_true(val is Basis, "should be Basis")
	assert_eq(val, b)


# Transform3D set/get roundtrip
func test_transform3d_set_get_roundtrip() -> void:
	var t := Transform3D(Basis.IDENTITY, Vector3(5, 10, 15))
	_chronicle.set_fact("player.transform3d", t)
	var val: Variant = _chronicle.get_fact("player.transform3d")
	assert_true(val is Transform3D, "should be Transform3D")
	assert_eq(val, t)


# Projection set/get roundtrip
func test_projection_set_get_roundtrip() -> void:
	var p := Projection.create_perspective(75.0, 1.777, 0.1, 100.0)
	_chronicle.set_fact("camera.projection", p)
	var val: Variant = _chronicle.get_fact("camera.projection")
	assert_true(val is Projection, "should be Projection")
	assert_eq(val, p)


# prepare_for_json produces nested tagged dicts for Transform3D
func test_prepare_for_json_transform3d_nested_format() -> void:
	var t := Transform3D(Basis.IDENTITY, Vector3(5.5, 10.5, 0.5))
	var result: Variant = _codec.encode_value(t)
	assert_true(result is Dictionary)
	assert_eq(result["_chronicle_type"], "Transform3D")
	assert_true(result["basis"] is Dictionary)
	assert_eq(result["basis"]["_chronicle_type"], "Basis")
	assert_true(result["origin"] is Dictionary)
	assert_eq(result["origin"]["_chronicle_type"], "Vector3")
	assert_eq(result["origin"]["x"], 5.5)


# restore_from_json reconstructs Transform3D from nested tagged dicts
func test_restore_from_json_transform3d() -> void:
	var tagged: Dictionary = {
		"_chronicle_type": "Transform3D",
		"basis": {
			"_chronicle_type": "Basis",
			"x": {"_chronicle_type": "Vector3", "x": 1.0, "y": 0.0, "z": 0.0},
			"y": {"_chronicle_type": "Vector3", "x": 0.0, "y": 1.0, "z": 0.0},
			"z": {"_chronicle_type": "Vector3", "x": 0.0, "y": 0.0, "z": 1.0},
		},
		"origin": {"_chronicle_type": "Vector3", "x": 5.0, "y": 10.0, "z": 0.0},
	}
	var result: Variant = _codec.decode_value(tagged)
	assert_true(result is Transform3D, "should reconstruct to Transform3D")
	assert_eq(result, Transform3D(Basis.IDENTITY, Vector3(5, 10, 0)))


# Rect2 prepare_for_json produces nested Vector2 tagged dicts
func test_prepare_for_json_rect2_nested_format() -> void:
	var result: Variant = _codec.encode_value(Rect2(10.5, 20.5, 100.5, 50.5))
	assert_true(result is Dictionary)
	assert_eq(result["_chronicle_type"], "Rect2")
	assert_true(result["position"] is Dictionary)
	assert_eq(result["position"]["_chronicle_type"], "Vector2")
	assert_eq(result["position"]["x"], 10.5)
	assert_true(result["size"] is Dictionary)
	assert_eq(result["size"]["x"], 100.5)


# PackedByteArray set/get roundtrip
func test_packed_byte_array_set_get_roundtrip() -> void:
	var arr := PackedByteArray([72, 101, 108, 108, 111])
	_chronicle.set_fact("data.bytes", arr)
	var val: Variant = _chronicle.get_fact("data.bytes")
	assert_true(val is PackedByteArray, "should be PackedByteArray")
	assert_eq(val, PackedByteArray([72, 101, 108, 108, 111]))


# PackedInt32Array set/get roundtrip
func test_packed_int32_array_set_get_roundtrip() -> void:
	var arr := PackedInt32Array([1, 2, 3, 42])
	_chronicle.set_fact("data.ints", arr)
	var val: Variant = _chronicle.get_fact("data.ints")
	assert_true(val is PackedInt32Array, "should be PackedInt32Array")
	assert_eq(val, PackedInt32Array([1, 2, 3, 42]))


# PackedInt64Array set/get roundtrip
func test_packed_int64_array_set_get_roundtrip() -> void:
	var arr := PackedInt64Array([100, 200, 300])
	_chronicle.set_fact("data.longs", arr)
	var val: Variant = _chronicle.get_fact("data.longs")
	assert_true(val is PackedInt64Array, "should be PackedInt64Array")
	assert_eq(val, PackedInt64Array([100, 200, 300]))


# PackedFloat32Array set/get roundtrip
func test_packed_float32_array_set_get_roundtrip() -> void:
	var arr := PackedFloat32Array([1.5, 2.7, 3.14])
	_chronicle.set_fact("data.floats32", arr)
	var val: Variant = _chronicle.get_fact("data.floats32")
	assert_true(val is PackedFloat32Array, "should be PackedFloat32Array")
	assert_eq(val.size(), 3)


# PackedFloat64Array set/get roundtrip
func test_packed_float64_array_set_get_roundtrip() -> void:
	var arr := PackedFloat64Array([1.5, 2.7, 3.14])
	_chronicle.set_fact("data.floats64", arr)
	var val: Variant = _chronicle.get_fact("data.floats64")
	assert_true(val is PackedFloat64Array, "should be PackedFloat64Array")
	assert_eq(val, PackedFloat64Array([1.5, 2.7, 3.14]))


# PackedStringArray set/get roundtrip
func test_packed_string_array_set_get_roundtrip() -> void:
	var arr := PackedStringArray(["hello", "world"])
	_chronicle.set_fact("data.strings", arr)
	var val: Variant = _chronicle.get_fact("data.strings")
	assert_true(val is PackedStringArray, "should be PackedStringArray")
	assert_eq(val, PackedStringArray(["hello", "world"]))


# PackedVector2Array set/get roundtrip
func test_packed_vector2_array_set_get_roundtrip() -> void:
	var arr := PackedVector2Array([Vector2(0, 0), Vector2(10, 5)])
	_chronicle.set_fact("path.points", arr)
	var val: Variant = _chronicle.get_fact("path.points")
	assert_true(val is PackedVector2Array, "should be PackedVector2Array")
	assert_eq(val, PackedVector2Array([Vector2(0, 0), Vector2(10, 5)]))


# PackedVector3Array set/get roundtrip
func test_packed_vector3_array_set_get_roundtrip() -> void:
	var arr := PackedVector3Array([Vector3(1, 2, 3), Vector3(4, 5, 6)])
	_chronicle.set_fact("mesh.vertices", arr)
	var val: Variant = _chronicle.get_fact("mesh.vertices")
	assert_true(val is PackedVector3Array, "should be PackedVector3Array")
	assert_eq(val, PackedVector3Array([Vector3(1, 2, 3), Vector3(4, 5, 6)]))


# PackedVector4Array set/get roundtrip
func test_packed_vector4_array_set_get_roundtrip() -> void:
	var arr := PackedVector4Array([Vector4(1, 2, 3, 4)])
	_chronicle.set_fact("shader.data", arr)
	var val: Variant = _chronicle.get_fact("shader.data")
	assert_true(val is PackedVector4Array, "should be PackedVector4Array")
	assert_eq(val, PackedVector4Array([Vector4(1, 2, 3, 4)]))


# PackedColorArray set/get roundtrip
func test_packed_color_array_set_get_roundtrip() -> void:
	var arr := PackedColorArray([Color.RED, Color.BLUE])
	_chronicle.set_fact("palette.colors", arr)
	var val: Variant = _chronicle.get_fact("palette.colors")
	assert_true(val is PackedColorArray, "should be PackedColorArray")
	assert_eq(val.size(), 2)
	assert_eq(val[0], Color.RED)
	assert_eq(val[1], Color.BLUE)


# PackedByteArray serializes as base64
func test_packed_byte_array_base64_format() -> void:
	var arr := PackedByteArray([72, 101, 108, 108, 111])
	var result: Variant = _codec.encode_value(arr)
	assert_true(result is Dictionary)
	assert_eq(result["_chronicle_type"], "PackedByteArray")
	assert_true(result["data"] is String, "data should be base64 string")


# PackedVector2Array serializes with compound elements
func test_packed_vector2_array_compound_format() -> void:
	var arr := PackedVector2Array([Vector2(1, 2), Vector2(3, 4)])
	var result: Variant = _codec.encode_value(arr)
	assert_true(result is Dictionary)
	assert_eq(result["_chronicle_type"], "PackedVector2Array")
	assert_true(result["data"] is Array)
	assert_eq(result["data"].size(), 2)
	assert_eq(result["data"][0]["_chronicle_type"], "Vector2")


# Deep copy isolation — mutating returned PackedByteArray does not affect store
func test_packed_array_deep_copy_isolation() -> void:
	_chronicle.set_fact("data.bytes", PackedByteArray([1, 2, 3]))
	var val: Variant = _chronicle.get_fact("data.bytes")
	val[0] = 99
	var stored: Variant = _chronicle.get_fact("data.bytes")
	assert_eq(stored[0], 1, "store should be unaffected")


# Empty packed array roundtrip
func test_empty_packed_array_roundtrip() -> void:
	_chronicle.set_fact("data.empty", PackedVector2Array())
	var val: Variant = _chronicle.get_fact("data.empty")
	assert_true(val is PackedVector2Array)
	assert_eq(val.size(), 0)


# serialize/deserialize roundtrip preserves Vector2
func test_serialize_deserialize_vector2() -> void:
	_chronicle.set_fact("player.pos", Vector2(100.5, 200.75))
	_chronicle.set_fact("player.gold", 42)
	roundtrip()
	var val: Variant = _chronicle.get_fact("player.pos")
	assert_true(val is Vector2, "should survive serialize/deserialize as Vector2")
	assert_eq(val, Vector2(100.5, 200.75))
	assert_eq(_chronicle.get_fact("player.gold"), 42)


# serialize/deserialize roundtrip preserves all 16 value types
func test_serialize_deserialize_all_value_types() -> void:
	_chronicle.set_fact("t.v2", Vector2(1, 2))
	_chronicle.set_fact("t.v2i", Vector2i(3, 4))
	_chronicle.set_fact("t.v3", Vector3(1, 2, 3))
	_chronicle.set_fact("t.v3i", Vector3i(4, 5, 6))
	_chronicle.set_fact("t.v4", Vector4(1, 2, 3, 4))
	_chronicle.set_fact("t.v4i", Vector4i(5, 6, 7, 8))
	_chronicle.set_fact("t.color", Color(1, 0.5, 0, 0.8))
	_chronicle.set_fact("t.quat", Quaternion(0, 0.707, 0, 0.707))
	_chronicle.set_fact("t.rect2", Rect2(10, 20, 100, 50))
	_chronicle.set_fact("t.rect2i", Rect2i(0, 0, 16, 16))
	_chronicle.set_fact("t.aabb", AABB(Vector3.ZERO, Vector3(10, 10, 10)))
	_chronicle.set_fact("t.plane", Plane(Vector3.UP, 5.0))
	_chronicle.set_fact("t.t2d", Transform2D(0.5, Vector2(100, 200)))
	_chronicle.set_fact("t.basis", Basis.IDENTITY)
	_chronicle.set_fact("t.t3d", Transform3D(Basis.IDENTITY, Vector3(5, 10, 0)))
	_chronicle.set_fact("t.proj", Projection.create_perspective(75.0, 1.777, 0.1, 100.0))

	roundtrip()

	assert_true(_chronicle.get_fact("t.v2") is Vector2)
	assert_eq(_chronicle.get_fact("t.v2"), Vector2(1, 2))
	assert_true(_chronicle.get_fact("t.v2i") is Vector2i)
	assert_eq(_chronicle.get_fact("t.v2i"), Vector2i(3, 4))
	assert_true(_chronicle.get_fact("t.v3") is Vector3)
	assert_true(_chronicle.get_fact("t.v3i") is Vector3i)
	assert_true(_chronicle.get_fact("t.v4") is Vector4)
	assert_true(_chronicle.get_fact("t.v4i") is Vector4i)
	assert_true(_chronicle.get_fact("t.color") is Color)
	assert_true(_chronicle.get_fact("t.quat") is Quaternion)
	assert_true(_chronicle.get_fact("t.rect2") is Rect2)
	assert_eq(_chronicle.get_fact("t.rect2"), Rect2(10, 20, 100, 50))
	assert_true(_chronicle.get_fact("t.rect2i") is Rect2i)
	assert_true(_chronicle.get_fact("t.aabb") is AABB)
	assert_true(_chronicle.get_fact("t.plane") is Plane)
	assert_true(_chronicle.get_fact("t.t2d") is Transform2D)
	assert_true(_chronicle.get_fact("t.basis") is Basis)
	assert_true(_chronicle.get_fact("t.t3d") is Transform3D)
	assert_eq(_chronicle.get_fact("t.t3d"), Transform3D(Basis.IDENTITY, Vector3(5, 10, 0)))
	assert_true(_chronicle.get_fact("t.proj") is Projection)


# File roundtrip preserves value types through JSON
func test_file_roundtrip_value_types() -> void:
	_chronicle.set_fact("player.pos", Vector2(100.5, 200.75))
	_chronicle.set_fact("player.color", Color.RED)
	_chronicle.set_fact("level.bounds", Rect2(0, 0, 1920, 1080))
	var data: Dictionary = _chronicle.serialize()
	var save_path: String = "user://chronicle_test_value_types.json"
	var err: Error = save_temp(save_path, data)
	assert_eq(err, OK)
	var loaded: Variant = read_file(save_path)
	assert_not_null(loaded)
	var c2: Node = add_child_autoqfree(Chronicle.new())
	c2.deserialize(loaded)
	assert_true(c2.get_fact("player.pos") is Vector2)
	assert_eq(c2.get_fact("player.pos"), Vector2(100.5, 200.75))
	assert_true(c2.get_fact("player.color") is Color)
	assert_eq(c2.get_fact("player.color"), Color.RED)
	assert_true(c2.get_fact("level.bounds") is Rect2)


# File roundtrip preserves packed arrays through JSON
func test_file_roundtrip_packed_arrays() -> void:
	_chronicle.set_fact("data.bytes", PackedByteArray([72, 101, 108]))
	_chronicle.set_fact("path.points", PackedVector2Array([Vector2(0, 0), Vector2(10, 5)]))
	_chronicle.set_fact("data.ints", PackedInt32Array([1, 2, 3]))
	var data: Dictionary = _chronicle.serialize()
	var save_path: String = "user://chronicle_test_packed_arrays.json"
	var err: Error = save_temp(save_path, data)
	assert_eq(err, OK)
	var loaded: Variant = read_file(save_path)
	assert_not_null(loaded)
	var c2: Node = add_child_autoqfree(Chronicle.new())
	c2.deserialize(loaded)
	assert_true(c2.get_fact("data.bytes") is PackedByteArray)
	assert_eq(c2.get_fact("data.bytes"), PackedByteArray([72, 101, 108]))
	assert_true(c2.get_fact("path.points") is PackedVector2Array)
	assert_eq(c2.get_fact("path.points"), PackedVector2Array([Vector2(0, 0), Vector2(10, 5)]))
	assert_true(c2.get_fact("data.ints") is PackedInt32Array)
	assert_eq(c2.get_fact("data.ints"), PackedInt32Array([1, 2, 3]))


# V1 save (no value types) loads fine on V2 code
func test_v1_save_loads_on_v2_code() -> void:
	var v1_data: Dictionary = {
		"version": 1,
		"game_time": 10.0,
		"tick": 5,
		"facts": {"_global.gold": 500, "player.name": "hero"},
		"timeline": [],
	}
	var ok: bool = _chronicle.deserialize(v1_data)
	assert_true(ok, "V1 data should load on V2 code")
	assert_fact("gold", 500)
	assert_fact("player.name", "hero")


# serialize() output version is 2
func test_serialize_version_is_2() -> void:
	_chronicle.set_fact("x.y", 1)
	var data: Dictionary = _chronicle.serialize()
	assert_eq(data["version"], 2)


# Value types in timeline survive serialize/deserialize
func test_timeline_value_types_survive_roundtrip() -> void:
	set_time(1.0)
	_chronicle.set_fact("player.pos", Vector2(0, 0))
	set_time(2.0)
	_chronicle.set_fact("player.pos", Vector2(10, 5))
	roundtrip()
	var history: Array[Dictionary] = _chronicle.get_fact_history("player.pos")
	assert_eq(history.size(), 2)
	assert_true(history[0].value is Vector2)
	assert_eq(history[0].value, Vector2(0, 0))
	assert_true(history[1].value is Vector2)
	assert_eq(history[1].value, Vector2(10, 5))


# Existing int restoration still works after _restore_int_types removal
func test_int_restoration_still_works() -> void:
	_chronicle.set_fact("player.gold", 500)
	_chronicle.set_fact("player.level", 7)
	var data: Dictionary = _chronicle.serialize()
	var save_path: String = "user://chronicle_test_int_restore.json"
	var err: Error = save_temp(save_path, data)
	assert_eq(err, OK)
	var loaded: Variant = read_file(save_path)
	var c2: Node = add_child_autoqfree(Chronicle.new())
	c2.deserialize(loaded)
	assert_eq(typeof(c2.get_fact("player.gold")), TYPE_INT)
	assert_eq(c2.get_fact("player.gold"), 500)


# Array of value types survives file roundtrip
func test_array_of_vectors_file_roundtrip() -> void:
	_chronicle.set_fact("path.waypoints", [Vector2(0, 0), Vector2(10, 5), Vector2(20, 0)])
	var data: Dictionary = _chronicle.serialize()
	var save_path: String = "user://chronicle_test_array_vectors.json"
	save_temp(save_path, data)
	var loaded: Variant = read_file(save_path)
	var c2: Node = add_child_autoqfree(Chronicle.new())
	c2.deserialize(loaded)
	var val: Variant = c2.get_fact("path.waypoints")
	assert_true(val is Array)
	assert_eq(val.size(), 3)
	assert_true(val[0] is Vector2)
	assert_eq(val[1], Vector2(10, 5))


# Rollback restores previous Vector2 value
func test_rollback_restores_vector2() -> void:
	set_time(1.0)
	_chronicle.set_fact("player.pos", Vector2(0, 0))
	set_time(2.0)
	_chronicle.set_fact("player.pos", Vector2(100, 200))
	_chronicle.rollback_to(1.0)
	var val: Variant = _chronicle.get_fact("player.pos")
	assert_true(val is Vector2, "should still be Vector2 after rollback")
	assert_fact("player.pos", Vector2(0, 0))


# Rollback erases value type fact that didn't exist before
func test_rollback_erases_new_value_type_fact() -> void:
	_chronicle.set_fact("anchor", 0)
	set_time(1.0)
	_chronicle.set_fact("player.pos", Vector2(100, 200))
	_chronicle.rollback_to(0.0)
	assert_no_fact("player.pos")


# changes_between returns value type entries
func test_changes_between_with_value_types() -> void:
	set_time(1.0)
	_chronicle.set_fact("player.pos", Vector2(0, 0))
	set_time(2.0)
	_chronicle.set_fact("player.pos", Vector2(10, 5))
	set_time(3.0)
	_chronicle.set_fact("player.pos", Vector2(20, 0))
	var changes: Array[Dictionary] = _chronicle.get_changes_between(1.5, 2.5)
	assert_eq(changes.size(), 1)
	assert_true(changes[0].value is Vector2)
	assert_eq(changes[0].value, Vector2(10, 5))


# fact_changes_between with value type key
func test_fact_changes_between_with_value_types() -> void:
	set_time(1.0)
	_chronicle.set_fact("player.pos", Vector2(0, 0))
	set_time(2.0)
	_chronicle.set_fact("player.hp", 100)
	set_time(3.0)
	_chronicle.set_fact("player.pos", Vector2(10, 5))
	var changes: Array[Dictionary] = _chronicle.get_fact_changes_between("player.pos", 0.0, 5.0)
	assert_eq(changes.size(), 2)
	assert_true(changes[0].value is Vector2)
	assert_eq(changes[0].value, Vector2(0, 0))
	assert_eq(changes[1].value, Vector2(10, 5))


# Watcher fires for value type changes
func test_watcher_fires_for_value_type() -> void:
	var collector := watch_events("player.pos")
	_chronicle.set_fact("player.pos", Vector2(10, 20))
	collector.assert_count(1)
	collector.assert_event(0, "player.pos", Vector2(10, 20), null)


# fact_changed signal carries value type values
func test_fact_changed_signal_with_value_type() -> void:
	var collector := collect_signal(_chronicle, "fact_changed")
	_chronicle.set_fact("player.pos", Vector2(10, 20))
	_chronicle.set_fact("player.pos", Vector2(30, 40))
	collector.assert_count(2)
	collector.assert_event(0, "player.pos", Vector2(10, 20), null)
	collector.assert_event(1, "player.pos", Vector2(30, 40), Vector2(10, 20))


# Bulk set_facts with value types
func test_bulk_set_facts_with_value_types() -> void:
	_chronicle.set_facts({
		"player.pos": Vector2(100, 200),
		"player.color": Color.RED,
		"player.gold": 42,
	})
	assert_fact("player.pos", Vector2(100, 200))
	assert_fact("player.color", Color.RED)
	assert_fact("player.gold", 42)


# fact_history returns value types
func test_fact_history_value_types() -> void:
	set_time(1.0)
	_chronicle.set_fact("player.pos", Vector2(0, 0))
	set_time(2.0)
	_chronicle.set_fact("player.pos", Vector2(10, 5))
	var history: Array[Dictionary] = _chronicle.get_fact_history("player.pos")
	assert_eq(history.size(), 2)
	assert_true(history[0].value is Vector2)
	assert_eq(history[0].value, Vector2(0, 0))
	assert_true(history[1].value is Vector2)
	assert_eq(history[1].value, Vector2(10, 5))


# A large int beyond the JSON-safe range (2^53) is tagged int_large and round-trips exactly.
func test_int_large_roundtrip_exact() -> void:
	var big: int = 9007199254740993  # 2^53 + 1 — beyond JSON-safe double precision
	var encoded: Variant = _codec.encode_value(big)
	assert_true(encoded is Dictionary, "large int must encode to a tagged dict")
	assert_eq((encoded as Dictionary).get("_chronicle_type"), "int_large",
		"large int must be tagged int_large")
	assert_eq((encoded as Dictionary).get("v"), "9007199254740993",
		"int_large 'v' must be the exact decimal string of the value")
	var decoded: Variant = _codec.decode_value(encoded)
	assert_eq(typeof(decoded), TYPE_INT, "int_large must decode back to TYPE_INT")
	assert_eq(decoded, big, "large int must survive encode->decode exactly")
