extends Resource
class_name VectorWeaponSpec

## These resources are the public customization surface for a new weapon.
@export var title: String = "Pistol"
@export var short_name: String = "P12"
@export_range(1, 100) var damage: float = 30.0
@export_range(1, 100) var magazine_size: int = 12
@export_range(0.05, 2.0) var fire_interval: float = 0.24
@export_range(0.1, 5.0) var reload_seconds: float = 1.15
@export_range(0.0, 10.0) var spread_degrees: float = 0.35
@export_range(1, 20) var pellets: int = 1
@export var automatic: bool = false
@export_range(0.0, 5.0) var recoil: float = 1.0
@export var accent: Color = Color("50e2cb")
