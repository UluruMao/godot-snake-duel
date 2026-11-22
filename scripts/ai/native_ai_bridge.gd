class_name NativeAIBridge
extends RefCounted

## Dynamic lookup keeps the reference backend playable without a native binary.
## Instances are decision/worker owned, never a global mutable native singleton.
static func available() -> bool:
	return ClassDB.class_exists("NativeSnakeAI")

static func enabled() -> bool:
	return available() and not "--gdscript-ai" in OS.get_cmdline_user_args()

static func create_kernel(requested := true) -> RefCounted:
	return ClassDB.instantiate("NativeSnakeAI") if requested and enabled() else null

static func description() -> String:
	return "C++ GDExtension" if enabled() else "GDScript reference"
