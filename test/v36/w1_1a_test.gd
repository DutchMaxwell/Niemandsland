extends GdUnitTestSuite
## W1.1a (0.3.15, rules 3.6): the GF and AoF rule maps declare 3.6.0 as the rules this build plays,
## so a 3.6 book imports silently there and an old 3.5 book is the one that gets the warning. The
## spin-off maps (gff / aofs / aofr) stay on 3.5.1 in this release and keep warning about 3.6 books.
## Every case reads the real maps through `rules_core_version` (their `_meta`) and the real warning
## text, never a second constant.


func before_test() -> void:
	# The reader caches per system; every case starts from the files on disk.
	OPRApiClient._core_versions.clear()


func test_gf_and_aof_maps_declare_rules_360() -> void:
	for system: String in ["gf", "aof"]:
		assert_str(OPRApiClient.rules_core_version(system)).override_failure_message(
			"the %s rule map does not declare 3.6.0" % system).is_equal("3.6.0")


func test_a_360_book_imports_silently_on_gf_and_aof() -> void:
	for system: String in ["gf", "aof"]:
		var warning := OPRApiClient.rules_version_warning("3.6.0", OPRApiClient.rules_core_version(system))
		assert_str(warning).override_failure_message(
			"a 3.6.0 book warns on %s: '%s'" % [system, warning]).is_empty()


func test_an_old_353_book_warns_on_gf_and_aof() -> void:
	for system: String in ["gf", "aof"]:
		var warning := OPRApiClient.rules_version_warning("3.5.3", OPRApiClient.rules_core_version(system))
		assert_str(warning).override_failure_message(
			"a 3.5.3 book imports silently on %s" % system).is_not_empty()


## A book OLDER than the rules must not be told the game runs on old rules: it runs on newer ones.
func test_an_older_book_is_told_its_list_is_the_older_side() -> void:
	var warning := OPRApiClient.rules_version_warning("3.5.3", "3.6.0")
	assert_str(warning).contains("3.5.3")
	assert_str(warning).contains("3.6.0")
	assert_str(warning).override_failure_message(
		"an older book is told the game runs on old rules: '%s'" % warning).not_contains("runs on the old rules")
	assert_str(warning).override_failure_message(
		"an older book is not told its list is the older side: '%s'" % warning).contains("older rules")
	assert_str(warning).not_contains("refuse")


## CONTROL (passes with and without the change): a 3.5.3 book against 3.6.0 rules warns.
func test_control_a_353_book_warns_on_360_rules() -> void:
	assert_str(OPRApiClient.rules_version_warning("3.5.3", "3.6.0")).is_not_empty()


## CONTROL: a book NEWER than the rules keeps today's sentence.
func test_control_a_newer_book_keeps_todays_sentence() -> void:
	var warning := OPRApiClient.rules_version_warning("3.7.0", "3.6.0")
	assert_str(warning).contains("3.7.0")
	assert_str(warning).contains("3.6.0")
	assert_str(warning).contains("the game runs on the old rules")
	assert_str(warning).not_contains("refuse")


## CONTROL: versions compare as numbers, so a two-digit minor ("3.10") is the newer side.
func test_control_a_two_digit_minor_counts_as_newer() -> void:
	assert_str(OPRApiClient.rules_version_warning("3.10.0", "3.9.0")).contains(
		"the game runs on the old rules")


## CONTROL: the spin-off maps stay on 3.5.1 in this release, so a 3.6.0 book still warns there.
func test_control_spin_off_maps_keep_351_and_warn_on_a_360_book() -> void:
	for system: String in ["gff", "aofs", "aofr"]:
		var core := OPRApiClient.rules_core_version(system)
		assert_str(core).override_failure_message("%s does not stay on 3.5.1" % system).is_equal("3.5.1")
		assert_str(OPRApiClient.rules_version_warning("3.6.0", core)).override_failure_message(
			"a 3.6.0 book imports silently on %s" % system).is_not_empty()
