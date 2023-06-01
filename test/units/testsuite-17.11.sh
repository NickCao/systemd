#!/usr/bin/env bash
# SPDX-License-Identifier: LGPL-2.1-or-later
set -ex
set -o pipefail

# Test for udevadm verify.

# shellcheck source=test/units/util.sh
. "$(dirname "$0")"/util.sh

# shellcheck disable=SC2317
cleanup() {
    cd /
    rm -rf "${workdir}"
    workdir=
}

workdir="$(mktemp -d)"
trap cleanup EXIT
cd "${workdir}"

cat >"${workdir}/default_output_1_success" <<EOF

1 udev rules files have been checked.
  Success: 1
  Fail:    0
EOF
cat >"${workdir}/default_output_1_fail" <<EOF

1 udev rules files have been checked.
  Success: 0
  Fail:    1
EOF
cat >"${workdir}/output_0_files" <<EOF

0 udev rules files have been checked.
  Success: 0
  Fail:    0
EOF

test_number=0
rules=
exp=
err=
out=
next_test_number() {
    : $((++test_number))

    local num_str
    num_str=$(printf %05d "${test_number}")

    rules="sample-${num_str}.rules"
    exp="sample-${num_str}.exp"
    err="sample-${num_str}.err"
    exo="sample-${num_str}.exo"
    out="sample-${num_str}.out"
}

assert_0() {
    udevadm verify "$@" >"${out}"
    if [ -f "${exo}" ]; then
        diff -u "${exo}" "${out}"
    elif [ -f "${rules}" ]; then
        diff -u "${workdir}/default_output_1_success" "${out}"
    fi

    next_test_number
}

assert_1() {
    local rc
    set +e
    udevadm verify "$@" >"${out}" 2>"${err}"
    rc=$?
    set -e
    assert_eq "$rc" 1

    if [ -f "${exp}" ]; then
        diff -u "${exp}" "${err}"
    fi

    if [ -f "${exo}" ]; then
        diff -u "${exo}" "${out}"
    elif [ -f "${rules}" ]; then
        diff -u "${workdir}/default_output_1_fail" "${out}"
    fi

    next_test_number
}

# initialize variables
next_test_number

assert_0 -h
assert_0 --help
assert_0 -V
assert_0 --version
assert_0 /dev/null

# unrecognized option '--unknown'
assert_1 --unknown
# option requires an argument -- 'N'
assert_1 -N
# --resolve-names= takes "early" or "never"
assert_1 -N now
# option '--resolve-names' requires an argument
assert_1 --resolve-names
# --resolve-names= takes "early" or "never"
assert_1 --resolve-names=now
# Failed to parse rules file ./nosuchfile: No such file or directory
assert_1 ./nosuchfile
# Failed to parse rules file ./nosuchfile: No such file or directory
cat >"${exo}" <<EOF

3 udev rules files have been checked.
  Success: 2
  Fail:    1
EOF
assert_1 /dev/null ./nosuchfile /dev/null

rules_dir='etc/udev/rules.d'
mkdir -p "${rules_dir}"
# No rules files found in $PWD
assert_1 --root="${workdir}"

# Directory without rules.
cp "${workdir}/output_0_files" "${exo}"
assert_0 "${rules_dir}"

# Directory with a loop.
ln -s . "${rules_dir}/loop.rules"
assert_1 "${rules_dir}"
rm "${rules_dir}/loop.rules"

# Empty rules.
touch "${rules_dir}/empty.rules"
assert_0 --root="${workdir}"
: >"${exo}"
assert_0 --root="${workdir}" --no-summary

# Directory with a single *.rules file.
cp "${workdir}/default_output_1_success" "${exo}"
assert_0 "${rules_dir}"

# Combination of --root= and FILEs is not supported.
assert_1 --root="${workdir}" /dev/null
# No rules files found in nosuchdir
assert_1 --root=nosuchdir

cd "${rules_dir}"

# UDEV_LINE_SIZE 16384
printf '%16383s\n' ' ' >"${rules}"
assert_0 "${rules}"

# Failed to parse rules file ${rules}: No buffer space available
printf '%16384s\n' ' ' >"${rules}"
echo "Failed to parse rules file ${rules}: No buffer space available" >"${exp}"
assert_1 "${rules}"

{
    printf 'RUN+="/bin/true",%8174s\\\n' ' '
    printf 'RUN+="/bin/false"%8174s\\\n' ' '
    echo
} >"${rules}"
assert_0 "${rules}"

