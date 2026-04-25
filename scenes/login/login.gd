## Login — handles sign-in and sign-up via Supabase Auth.
## On success, GameState loads the player profile then transitions to the city scene.
extends Control

@onready var email_input    : LineEdit = %EmailInput
@onready var password_input : LineEdit = %PasswordInput
@onready var status_label   : Label   = %StatusLabel
@onready var sign_in_button : Button  = %SignInButton
@onready var sign_up_button : Button  = %SignUpButton

func _ready() -> void:
sign_in_button.pressed.connect(_on_sign_in)
sign_up_button.pressed.connect(_on_sign_up)
SupabaseClient.auth_success.connect(_on_auth_success)
SupabaseClient.auth_error.connect(_on_auth_error)
# Allow pressing Enter in password field to submit.
password_input.text_submitted.connect(func(_t): _on_sign_in())


func _on_sign_in() -> void:
var email    := email_input.text.strip_edges()
var password := password_input.text
if not _validate(email, password):
return
_set_loading(true)
SupabaseClient.sign_in(email, password)


func _on_sign_up() -> void:
var email    := email_input.text.strip_edges()
var password := password_input.text
if not _validate(email, password):
return
_set_loading(true)
SupabaseClient.sign_up(email, password)


func _on_auth_success(_session: Dictionary) -> void:
status_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4))
status_label.text = "Welcome! Loading your kingdom..."
# GameState auto-loads player profile on auth_success.
# Wait for it, then switch scenes.
await GameState.player_loaded
get_tree().change_scene_to_file("res://scenes/city/city.tscn")


func _on_auth_error(message: String) -> void:
_set_loading(false)
status_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
# Show a friendly message instead of raw API errors.
if "Invalid login" in message or "invalid_grant" in message:
status_label.text = "Incorrect email or password."
elif "already registered" in message:
status_label.text = "An account with that email already exists."
elif "Password" in message and "characters" in message:
status_label.text = "Password must be at least 6 characters."
else:
status_label.text = "Something went wrong. Please try again."


func _validate(email: String, password: String) -> bool:
if email == "" or not "@" in email:
status_label.text = "Please enter a valid email address."
return false
if password.length() < 6:
status_label.text = "Password must be at least 6 characters."
return false
status_label.text = ""
return true


func _set_loading(loading: bool) -> void:
sign_in_button.disabled = loading
sign_up_button.disabled = loading
email_input.editable    = not loading
password_input.editable = not loading
if loading:
status_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
status_label.text = "Connecting..."
