extends Node
## The network seam's presence calls as no-ops, for test FakeNets that stand in for NetworkManager. main._broadcast_presence
## (15 Hz, whenever a room is active) calls them; a FakeNet without them crashed a suite that ran long enough for the timer
## to fire. A FakeNet extends this file instead of Node.


func broadcast_cursor_position(_pos: Vector3) -> void:
	pass


func broadcast_camera_direction(_yaw: float, _pitch: float, _zoom: float) -> void:
	pass


func broadcast_camera_position(_pos: Vector3) -> void:
	pass