printf 'RUN+="/bin/true"%8176s\\\n #\n' ' ' ' ' >"${rules}"
echo >>"${rules}"
cat >"${exp}" <<EOF
${rules}:5 Line is too long, ignored.
${rules}: udev rules check failed.
EOF
assert_1 "${rules}"

printf '\\\n' >"${rules}"
cat >"${exp}" <<EOF
${rules}:1 Unexpected EOF after line continuation, line ignored.
${rules}: udev rules check failed.
EOF
assert_1 "${rules}"

test_syntax_error() {
    local rule msg

    rule="$1"; shift
    msg="$1"; shift

    printf '%s\n' "${rule}" >"${rules}"
    cat >"${exp}" <<EOF
${rules}:1 ${msg}
${rules}: udev rules check failed.
EOF
    assert_1 "${rules}"
}

test_syntax_error '=' 'Invalid key/value pair, ignoring.'
test_syntax_error 'ACTION{a}=="b"' 'Invalid attribute for ACTION.'
test_syntax_error 'ACTION:="b"' 'Invalid operator for ACTION.'
test_syntax_error 'ACTION=="b"' 'The line has no effect, ignoring.'
test_syntax_error 'DEVPATH{a}=="b"' 'Invalid attribute for DEVPATH.'
test_syntax_error 'DEVPATH:="b"' 'Invalid operator for DEVPATH.'
test_syntax_error 'KERNEL{a}=="b"' 'Invalid attribute for KERNEL.'
test_syntax_error 'KERNEL:="b"' 'Invalid operator for KERNEL.'
test_syntax_error 'KERNELS{a}=="b"' 'Invalid attribute for KERNELS.'
test_syntax_error 'KERNELS:="b"' 'Invalid operator for KERNELS.'
test_syntax_error 'SYMLINK{a}=="b"' 'Invalid attribute for SYMLINK.'
test_syntax_error 'SYMLINK:="%?"' 'Invalid value "%?" for SYMLINK (char 1: invalid substitution type), ignoring.'
test_syntax_error 'NAME{a}=="b"' 'Invalid attribute for NAME.'
test_syntax_error 'NAME-="b"' 'Invalid operator for NAME.'
test_syntax_error 'NAME+="a"' "NAME key takes '==', '!=', '=', or ':=' operator, assuming '='."
test_syntax_error 'NAME:=""' 'Ignoring NAME="", as udev will not delete any network interfaces.'
test_syntax_error 'NAME="%k"' 'Ignoring NAME="%k", as it will take no effect.'
test_syntax_error 'ENV=="b"' 'Invalid attribute for ENV.'
test_syntax_error 'ENV{a}-="b"' 'Invalid operator for ENV.'
test_syntax_error 'ENV{a}:="b"' "ENV key takes '==', '!=', '=', or '+=' operator, assuming '='."
test_syntax_error 'ENV{ACTION}="b"' "Invalid ENV attribute. 'ACTION' cannot be set."
test_syntax_error 'CONST=="b"' 'Invalid attribute for CONST.'
test_syntax_error 'CONST{a}=="b"' 'Invalid attribute for CONST.'
test_syntax_error 'CONST{arch}="b"' 'Invalid operator for CONST.'
test_syntax_error 'TAG{a}=="b"' 'Invalid attribute for TAG.'
test_syntax_error 'TAG:="a"' "TAG key takes '==', '!=', '=', or '+=' operator, assuming '='."
test_syntax_error 'TAG="%?"' 'Invalid value "%?" for TAG (char 1: invalid substitution type), ignoring.'
test_syntax_error 'TAGS{a}=="b"' 'Invalid attribute for TAGS.'
test_syntax_error 'TAGS:="a"' 'Invalid operator for TAGS.'
test_syntax_error 'SUBSYSTEM{a}=="b"' 'Invalid attribute for SUBSYSTEM.'
test_syntax_error 'SUBSYSTEM:="b"' 'Invalid operator for SUBSYSTEM.'
test_syntax_error 'SUBSYSTEM=="bus", NAME="b"' '"bus" must be specified as "subsystem".'
test_syntax_error 'SUBSYSTEMS{a}=="b"' 'Invalid attribute for SUBSYSTEMS.'
test_syntax_error 'SUBSYSTEMS:="b"' 'Invalid operator for SUBSYSTEMS.'
test_syntax_error 'DRIVER{a}=="b"' 'Invalid attribute for DRIVER.'
test_syntax_error 'DRIVER:="b"' 'Invalid operator for DRIVER.'
test_syntax_error 'DRIVERS{a}=="b"' 'Invalid attribute for DRIVERS.'
test_syntax_error 'DRIVERS:="b"' 'Invalid operator for DRIVERS.'
test_syntax_error 'ATTR="b"' 'Invalid attribute for ATTR.'
test_syntax_error 'ATTR{%}="b"' 'Invalid attribute "%" for ATTR (char 1: invalid substitution type), ignoring.'
test_syntax_error 'ATTR{a}-="b"' 'Invalid operator for ATTR.'
test_syntax_error 'ATTR{a}+="b"' "ATTR key takes '==', '!=', or '=' operator, assuming '='."
test_syntax_error 'ATTR{a}="%?"' 'Invalid value "%?" for ATTR (char 1: invalid substitution type), ignoring.'
test_syntax_error 'SYSCTL=""' 'Invalid attribute for SYSCTL.'
test_syntax_error 'SYSCTL{%}="b"' 'Invalid attribute "%" for SYSCTL (char 1: invalid substitution type), ignoring.'
test_syntax_error 'SYSCTL{a}-="b"' 'Invalid operator for SYSCTL.'
test_syntax_error 'SYSCTL{a}+="b"' "SYSCTL key takes '==', '!=', or '=' operator, assuming '='."
test_syntax_error 'SYSCTL{a}="%?"' 'Invalid value "%?" for SYSCTL (char 1: invalid substitution type), ignoring.'
test_syntax_error 'ATTRS=""' 'Invalid attribute for ATTRS.'
test_syntax_error 'ATTRS{%}=="b", NAME="b"' 'Invalid attribute "%" for ATTRS (char 1: invalid substitution type), ignoring.'
test_syntax_error 'ATTRS{a}-="b"' 'Invalid operator for ATTRS.'
test_syntax_error 'ATTRS{device/}!="a", NAME="b"' "'device' link may not be available in future kernels."
test_syntax_error 'ATTRS{../}!="a", NAME="b"' 'Direct reference to parent sysfs directory, may break in future kernels.'
test_syntax_error 'TEST{a}=="b"' "Failed to parse mode 'a': Invalid argument"
test_syntax_error 'TEST{0}=="%", NAME="b"' 'Invalid value "%" for TEST (char 1: invalid substitution type), ignoring.'
test_syntax_error 'TEST{0644}="b"' 'Invalid operator for TEST.'
test_syntax_error 'PROGRAM{a}=="b"' 'Invalid attribute for PROGRAM.'
test_syntax_error 'PROGRAM-="b"' 'Invalid operator for PROGRAM.'
test_syntax_error 'PROGRAM=="%", NAME="b"' 'Invalid value "%" for PROGRAM (char 1: invalid substitution type), ignoring.'
test_syntax_error 'IMPORT="b"' 'Invalid attribute for IMPORT.'
test_syntax_error 'IMPORT{a}="b"' 'Invalid attribute for IMPORT.'
test_syntax_error 'IMPORT{a}-="b"' 'Invalid operator for IMPORT.'
test_syntax_error 'IMPORT{file}=="%", NAME="b"' 'Invalid value "%" for IMPORT (char 1: invalid substitution type), ignoring.'
test_syntax_error 'IMPORT{builtin}!="foo"' 'Unknown builtin command: foo'
test_syntax_error 'RESULT{a}=="b"' 'Invalid attribute for RESULT.'
test_syntax_error 'RESULT:="b"' 'Invalid operator for RESULT.'
test_syntax_error 'OPTIONS{a}="b"' 'Invalid attribute for OPTIONS.'
test_syntax_error 'OPTIONS-="b"' 'Invalid operator for OPTIONS.'
test_syntax_error 'OPTIONS!="b"' 'Invalid operator for OPTIONS.'
test_syntax_error 'OPTIONS+="link_priority=a"' "Failed to parse link priority 'a': Invalid argument"
test_syntax_error 'OPTIONS:="log_level=a"' "Failed to parse log level 'a': Invalid argument"
test_syntax_error 'OPTIONS="a", NAME="b"' "Invalid value for OPTIONS key, ignoring: 'a'"
test_syntax_error 'OWNER{a}="b"' 'Invalid attribute for OWNER.'
test_syntax_error 'OWNER-="b"' 'Invalid operator for OWNER.'
test_syntax_error 'OWNER!="b"' 'Invalid operator for OWNER.'
test_syntax_error 'OWNER+="0"' "OWNER key takes '=' or ':=' operator, assuming '='."
test_syntax_error 'OWNER=":nosuchuser:"' "Unknown user ':nosuchuser:', ignoring."
test_syntax_error 'GROUP{a}="b"' 'Invalid attribute for GROUP.'
test_syntax_error 'GROUP-="b"' 'Invalid operator for GROUP.'
test_syntax_error 'GROUP!="b"' 'Invalid operator for GROUP.'
test_syntax_error 'GROUP+="0"' "GROUP key takes '=' or ':=' operator, assuming '='."
test_syntax_error 'GROUP=":nosuchgroup:"' "Unknown group ':nosuchgroup:', ignoring."
test_syntax_error 'MODE{a}="b"' 'Invalid attribute for MODE.'
test_syntax_error 'MODE-="b"' 'Invalid operator for MODE.'
test_syntax_error 'MODE!="b"' 'Invalid operator for MODE.'
test_syntax_error 'MODE+="0"' "MODE key takes '=' or ':=' operator, assuming '='."
test_syntax_error 'MODE="%"' 'Invalid value "%" for MODE (char 1: invalid substitution type), ignoring.'
test_syntax_error 'SECLABEL="b"' 'Invalid attribute for SECLABEL.'
test_syntax_error 'SECLABEL{a}="%"' 'Invalid value "%" for SECLABEL (char 1: invalid substitution type), ignoring.'
test_syntax_error 'SECLABEL{a}!="b"' 'Invalid operator for SECLABEL.'
test_syntax_error 'SECLABEL{a}-="b"' 'Invalid operator for SECLABEL.'
test_syntax_error 'SECLABEL{a}:="b"' "SECLABEL key takes '=' or '+=' operator, assuming '='."
test_syntax_error 'RUN=="b"' 'Invalid operator for RUN.'
test_syntax_error 'RUN-="b"' 'Invalid operator for RUN.'
test_syntax_error 'RUN="%"' 'Invalid value "%" for RUN (char 1: invalid substitution type), ignoring.'
test_syntax_error 'RUN{builtin}+="foo"' "Unknown builtin command 'foo', ignoring."
test_syntax_error 'GOTO{a}="b"' 'Invalid attribute for GOTO.'
test_syntax_error 'GOTO=="b"' 'Invalid operator for GOTO.'
test_syntax_error 'NAME="a", GOTO="b"' 'GOTO="b" has no matching label, ignoring.'
test_syntax_error 'GOTO="a", GOTO="b"
LABEL="a"' 'Contains multiple GOTO keys, ignoring GOTO="b".'
test_syntax_error 'LABEL{a}="b"' 'Invalid attribute for LABEL.'
test_syntax_error 'LABEL=="b"' 'Invalid operator for LABEL.'
test_syntax_error 'LABEL="b"' 'LABEL="b" is unused.'
test_syntax_error 'a="b"' "Invalid key 'a'."
test_syntax_error 'KERNEL=="", KERNEL=="?*", NAME="a"' 'conflicting match expressions, the line has no effect.'
test_syntax_error 'KERNEL=="abc", KERNEL!="abc", NAME="b"' 'conflicting match expressions, the line has no effect.'
test_syntax_error 'KERNEL=="|a|b", KERNEL!="b|a|", NAME="c"' 'conflicting match expressions, the line has no effect.'
test_syntax_error 'KERNEL=="a|b", KERNEL=="c|d|e", NAME="f"' 'conflicting match expressions, the line has no effect.'
# shellcheck disable=SC2016
test_syntax_error 'ENV{DISKSEQ}=="?*", ENV{DEVTYPE}!="partition", ENV{DISKSEQ}!="?*", ENV{ID_IGNORE_DISKSEQ}!="1", SYMLINK+="disk/by-diskseq/$env{DISKSEQ}"' \
                  'conflicting match expressions, the line has no effect.'
