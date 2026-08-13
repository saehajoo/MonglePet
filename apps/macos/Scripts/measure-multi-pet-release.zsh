#!/bin/zsh

set -euo pipefail

script_dir=${0:A:h}
macos_root=${script_dir:h}
repo_root=${macos_root:h:h}
counts_text=${MONGLEPET_QA_COUNTS:-"1 2 4 8"}
counts=(${=counts_text})
duration=${MONGLEPET_QA_DURATION_SECONDS:-30}
warmup=${MONGLEPET_QA_WARMUP_SECONDS:-5}
movement_mode=${MONGLEPET_QA_MOVEMENT_MODE:-fixed}
provided_app_path=${MONGLEPET_QA_APP_PATH:-}
timestamp=$(date '+%Y%m%d-%H%M%S')
report_path=${MONGLEPET_QA_REPORT_PATH:-"$repo_root/dist/qa/macos-multi-pet-$timestamp.tsv"}

for tool in xcodebuild ps awk date mktemp; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        print -u2 "필요한 명령을 찾을 수 없습니다: $tool"
        exit 1
    fi
done

if [[ "$duration" != <-> || "$duration" -lt 5 ]]; then
    print -u2 "MONGLEPET_QA_DURATION_SECONDS는 5 이상의 정수여야 합니다."
    exit 1
fi
if [[ "$warmup" != <-> || "$warmup" -lt 0 || "$warmup" -ge "$duration" ]]; then
    print -u2 "MONGLEPET_QA_WARMUP_SECONDS는 0 이상이며 측정 시간보다 작아야 합니다."
    exit 1
fi
case "$movement_mode" in
    fixed|cursor-following|free-roaming|cursor-avoiding) ;;
    *)
        print -u2 "지원하지 않는 이동 모드입니다: $movement_mode"
        exit 1
        ;;
esac
for count in $counts; do
    if [[ "$count" != <-> || "$count" -lt 1 || "$count" -gt 64 ]]; then
        print -u2 "펫 수는 1~64 범위의 정수여야 합니다: $count"
        exit 1
    fi
done

work_dir=$(mktemp -d "${TMPDIR%/}/MonglePetMultiPetQA.XXXXXX")
current_pid=""
cleanup() {
    if [[ -n "$current_pid" ]] && kill -0 "$current_pid" 2>/dev/null; then
        kill -TERM "$current_pid" 2>/dev/null || true
        wait "$current_pid" 2>/dev/null || true
    fi
    rm -rf -- "$work_dir"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if [[ -n "$provided_app_path" ]]; then
    app_path=${provided_app_path:A}
else
    derived_data="$work_dir/DerivedData"
    xcodebuild \
        -project "$macos_root/MonglePet.xcodeproj" \
        -scheme MonglePet \
        -configuration Release \
        -destination 'platform=macOS' \
        -derivedDataPath "$derived_data" \
        CODE_SIGNING_ALLOWED=NO \
        build
    app_path="$derived_data/Build/Products/Release/MonglePet.app"
fi

binary_path="$app_path/Contents/MacOS/MonglePet"
if [[ ! -x "$binary_path" ]]; then
    print -u2 "실행할 Release 앱을 찾을 수 없습니다: $binary_path"
    exit 1
fi

mkdir -p "${report_path:h}"
print 'pets\tmode\tduration_seconds\tsamples\taverage_cpu_percent\tpeak_cpu_percent\taverage_rss_mib\tpeak_rss_mib\tinitial_rss_mib\tfinal_rss_mib\trss_growth_mib' > "$report_path"

for count in $counts; do
    sample_path="$work_dir/samples-$count.txt"
    log_path="$work_dir/app-$count.log"
    total_duration=$((duration + warmup + 2))
    LLVM_PROFILE_FILE="$work_dir/profile-$count-%p.profraw" "$binary_path" \
        --ui-testing \
        --qa-active-pet-count "$count" \
        --qa-movement-mode "$movement_mode" \
        --qa-duration-seconds "$total_duration" \
        >"$log_path" 2>&1 &
    current_pid=$!

    sleep "$warmup"
    for ((second = 0; second < duration; second++)); do
        if ! kill -0 "$current_pid" 2>/dev/null; then
            print -u2 "Release workload가 일찍 종료되었습니다: 펫 $count마리"
            sed -n '1,120p' "$log_path" >&2
            exit 1
        fi
        ps -p "$current_pid" -o %cpu= -o rss= | awk 'NF == 2 { print $1, $2 }' >> "$sample_path"
        sleep 1
    done

    wait "$current_pid"
    current_pid=""
    awk -v pets="$count" -v mode="$movement_mode" -v duration="$duration" '
        BEGIN {
            cpu_sum = 0
            cpu_max = 0
            rss_sum = 0
            rss_max = 0
        }
        NF == 2 {
            if (samples == 0) rss_initial = $2
            cpu_sum += $1
            rss_sum += $2
            rss_final = $2
            if ($1 > cpu_max) cpu_max = $1
            if ($2 > rss_max) rss_max = $2
            samples += 1
        }
        END {
            if (samples == 0) exit 1
            printf "%s\t%s\t%s\t%d\t%.3f\t%.3f\t%.1f\t%.1f\t%.1f\t%.1f\t%+.1f\n", \
                pets, mode, duration, samples, cpu_sum / samples, cpu_max, \
                rss_sum / samples / 1024, rss_max / 1024, \
                rss_initial / 1024, rss_final / 1024, \
                (rss_final - rss_initial) / 1024
        }
    ' "$sample_path" | tee -a "$report_path"
done

print "Release 멀티펫 측정 완료: $report_path"
