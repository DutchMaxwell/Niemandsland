extends Node
class_name SelfUpdater
## Downloads the platform release .zip and installs it OVER the running installation, then relaunches.
##
## Defensive by design: ANY failure (download, extract, write, unsupported layout) emits
## `update_failed` so the caller can fall back to simply opening the download page — the self-update
## is therefore never WORSE than the manual flow. The update is fully staged under user:// before a
## single install file is touched, so a half-finished download can't corrupt the install.
##
## Per platform (the running binary's directory is the install dir):
##   Linux  — overwrite Niemandsland.x86_64 + .pck (the running process keeps its old inodes), relaunch.
##   macOS  — replace the .app bundle, relaunch via `open`.
##   Windows— the running .exe is LOCKED, so a tiny helper .bat waits for us to exit, swaps the single
##            self-contained .exe (with a .bak it restores on failure), and relaunches.

# ===== Signals =====

## stage: "Downloading" / "Extracting" / "Installing"; ratio in [0,1] while downloading, -1 = busy.
signal progress(stage: String, ratio: float)
## Could not self-update — the caller should fall back to opening the download URL in a browser.
signal update_failed(reason: String)
## Files are staged + the relaunch is about to happen; the app is quitting.
signal restarting()

# ===== Constants =====

const STAGING_DIR: String = "user://_update"
const USER_AGENT: String = "Niemandsland-SelfUpdater"

# ===== Private state =====

var _http: HTTPRequest = null
var _zip_path: String = ""

# ===== Public API =====

## Begin a self-update from a release .zip asset URL (all three platform assets are zips).
func install(asset_url: String) -> void:
	if not asset_url.ends_with(".zip"):
		_fail("the release has no installable .zip for this platform")
		return
	var staging_abs := ProjectSettings.globalize_path(STAGING_DIR)
	_rmrf(staging_abs)
	if DirAccess.make_dir_recursive_absolute(staging_abs) != OK:
		_fail("could not create the staging folder")
		return
	_zip_path = STAGING_DIR.path_join("download.zip")
	_http = HTTPRequest.new()
	_http.use_threads = true
	_http.download_file = _zip_path  # stream to disk; never holds the whole zip in memory
	add_child(_http)
	_http.request_completed.connect(_on_downloaded)
	progress.emit("Downloading", 0.0)
	var err := _http.request(asset_url, PackedStringArray(["User-Agent: %s" % USER_AGENT]))
	if err != OK:
		_fail("the download could not start (error %d)" % err)


func _process(_delta: float) -> void:
	if _http != null and _http.get_http_client_status() == HTTPClient.STATUS_BODY:
		var total := _http.get_body_size()
		var got := _http.get_downloaded_bytes()
		progress.emit("Downloading", (float(got) / float(total)) if total > 0 else -1.0)


# ===== Download -> extract -> apply =====