test_syntax_error 'ACTION=="a*", ACTION=="bc*", NAME="d"' 'conflicting match expressions, the line has no effect.'
test_syntax_error 'ACTION=="a*|bc*", ACTION=="d*|ef*", NAME="g"' 'conflicting match expressions, the line has no effect.'
test_syntax_error 'KERNEL!="", KERNEL=="?*", NAME="a"' 'duplicate expressions.'
test_syntax_error 'KERNEL=="|a|b", KERNEL=="b|a|", NAME="c"' 'duplicate expressions.'
# shellcheck disable=SC2016
test_syntax_error 'ENV{DISKSEQ}=="?*", ENV{DEVTYPE}!="partition", ENV{DISKSEQ}=="?*", ENV{ID_IGNORE_DISKSEQ}!="1", SYMLINK+="disk/by-diskseq/$env{DISKSEQ}"' \
                  'duplicate expressions.'
test_syntax_error ',ACTION=="a", NAME="b"' 'Stray leading comma.'
test_syntax_error ' ,ACTION=="a", NAME="b"' 'Stray leading comma.'
test_syntax_error ', ACTION=="a", NAME="b"' 'Stray leading comma.'
test_syntax_error 'ACTION=="a", NAME="b",' 'Stray trailing comma.'
test_syntax_error 'ACTION=="a", NAME="b", ' 'Stray trailing comma.'
test_syntax_error 'ACTION=="a" NAME="b"' 'A comma between tokens is expected.'
test_syntax_error 'ACTION=="a",, NAME="b"' 'More than one comma between tokens.'
test_syntax_error 'ACTION=="a" , NAME="b"' 'Stray whitespace before comma.'
test_syntax_error 'ACTION=="a",NAME="b"' 'Whitespace after comma is expected.'
test_syntax_error 'RESULT=="a", PROGRAM="b"' 'Reordering RESULT check after PROGRAM assignment.'
test_syntax_error 'RESULT=="a*", PROGRAM="b", RESULT=="*c", PROGRAM="d"' \
        'Reordering RESULT check after PROGRAM assignment.'

