extends Control

@export var buttons: Array[Button]
@export var winner_label: Label
@export var restart_button: Button

var turn: String = "X"
var board: Array = ["", "", "", "", "", "", "", "", ""]
var game_over: bool = false

func _ready() -> void:
	for i in range(9):
		buttons[i].pressed.connect(_on_button_pressed.bind(i))
	restart_button.pressed.connect(_on_restart_pressed)
	
	restart_game()

func _on_button_pressed(index: int) -> void:
	if board[index] == "" and not game_over:
		board[index] = turn
		buttons[index].text = turn
		if _check_winner():
			return
		if turn == "X":
			turn = "O"
		else:
			turn = "X"
		_update_turn_display()

func _check_winner() -> bool:
	var win_positions: Array[Array] = [[0, 1, 2], [3, 4, 5], [6, 7, 8], [0, 3, 6], [1, 4, 7], [2, 5, 8], [0, 4, 8], [2, 4, 6]]
	for pos in win_positions:
		if board[pos[0]] != "" and board[pos[0]] == board[pos[1]] and board[pos[1]] == board[pos[2]]:
			_game_over("Player " + board[pos[0]] + " wins!")
			return true
	if not "" in board:
		_game_over("It's a draw!")
		return true
	return false

func _game_over(message: String) -> void:
	game_over = true
	winner_label.text = message
	
func _on_restart_pressed() -> void:
	restart_game()

func restart_game() -> void:
	game_over = false
	turn = "X"
	for i in range(9):
		board[i] = ""
		buttons[i].text = ""
	_update_turn_display()
	
func _update_turn_display() -> void:
	if not game_over:
		winner_label.text = "Player " + turn + "'s Turn"