func _on_downloaded(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
		_fail("the download failed (result %d, HTTP %d)" % [result, code])
		return
	progress.emit("Extracting", -1.0)
	var extracted := STAGING_DIR.path_join("extracted")
	if not _extract(_zip_path, extracted):
		_fail("the downloaded update could not be extracted")
		return
	progress.emit("Installing", -1.0)
	_apply(ProjectSettings.globalize_path(extracted))


## Extract every entry of `zip_path` into `dest` (cleared first). Returns false on any I/O error.
func _extract(zip_path: String, dest: String) -> bool:
	var reader := ZIPReader.new()
	if reader.open(ProjectSettings.globalize_path(zip_path)) != OK:
		return false
	var g_dest := ProjectSettings.globalize_path(dest)
	_rmrf(g_dest)
	if DirAccess.make_dir_recursive_absolute(g_dest) != OK:
		reader.close()
		return false
	for entry in reader.get_files():
		if entry.ends_with("/"):
			continue
		var out_path := g_dest.path_join(entry)
		if DirAccess.make_dir_recursive_absolute(out_path.get_base_dir()) != OK:
			reader.close()
			return false
		var data := reader.read_file(entry)
		var fa := FileAccess.open(out_path, FileAccess.WRITE)
		if fa == null:
			reader.close()
			return false
		fa.store_buffer(data)
		fa.close()
	reader.close()
	return true


func _apply(extracted_abs: String) -> void:
	var exe := OS.get_executable_path()
	match OS.get_name():
		"Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD":
			_apply_unix(extracted_abs, exe.get_base_dir(), exe)
		"macOS":
			_apply_macos(extracted_abs, exe)
		"Windows", "UWP":
			_apply_windows(extracted_abs, exe.get_base_dir(), exe)
		_:
			_fail("self-update is not supported on this platform")


## Linux: overwrite the install-dir files in place. The running process keeps its old open inodes, so
## the swap is safe and the new files take effect on the relaunch below.
func _apply_unix(extracted_abs: String, install_dir: String, exe: String) -> void:
	if not _copy_tree(extracted_abs, install_dir):
		_fail("could not write the new files (permissions on the install folder?)")
		return
	OS.execute("chmod", ["+x", exe])
	restarting.emit()
	OS.create_process(exe, [])
	get_tree().quit()


## macOS: replace the whole .app bundle (exe is …/Niemandsland.app/Contents/MacOS/Niemandsland), then
## relaunch via `open`. The extracted zip contains a single top-level *.app.
func _apply_macos(extracted_abs: String, exe: String) -> void:
	var app_path := exe.get_base_dir().get_base_dir().get_base_dir()  # …/Foo.app
	var apps_parent := app_path.get_base_dir()
	var new_app := _first_app_bundle(extracted_abs)
	if new_app.is_empty():
		_fail("the macOS update contained no .app bundle")
		return
	var dest_app := apps_parent.path_join(new_app.get_file())
	_rmrf(dest_app)
	if not _copy_tree(new_app, dest_app):
		_fail("could not replace the app bundle (permissions?)")
		return
	OS.execute("chmod", ["+x", dest_app.path_join("Contents/MacOS").path_join(app_path.get_file().get_basename())])
	restarting.emit()
	OS.create_process("/usr/bin/open", [dest_app])
	get_tree().quit()


## Windows: the running .exe is locked, so a helper .bat waits for us to exit, swaps the single
## self-contained .exe (keeping a .bak it restores if the copy fails), and relaunches.
func _apply_windows(extracted_abs: String, install_dir: String, exe: String) -> void:
	var new_exe := extracted_abs.path_join(exe.get_file())
	if not FileAccess.file_exists(new_exe):
		_fail("the Windows update contained no %s" % exe.get_file())
		return
	var bat := ProjectSettings.globalize_path(STAGING_DIR).path_join("apply_update.bat")
	var name := exe.get_file()
	var script := "@echo off\r\n"
	script += "ping 127.0.0.1 -n 3 >nul\r\n"  # ~2s: let the game process exit + release the lock
	script += "copy /Y \"%s\" \"%s.bak\" >nul\r\n" % [exe, exe]
	script += "copy /Y \"%s\" \"%s\" >nul\r\n" % [new_exe, exe]
	script += "if errorlevel 1 copy /Y \"%s.bak\" \"%s\" >nul\r\n" % [exe, exe]
	script += "del \"%s.bak\" >nul 2>&1\r\n" % exe
	script += "start \"\" \"%s\"\r\n" % exe
	var fa := FileAccess.open(bat, FileAccess.WRITE)
	if fa == null:
		_fail("could not write the Windows update helper")
		return
	fa.store_string(script)
	fa.close()
	restarting.emit()
	OS.create_process("cmd.exe", ["/c", "start", "", "/min", bat])
	get_tree().quit()


# ===== Helpers =====

func _first_app_bundle(dir: String) -> String:
	for d in DirAccess.get_directories_at(dir):
		if d.ends_with(".app"):
			return dir.path_join(d)
	return ""


## Recursively copy everything in `src` into `dst` (created if missing), replacing files — each
## existing target is unlinked first so an in-use file (the running binary, the mapped .pck) swaps cleanly.
func _copy_tree(src: String, dst: String) -> bool:
	if DirAccess.make_dir_recursive_absolute(dst) != OK:
		return false
	var da := DirAccess.open(src)
	if da == null:
		return false
	for f in da.get_files():
		var target := dst.path_join(f)
		# A running executable / mapped .pck cannot be overwritten in place on Linux (ETXTBSY), but it
		# CAN be unlinked first — the running process keeps its open inode and the fresh file appears at
		# the freed path. (macOS already _rmrf's its bundle first; Windows swaps the locked exe post-exit.)
		if FileAccess.file_exists(target):
			DirAccess.remove_absolute(target)
		if da.copy(src.path_join(f), target) != OK:
			return false
	for sub in da.get_directories():
		if not _copy_tree(src.path_join(sub), dst.path_join(sub)):
			return false
	return true


func _rmrf(abs_path: String) -> void:
	var da := DirAccess.open(abs_path)
	if da == null:
		return
	for f in da.get_files():
		da.remove(abs_path.path_join(f))
	for sub in da.get_directories():
		_rmrf(abs_path.path_join(sub))
		da.remove(abs_path.path_join(sub))


func _fail(reason: String) -> void:
	update_failed.emit(reason)