cat >"${rules}" <<'EOF'
KERNEL=="a|b", KERNEL=="a|c", NAME="d"
KERNEL=="a|b", KERNEL!="a|c", NAME="d"
KERNEL!="a", KERNEL!="b", NAME="c"
KERNEL=="|a", KERNEL=="|b", NAME="c"
KERNEL=="*", KERNEL=="a*", NAME="b"
KERNEL=="a*", KERNEL=="c*|ab*", NAME="d"
PROGRAM="a", RESULT=="b"
EOF
assert_0 "${rules}"

echo 'GOTO="a"' >"${rules}"
cat >"${exp}" <<EOF
${rules}:1 GOTO="a" has no matching label, ignoring.
${rules}:1 The line has no effect any more, dropping.
${rules}: udev rules check failed.
EOF
assert_1 "${rules}"

cat >"${rules}" <<'EOF'
GOTO="a"
LABEL="a"
EOF
assert_0 "${rules}"

cat >"${rules}" <<'EOF'
GOTO="b"
LABEL="b"
LABEL="b"
EOF
cat >"${exp}" <<EOF
${rules}:3 LABEL="b" is unused.
${rules}: udev rules check failed.
EOF
assert_1 "${rules}"

cat >"${rules}" <<'EOF'
GOTO="a"
LABEL="a", LABEL="b"
EOF
cat >"${exp}" <<EOF
${rules}:2 Contains multiple LABEL keys, ignoring LABEL="a".
${rules}:1 GOTO="a" has no matching label, ignoring.
${rules}:1 The line has no effect any more, dropping.
${rules}:2 LABEL="b" is unused.
${rules}: udev rules check failed.
EOF
assert_1 "${rules}"

