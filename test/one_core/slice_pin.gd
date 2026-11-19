extends RefCounted
## C-19: the AI door's default slice is the measured deny-list. A case that is about a unit the NARROW (allow) slice refuses
## (a unit with a rule is "not plain", the census labels of such a unit) pins that slice through the real way back,
## `NML_CORE_SLICE=allow`, and releases it in after_test. The human door reads the allow file by default and needs no pin.


static func narrow() -> void:
	OS.set_environment("NML_CORE_SLICE", "allow")
	CoreSlice.reset_cache()


static func release() -> void:
	OS.unset_environment("NML_CORE_SLICE")
	CoreSlice.reset_cache()
