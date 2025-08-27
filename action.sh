#!/usr/bin/env bash

# action.sh: run zizmor via Docker

set -euo pipefail

dbg() {
    echo "::debug::${*}"
}

warn() {
    echo "::warning::${*}"
}

err() {
    echo "::error::${*}"
}

die() {
  err "${*}"
  exit 1
}

installed() {
    command -v "${1}" >/dev/null 2>&1
}

output() {
    echo "${1}=${2}" >> "${GITHUB_OUTPUT}"
}

zizmor-summary () {
    format="%-50s%-20s\n"
    
    printf \\n; printf \\n; printf \\n
    printf "SUMMARY OF DETECTED ISSUES PER FILE"
    printf \\n; printf \\n

    printf "$format" "=========" "================"
    printf "$format" "File name" "Number of issues"
    printf "$format" "=========" "================"

    count=0
    while read no_of_occurence workflow_file; do
        printf "$format" "$workflow_file" "$no_of_occurence"
        count=$((count + no_of_occurence))
    done < <(cat | grep -Eo "[^ /]+/([^ /]+/)?.*\.yml" | sort | uniq -c)

    printf "$format" "=========" "================"
    printf "$format" "Total" "$count"
    printf "$format" "=========" "================"
    printf "\nNote: the summary excludes warning surpressed by zizmor."
}

installed docker || die "Cannot run this action without Docker"

[[ "${RUNNER_OS}" != "Linux" ]] && warn "Unsupported runner OS: ${RUNNER_OS}"

output="${RUNNER_TEMP}/zizmor"

version_regex='^v?[0-9]+\.[0-9]+\.[0-9]+$'

[[ "${GHA_ZIZMOR_VERSION}" == "latest" || "${GHA_ZIZMOR_VERSION}" =~ $version_regex ]] \
    || die "'version' must be 'latest' or an exact X.Y.Z version"

arguments=()
arguments+=("--persona=${GHA_ZIZMOR_PERSONA}")

if [[ "${GHA_ZIZMOR_ADVANCED_SECURITY}" == "true" ]]; then
    arguments+=("--format=sarif")
    output "sarif-file" "${output}"
fi

[[ "${GHA_ZIZMOR_ONLINE_AUDITS}" == "true" ]] || arguments+=("--no-online-audits")
[[ -n "${GHA_ZIZMOR_MIN_SEVERITY}" ]] && arguments+=("--min-severity=${GHA_ZIZMOR_MIN_SEVERITY}")
[[ -n "${GHA_ZIZMOR_MIN_CONFIDENCE}" ]] && arguments+=("--min-confidence=${GHA_ZIZMOR_MIN_CONFIDENCE}")

image="ghcr.io/zizmorcore/zizmor:${GHA_ZIZMOR_VERSION#v}"

# Notes:
# - We run the container with ${GITHUB_WORKSPACE} mounted as /workspace
#   and with /workspace as the working directory, so that user inputs
#   like '.' resolve correctly.
# - We pass the GitHub token as an environment variable so that zizmor
#   can run online audits/perform online collection if requested.
# - We pass FORCE_COLOR=1 so that the output is always colored, even
#   though we intentionally don't `docker run -it`.
# - ${GHA_ZIZMOR_INPUTS} is intentionally not quoted, so that
#   it can expand according to the shell's word-splitting rules.
#   However, we put it after `--` so that it can't be interpreted
#   as one or more flags.
#
# shellcheck disable=SC2086
docker run \
    --rm \
    --volume "${GITHUB_WORKSPACE}:/workspace:ro" \
    --workdir "/workspace" \
    --env "GH_TOKEN=${GHA_ZIZMOR_TOKEN}" \
    --env "FORCE_COLOR=1" \
    "${image}" \
    "${arguments[@]}" \
    -- \
    ${GHA_ZIZMOR_INPUTS} \
        | tee "${output}" \

# Output a summary of findings if requested
[[ "${GHA_ZIZMOR_SUMMARY}" == "true" ]] && cat "${output}" | zizmor-summary