cat >"${rules}" <<'EOF'
KERNEL!="", KERNEL=="?*", KERNEL=="", NAME="a"
EOF
cat >"${exp}" <<EOF
${rules}:1 duplicate expressions.
${rules}:1 conflicting match expressions, the line has no effect.
${rules}: udev rules check failed.
EOF
assert_1 "${rules}"

cat >"${rules}" <<'EOF'
ACTION=="a"NAME="b"
EOF
cat >"${exp}" <<EOF
${rules}:1 A comma between tokens is expected.
${rules}:1 Whitespace between tokens is expected.
${rules}: udev rules check failed.
EOF
assert_1 "${rules}"

cat >"${rules}" <<'EOF'
ACTION=="a" ,NAME="b"
EOF
cat >"${exp}" <<EOF
${rules}:1 Stray whitespace before comma.
${rules}:1 Whitespace after comma is expected.
${rules}: udev rules check failed.
EOF
assert_1 "${rules}"

# udevadm verify --root
sed "s|sample-[0-9]*.rules|${workdir}/${rules_dir}/&|" sample-*.exp >"${workdir}/${exp}"
cd -
assert_1 --root="${workdir}"
cd -

# udevadm verify path/
sed "s|sample-[0-9]*.rules|${workdir}/${rules_dir}/&|" sample-*.exp >"${workdir}/${exp}"
cd -
assert_1 "${rules_dir}"
cd -

exit 0
