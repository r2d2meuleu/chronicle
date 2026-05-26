class_name ChronicleBuiltinTypes
extends RefCounted


static func register_all(registry: ChronicleTypeRegistry, codec: ChronicleTypeCodec) -> void:
	var TAG_KEY: String = ChronicleTypeRegistry.TAG_KEY
	var _identity: Callable = func(v: Variant) -> Variant: return v

	registry.register_type(TYPE_VECTOR2, "Vector2",
		func(v: Variant) -> Dictionary: return {TAG_KEY: "Vector2", "x": codec.encode_value(v.x), "y": codec.encode_value(v.y)},
		func(d: Dictionary) -> Variant: return Vector2(float(codec.decode_value(d["x"])), float(codec.decode_value(d["y"]))),
		_identity, ["x", "y"])
	registry.register_type(TYPE_VECTOR2I, "Vector2i",
		func(v: Variant) -> Dictionary: return {TAG_KEY: "Vector2i", "x": v.x, "y": v.y},
		func(d: Dictionary) -> Variant: return Vector2i(int(codec.decode_value(d["x"])), int(codec.decode_value(d["y"]))),
		_identity, ["x", "y"])
	registry.register_type(TYPE_VECTOR3, "Vector3",
		func(v: Variant) -> Dictionary: return {TAG_KEY: "Vector3", "x": codec.encode_value(v.x), "y": codec.encode_value(v.y), "z": codec.encode_value(v.z)},
		func(d: Dictionary) -> Variant: return Vector3(float(codec.decode_value(d["x"])), float(codec.decode_value(d["y"])), float(codec.decode_value(d["z"]))),
		_identity, ["x", "y", "z"])
	registry.register_type(TYPE_VECTOR3I, "Vector3i",
		func(v: Variant) -> Dictionary: return {TAG_KEY: "Vector3i", "x": v.x, "y": v.y, "z": v.z},
		func(d: Dictionary) -> Variant: return Vector3i(int(codec.decode_value(d["x"])), int(codec.decode_value(d["y"])), int(codec.decode_value(d["z"]))),
		_identity, ["x", "y", "z"])
	registry.register_type(TYPE_VECTOR4, "Vector4",
		func(v: Variant) -> Dictionary: return {TAG_KEY: "Vector4", "x": codec.encode_value(v.x), "y": codec.encode_value(v.y), "z": codec.encode_value(v.z), "w": codec.encode_value(v.w)},
		func(d: Dictionary) -> Variant: return Vector4(float(codec.decode_value(d["x"])), float(codec.decode_value(d["y"])), float(codec.decode_value(d["z"])), float(codec.decode_value(d["w"]))),
		_identity, ["x", "y", "z", "w"])
	registry.register_type(TYPE_VECTOR4I, "Vector4i",
		func(v: Variant) -> Dictionary: return {TAG_KEY: "Vector4i", "x": v.x, "y": v.y, "z": v.z, "w": v.w},
		func(d: Dictionary) -> Variant: return Vector4i(int(codec.decode_value(d["x"])), int(codec.decode_value(d["y"])), int(codec.decode_value(d["z"])), int(codec.decode_value(d["w"]))),
		_identity, ["x", "y", "z", "w"])
	registry.register_type(TYPE_COLOR, "Color",
		func(v: Variant) -> Dictionary: return {TAG_KEY: "Color", "r": codec.encode_value(v.r), "g": codec.encode_value(v.g), "b": codec.encode_value(v.b), "a": codec.encode_value(v.a)},
		func(d: Dictionary) -> Variant: return Color(float(codec.decode_value(d["r"])), float(codec.decode_value(d["g"])), float(codec.decode_value(d["b"])), float(codec.decode_value(d["a"]))),
		_identity, ["r", "g", "b", "a"])
	registry.register_type(TYPE_QUATERNION, "Quaternion",
		func(v: Variant) -> Dictionary: return {TAG_KEY: "Quaternion", "x": codec.encode_value(v.x), "y": codec.encode_value(v.y), "z": codec.encode_value(v.z), "w": codec.encode_value(v.w)},
		func(d: Dictionary) -> Variant: return Quaternion(float(codec.decode_value(d["x"])), float(codec.decode_value(d["y"])), float(codec.decode_value(d["z"])), float(codec.decode_value(d["w"]))),
		_identity, ["x", "y", "z", "w"])
	registry.register_type(TYPE_RECT2, "Rect2",
		func(v: Variant) -> Dictionary: return {TAG_KEY: "Rect2", "position": codec.encode_value(v.position), "size": codec.encode_value(v.size)},
		func(d: Dictionary) -> Variant: return Rect2(codec.decode_value(d["position"]), codec.decode_value(d["size"])),
		_identity, ["position", "size"])
	registry.register_type(TYPE_RECT2I, "Rect2i",
		func(v: Variant) -> Dictionary: return {TAG_KEY: "Rect2i", "position": codec.encode_value(v.position), "size": codec.encode_value(v.size)},
		func(d: Dictionary) -> Variant: return Rect2i(codec.decode_value(d["position"]), codec.decode_value(d["size"])),
		_identity, ["position", "size"])
	registry.register_type(TYPE_AABB, "AABB",
		func(v: Variant) -> Dictionary: return {TAG_KEY: "AABB", "position": codec.encode_value(v.position), "size": codec.encode_value(v.size)},
		func(d: Dictionary) -> Variant: return AABB(codec.decode_value(d["position"]), codec.decode_value(d["size"])),
		_identity, ["position", "size"])
	registry.register_type(TYPE_PLANE, "Plane",
		func(v: Variant) -> Dictionary: return {TAG_KEY: "Plane", "normal": codec.encode_value(v.normal), "d": codec.encode_value(v.d)},
		func(d: Dictionary) -> Variant: return Plane(codec.decode_value(d["normal"]), float(codec.decode_value(d["d"]))),
		_identity, ["normal", "d"])
	registry.register_type(TYPE_TRANSFORM2D, "Transform2D",
		func(v: Variant) -> Dictionary: return {TAG_KEY: "Transform2D", "x": codec.encode_value(v.x), "y": codec.encode_value(v.y), "origin": codec.encode_value(v.origin)},
		func(d: Dictionary) -> Variant: return Transform2D(codec.decode_value(d["x"]), codec.decode_value(d["y"]), codec.decode_value(d["origin"])),
		_identity, ["x", "y", "origin"])
	registry.register_type(TYPE_BASIS, "Basis",
		func(v: Variant) -> Dictionary: return {TAG_KEY: "Basis", "x": codec.encode_value(v.x), "y": codec.encode_value(v.y), "z": codec.encode_value(v.z)},
		func(d: Dictionary) -> Variant: return Basis(codec.decode_value(d["x"]), codec.decode_value(d["y"]), codec.decode_value(d["z"])),
		_identity, ["x", "y", "z"])
	registry.register_type(TYPE_TRANSFORM3D, "Transform3D",
		func(v: Variant) -> Dictionary: return {TAG_KEY: "Transform3D", "basis": codec.encode_value(v.basis), "origin": codec.encode_value(v.origin)},
		func(d: Dictionary) -> Variant: return Transform3D(codec.decode_value(d["basis"]), codec.decode_value(d["origin"])),
		_identity, ["basis", "origin"])
	registry.register_type(TYPE_PROJECTION, "Projection",
		func(v: Variant) -> Dictionary: return {TAG_KEY: "Projection", "x": codec.encode_value(v.x), "y": codec.encode_value(v.y), "z": codec.encode_value(v.z), "w": codec.encode_value(v.w)},
		func(d: Dictionary) -> Variant:
			var p := Projection()
			p.x = codec.decode_value(d["x"])
			p.y = codec.decode_value(d["y"])
			p.z = codec.decode_value(d["z"])
			p.w = codec.decode_value(d["w"])
			return p,
		_identity, ["x", "y", "z", "w"])
	registry.register_type(TYPE_PACKED_BYTE_ARRAY, "PackedByteArray",
		func(v: Variant) -> Dictionary: return {TAG_KEY: "PackedByteArray", "data": Marshalls.raw_to_base64(v)},
		func(d: Dictionary) -> Variant: return Marshalls.base64_to_raw(d["data"]),
		func(v: Variant) -> Variant: return v.duplicate(), ["data"])
	registry.register_type(TYPE_PACKED_INT32_ARRAY, "PackedInt32Array",
		func(v: Variant) -> Dictionary:
			var arr: Array[Variant] = []
			for i: int in v: arr.append(i)
			return {TAG_KEY: "PackedInt32Array", "data": arr},
		func(d: Dictionary) -> Variant:
			var arr := PackedInt32Array()
			for i: Variant in d["data"]: arr.append(int(i))
			return arr,
		func(v: Variant) -> Variant: return v.duplicate(), ["data"])
	registry.register_type(TYPE_PACKED_INT64_ARRAY, "PackedInt64Array",
		func(v: Variant) -> Dictionary:
			var arr: Array[Variant] = []
			for i: int in v: arr.append(codec.encode_value(i))
			return {TAG_KEY: "PackedInt64Array", "data": arr},
		func(d: Dictionary) -> Variant:
			var arr := PackedInt64Array()
			for i: Variant in d["data"]: arr.append(int(codec.decode_value(i)))
			return arr,
		func(v: Variant) -> Variant: return v.duplicate(), ["data"])
	registry.register_type(TYPE_PACKED_FLOAT32_ARRAY, "PackedFloat32Array",
		func(v: Variant) -> Dictionary:
			var arr: Array[Variant] = []
			for f: float in v: arr.append(codec.encode_value(f))
			return {TAG_KEY: "PackedFloat32Array", "data": arr},
		func(d: Dictionary) -> Variant:
			var arr := PackedFloat32Array()
			for f: Variant in d["data"]: arr.append(float(codec.decode_value(f)))
			return arr,
		func(v: Variant) -> Variant: return v.duplicate(), ["data"])
	registry.register_type(TYPE_PACKED_FLOAT64_ARRAY, "PackedFloat64Array",
		func(v: Variant) -> Dictionary:
			var arr: Array[Variant] = []
			for f: float in v: arr.append(codec.encode_value(f))
			return {TAG_KEY: "PackedFloat64Array", "data": arr},
		func(d: Dictionary) -> Variant:
			var arr := PackedFloat64Array()
			for f: Variant in d["data"]: arr.append(float(codec.decode_value(f)))
			return arr,
		func(v: Variant) -> Variant: return v.duplicate(), ["data"])
	registry.register_type(TYPE_PACKED_STRING_ARRAY, "PackedStringArray",
		func(v: Variant) -> Dictionary:
			var arr: Array[Variant] = []
			for s: String in v: arr.append(s)
			return {TAG_KEY: "PackedStringArray", "data": arr},
		func(d: Dictionary) -> Variant:
			var arr := PackedStringArray()
			for s: Variant in d["data"]: arr.append(str(s))
			return arr,
		func(v: Variant) -> Variant: return v.duplicate(), ["data"])
	registry.register_type(TYPE_PACKED_VECTOR2_ARRAY, "PackedVector2Array",
		func(v: Variant) -> Dictionary:
			var arr: Array[Variant] = []
			for vec: Vector2 in v: arr.append(codec.encode_value(vec))
			return {TAG_KEY: "PackedVector2Array", "data": arr},
		func(d: Dictionary) -> Variant:
			var arr := PackedVector2Array()
			for item: Variant in d["data"]: arr.append(codec.decode_value(item))
			return arr,
		func(v: Variant) -> Variant: return v.duplicate(), ["data"])
	registry.register_type(TYPE_PACKED_VECTOR3_ARRAY, "PackedVector3Array",
		func(v: Variant) -> Dictionary:
			var arr: Array[Variant] = []
			for vec: Vector3 in v: arr.append(codec.encode_value(vec))
			return {TAG_KEY: "PackedVector3Array", "data": arr},
		func(d: Dictionary) -> Variant:
			var arr := PackedVector3Array()
			for item: Variant in d["data"]: arr.append(codec.decode_value(item))
			return arr,
		func(v: Variant) -> Variant: return v.duplicate(), ["data"])
	registry.register_type(TYPE_PACKED_VECTOR4_ARRAY, "PackedVector4Array",
		func(v: Variant) -> Dictionary:
			var arr: Array[Variant] = []
			for vec: Vector4 in v: arr.append(codec.encode_value(vec))
			return {TAG_KEY: "PackedVector4Array", "data": arr},
		func(d: Dictionary) -> Variant:
			var arr := PackedVector4Array()
			for item: Variant in d["data"]: arr.append(codec.decode_value(item))
			return arr,
		func(v: Variant) -> Variant: return v.duplicate(), ["data"])
	registry.register_type(TYPE_PACKED_COLOR_ARRAY, "PackedColorArray",
		func(v: Variant) -> Dictionary:
			var arr: Array[Variant] = []
			for c: Color in v: arr.append(codec.encode_value(c))
			return {TAG_KEY: "PackedColorArray", "data": arr},
		func(d: Dictionary) -> Variant:
			var arr := PackedColorArray()
			for item: Variant in d["data"]: arr.append(codec.decode_value(item))
			return arr,
		func(v: Variant) -> Variant: return v.duplicate(), ["data"])
	registry.register_type(TYPE_STRING_NAME, "StringName",
		func(v: Variant) -> Dictionary: return {TAG_KEY: "StringName", "v": String(v)},
		func(d: Dictionary) -> Variant: return StringName(d["v"]),
		_identity, ["v"])
	registry.register_type(TYPE_NODE_PATH, "NodePath",
		func(v: Variant) -> Dictionary: return {TAG_KEY: "NodePath", "v": String(v)},
		func(d: Dictionary) -> Variant: return NodePath(d["v"]),
		_identity, ["v"])
