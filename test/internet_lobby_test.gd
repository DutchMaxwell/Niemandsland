extends GdUnitTestSuite
## Tests for InternetLobby
## Tests the host/join flow orchestration for internet multiplayer.


func test_initial_state() -> void:
	var lobby = InternetLobby.new()
	assert_that(lobby.is_host).is_false()
	assert_that(lobby.room_code).is_equal("")
	assert_that(lobby.relay_peer).is_null()


func test_host_creates_relay_peer() -> void:
	var lobby = InternetLobby.new()
	# host_internet_game creates a RelayMultiplayerPeer
	# (connection will fail without a real server, but peer should be created)
	lobby.host_internet_game("ws://invalid:9999")
	assert_that(lobby.relay_peer).is_not_null()
	assert_that(lobby.relay_peer is RelayMultiplayerPeer).is_true()
	lobby.disconnect_internet_game()


func test_host_sets_is_host_true() -> void:
	var lobby = InternetLobby.new()
	lobby.host_internet_game("ws://invalid:9999")
	assert_that(lobby.is_host).is_true()
	lobby.disconnect_internet_game()


func test_join_creates_relay_peer() -> void:
	var lobby = InternetLobby.new()
	lobby.join_internet_game("ABCDEF", "ws://invalid:9999")
	assert_that(lobby.relay_peer).is_not_null()
	assert_that(lobby.relay_peer is RelayMultiplayerPeer).is_true()
	lobby.disconnect_internet_game()


func test_join_sets_is_host_false() -> void:
	var lobby = InternetLobby.new()
	lobby.join_internet_game("ABCDEF", "ws://invalid:9999")
	assert_that(lobby.is_host).is_false()
	lobby.disconnect_internet_game()


func test_disconnect_clears_state() -> void:
	var lobby = InternetLobby.new()
	lobby.host_internet_game("ws://invalid:9999")
	lobby.disconnect_internet_game()
	assert_that(lobby.relay_peer).is_null()
	assert_that(lobby.is_host).is_false()
	assert_that(lobby.room_code).is_equal("")
