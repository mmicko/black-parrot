/**
 *
 * Name:
 *   bp_me_nonsynth_cce_pending_tracer.v
 *
 * Description:
 *
 */

`include "bp_common_defines.svh"
`include "bp_me_defines.svh"

module bp_me_nonsynth_cce_pending_tracer
  import bp_common_pkg::*;
  #(parameter num_way_groups_p = 64
    , parameter width_p        = 3
    , parameter cce_id_width_p = 6
    , localparam trace_file_p = "cce_pending"
    , localparam lg_num_way_groups_lp     = `BSG_SAFE_CLOG2(num_way_groups_p)
  )
  (input                                            clk_i
   , input                                          reset_i
   , input [cce_id_width_p-1:0]                     cce_id_i
   , input                                          w_v_i
   , input [lg_num_way_groups_lp-1:0]               w_wg_i
   , input [width_p-1:0]                            w_val_i
  );

  integer file;
  string file_name;

  always_ff @(negedge reset_i) begin
    file_name = $sformatf("%s_%x.trace", trace_file_p, cce_id_i);
    file      = $fopen(file_name, "w");
  end

  always_ff @(negedge clk_i) begin
    if (~reset_i) begin
      if (w_v_i) begin
        $fdisplay(file, "%12t |: write[%d] := %d", $time, w_wg_i, w_val_i);
      end
    end
  end

endmodule
