#!/usr/bin/env bash
set -euo pipefail

tb_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
hdl_dir=$(cd -- "$tb_dir/../../../.." && pwd)
work_root=$(mktemp -d /tmp/awg-release-a-regression.XXXXXX)
trap 'rm -rf -- "$work_root"' EXIT

scheduler_sources=(
  "$hdl_dir/library/common/ad_mem.v"
  "$hdl_dir/library/util_cdc/sync_gray.v"
  "$hdl_dir/library/util_axis_fifo/util_axis_fifo_address_generator.v"
  "$hdl_dir/library/util_axis_fifo/util_axis_fifo.v"
  "$hdl_dir/projects/awg/common/awg_timed_ctrl.v"
  "$hdl_dir/projects/awg/common/awg_extension.v"
  "$hdl_dir/projects/awg/common/jesd_sysref_sync.v"
)

run_case() {
  local name=$1
  local top=$2
  shift 2
  local case_dir="$work_root/$name"
  mkdir -p -- "$case_dir"
  iverilog -g2012 -I "$tb_dir" -s "$top" -o "$case_dir/sim.vvp" "$@"
  (
    cd -- "$case_dir"
    vvp ./sim.vvp | tee sim.log
  )
  grep -qx 'SUCCESS' "$case_dir/sim.log"
  if grep -q 'FAILED' "$case_dir/sim.log"; then
    return 1
  fi
}

run_case sysref tb_jesd_sysref_sync \
  "$hdl_dir/projects/awg/common/jesd_sysref_sync.v" \
  "$tb_dir/tb_jesd_sysref_sync.v"

run_case sched_dds_mapping testbench \
  "$hdl_dir/library/jesd204/ad_ip_jesd204_tpl_dac/ad_ip_jesd204_tpl_dac_sched_mux.v" \
  "$tb_dir/tb_sched_dds_mapping.v"

run_case sched_dds_samples testbench \
  "$hdl_dir/library/jesd204/ad_ip_jesd204_tpl_dac/ad_ip_jesd204_tpl_dac_sched_mux.v" \
  "$hdl_dir/library/jesd204/ad_ip_jesd204_tpl_dac/ad_ip_jesd204_tpl_dac_output_gate.v" \
  "$hdl_dir/library/xilinx/common/ad_mul.v" \
  "$hdl_dir/library/common/ad_dds_cordic_pipe.v" \
  "$hdl_dir/library/common/ad_dds_sine_cordic.v" \
  "$hdl_dir/library/common/ad_dds_sine.v" \
  "$hdl_dir/library/common/ad_dds_1.v" \
  "$hdl_dir/library/common/ad_dds_2.v" \
  "$hdl_dir/library/common/ad_dds.v" \
  "$tb_dir/tb_sched_dds_samples.v"

run_case tpl_output_gate testbench \
  "$hdl_dir/library/jesd204/ad_ip_jesd204_tpl_dac/ad_ip_jesd204_tpl_dac_output_gate.v" \
  "$tb_dir/tb_tpl_output_gate.v"

scheduler_benches=(
  tb_mode_locked.v
  tb_stream_empty_wait.v
  tb_stream_eof.v
  tb_stream_hard_underrun.v
  tb_stream_low_watermark.v
  tb_stream_overflow_refused.v
  tb_stream_soft_reset_flush.v
  tb_dma_mode_mux.v
  tb_dma_backpressure_full.v
  tb_dma_stop_soft_reset.v
  tb_stream_occupancy_rollover.v
  tb_sideband_irq.v
  tb_sysref_epoch.v
  tb_output_safety.v
)

for bench in "${scheduler_benches[@]}"; do
  run_case "${bench%.v}" testbench \
    "${scheduler_sources[@]}" \
    "$tb_dir/$bench"
done

run_case legacy_axi awg_timed_ctrl_tb \
  "${scheduler_sources[@]}" \
  "$hdl_dir/projects/awg/test/awg_timed_ctrl_tb.v"

run_case extension_c1 testbench \
  "$hdl_dir/projects/awg/common/awg_extension.v" \
  "$tb_dir/tb_awg_extension_c1.v"

# Terminal CDC phase/rate sweep.  Ratios include scheduler-faster-than-AXI,
# AXI-faster-than-scheduler, and near-rational clocks; phase offsets cover every
# integer nanosecond across the smaller half-period.
for axi_half in 3 5 7; do
  for sched_half in 2 4 6; do
    max_phase=$axi_half
    if (( sched_half < max_phase )); then
      max_phase=$sched_half
    fi
    for ((phase = 0; phase < max_phase; phase++)); do
      name="terminal_a${axi_half}_s${sched_half}_p${phase}"
      case_dir="$work_root/$name"
      mkdir -p -- "$case_dir"
      iverilog -g2012 -I "$tb_dir" -s testbench \
        -DAXI_HALF_PERIOD="$axi_half" \
        -DSCHED_HALF_PERIOD="$sched_half" \
        -DSCHED_PHASE_OFFSET="$phase" \
        -o "$case_dir/sim.vvp" \
        "${scheduler_sources[@]}" \
        "$tb_dir/tb_terminal_mailbox.v"
      (
        cd -- "$case_dir"
        vvp ./sim.vvp > sim.log
      )
      grep -qx 'SUCCESS' "$case_dir/sim.log"
      if grep -q 'FAILED' "$case_dir/sim.log"; then
        cat "$case_dir/sim.log"
        exit 1
      fi
    done
  done
done

echo "SUCCESS"
