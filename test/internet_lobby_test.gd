extends GdUnitTestSuite
## Tests for InternetLobby
## Tests the host/join flow orchestration for internet multiplayer.
##
## The relay address is an IP literal on a closed local port: a host NAME takes one of the engine's 256 resolver
## slots until it resolves, and a long test shard that leaked them all made connect_to_url fail at once (the
## host flow then never set is_host). An IP literal needs no resolver and never reaches a real server.
const RELAY := "ws://127.0.0.1:9"


func test_initial_state() -> void:
	var lobby = auto_free(InternetLobby.new())
	assert_that(lobby.is_host).is_false()
	assert_that(lobby.room_code).is_equal("")
	assert_that(lobby.relay_peer).is_null()


func test_host_creates_relay_peer() -> void:
	var lobby = auto_free(InternetLobby.new())
	# host_internet_game creates a RelayMultiplayerPeer
	# (connection will fail without a real server, but peer should be created)
	lobby.host_internet_game(RELAY)
	assert_that(lobby.relay_peer).is_not_null()
	assert_that(lobby.relay_peer is RelayMultiplayerPeer).is_true()
	lobby.disconnect_internet_game()


func test_host_sets_is_host_true() -> void:
	var lobby = auto_free(InternetLobby.new())
	lobby.host_internet_game(RELAY)
	assert_that(lobby.is_host).is_true()
	lobby.disconnect_internet_game()


func test_join_creates_relay_peer() -> void:
	var lobby = auto_free(InternetLobby.new())
	lobby.join_internet_game("ABCDEF", RELAY)
	assert_that(lobby.relay_peer).is_not_null()
	assert_that(lobby.relay_peer is RelayMultiplayerPeer).is_true()
	lobby.disconnect_internet_game()


func test_join_sets_is_host_false() -> void:
	var lobby = auto_free(InternetLobby.new())
	lobby.join_internet_game("ABCDEF", RELAY)
	assert_that(lobby.is_host).is_false()
	lobby.disconnect_internet_game()


func test_disconnect_clears_state() -> void:
	var lobby = auto_free(InternetLobby.new())
	lobby.host_internet_game(RELAY)
	lobby.disconnect_internet_game()
	assert_that(lobby.relay_peer).is_null()
	assert_that(lobby.is_host).is_false()
	assert_that(lobby.room_code).is_equal("")
