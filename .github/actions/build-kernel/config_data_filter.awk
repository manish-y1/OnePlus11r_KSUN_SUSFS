# Filters the kernel config that gets embedded in the Image (/proc/config.gz).
#
# kernel/Makefile runs it (see "Apply Fake config.gz patch" in action.yml) as:
#   awk -v unset_opts="CONFIG_A CONFIG_B" -f config_data_filter.awk .config
#
# - Options listed in unset_opts are shown as "# CONFIG_X is not set", which
#   is what the upstream fake_config.patch did with sed.
# - KernelSU/SUSFS, NoMount and Baseband Guard don't exist in the stock kernel,
#   so their options and menus are removed outright (an "is not set" line would
#   still name them), and baseband_guard is dropped from CONFIG_LSM.
# - Blank lines next to removed text are written the way Kconfig would have
#   written them without it; untouched parts of the file stay byte-identical.

function is_option(s) {
    return s ~ /^CONFIG_/ || s ~ /^# CONFIG_[A-Za-z0-9_]* is not set$/
}

function emit(s) {
    if (!removed) {
        for (; blanks > 0; blanks--)
            print ""
    } else if (blanks > 0 && (s == "#" || (is_option(s) && last ~ /^# end of /))) {
        # Kconfig prints a blank line before a menu header, and before an
        # option that directly follows the end of a menu.
        print ""
    }
    blanks = 0
    removed = 0
    print s
    last = s
}

{ line[NR] = $0 }

END {
    n = split(unset_opts, opts, " ")
    for (k = 1; k <= n; k++)
        unset[opts[k]] = 1

    for (i = 1; i <= NR; i++) {
        s = line[i]

        if (s == "") {
            blanks++
            continue
        }

        # A menu is written as "#", "# <title>", "#", ..., "# end of <title>".
        if (s == "#" && i + 2 <= NR && line[i + 2] == "#" &&
            line[i + 1] ~ /^# (KernelSU|Baseband Security Guard)/) {
            title = substr(line[i + 1], 3)
            stop = i + 2
            for (j = i + 3; j <= NR; j++) {
                if (line[j] == "# end of " title) {
                    stop = j
                    break
                }
            }
            i = stop
            removed = 1
            continue
        }

        if (s ~ /^CONFIG_(KSU|NOMOUNT|BBG)(_[A-Z0-9_]*)?=/ ||
            s ~ /^# CONFIG_(KSU|NOMOUNT|BBG)(_[A-Z0-9_]*)? is not set$/) {
            removed = 1
            continue
        }

        if (s ~ /^CONFIG_LSM=/) {
            gsub(/,baseband_guard/, "", s)
            gsub(/baseband_guard,/, "", s)
        }

        eq = index(s, "=")
        if (eq > 0) {
            name = substr(s, 1, eq - 1)
            if (name in unset)
                s = "# " name " is not set"
        }

        emit(s)
    }

    if (!removed)
        for (; blanks > 0; blanks--)
            print ""
}
