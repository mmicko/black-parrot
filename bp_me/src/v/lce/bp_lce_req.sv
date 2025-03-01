/**
 *  Name:
 *    bp_lce_req.sv
 *
 *  Description:
 *    LCE request handler.
 *
 *    When a cache miss is present to the LCE, the LCE request handler issues a new
 *    LCE request to the coherenece system to request the desired cache block, or to
 *    perform an uncached access.
 *
 */

`include "bp_common_defines.svh"
`include "bp_me_defines.svh"

module bp_lce_req
  import bp_common_pkg::*;
 #(parameter bp_params_e bp_params_p = e_bp_default_cfg
   `declare_bp_proc_params(bp_params_p)

    // parameters specific to this LCE
    , parameter `BSG_INV_PARAM(assoc_p)
    , parameter `BSG_INV_PARAM(sets_p)
    , parameter `BSG_INV_PARAM(block_width_p)
    , parameter fill_width_p = block_width_p

    // maximum number of outstanding transactions
    , parameter credits_p = coh_noc_max_credits_p

    // issue non-exclusive read requests
    , parameter non_excl_reads_p = 0

    , parameter req_invert_clk_p = 0
    , parameter metadata_latency_p = 0

    , localparam block_size_in_bytes_lp = (block_width_p/8)
    , localparam lg_sets_lp = `BSG_SAFE_CLOG2(sets_p)
    , localparam lg_block_size_in_bytes_lp = `BSG_SAFE_CLOG2(block_size_in_bytes_lp)
    , localparam lg_lce_assoc_lp = `BSG_SAFE_CLOG2(lce_assoc_p)

   `declare_bp_bedrock_lce_if_widths(paddr_width_p, lce_id_width_p, cce_id_width_p, lce_assoc_p, lce)
   `declare_bp_cache_engine_if_widths(paddr_width_p, ctag_width_p, sets_p, assoc_p, dword_width_gp, block_width_p, fill_width_p, cache)

    , localparam stat_info_width_lp = `bp_cache_stat_info_width(assoc_p)

    // coherence request size for cached requests
    // block size smaller than 8-bytes not supported
    , localparam bp_bedrock_msg_size_e req_block_size_lp =
      (block_size_in_bytes_lp == 128)
      ? e_bedrock_msg_size_128
      : (block_size_in_bytes_lp == 64)
        ? e_bedrock_msg_size_64
        : (block_size_in_bytes_lp == 32)
          ? e_bedrock_msg_size_32
          : (block_size_in_bytes_lp == 16)
            ? e_bedrock_msg_size_16
            : e_bedrock_msg_size_8
  )
  (
    input                                            clk_i
    , input                                          reset_i

    // LCE Configuration
    , input [lce_id_width_p-1:0]                     lce_id_i
    , input bp_lce_mode_e                            lce_mode_i
    , input                                          sync_done_i

    // LCE Req is able to sink any requests this cycle
    , output logic                                   ready_o

    // Cache-LCE Interface
    // valid_i -> yumi_o handshake
    // metadata arrives in the same cycle as req, or any cycle after, but before the next request
    // can arrive, as indicated by the metadata_v_i signal
    , input [cache_req_width_lp-1:0]                 cache_req_i
    , input                                          cache_req_v_i
    , output logic                                   cache_req_yumi_o
    , input [cache_req_metadata_width_lp-1:0]        cache_req_metadata_i
    , input                                          cache_req_metadata_v_i

    // LCE-Cache Interface
    , output logic                                   credits_full_o
    , output logic                                   credits_empty_o

    // LCE Cmd - LCE Req Interface
    // request complete signal from LCE Cmd module - Cached Load/Store and Uncached Load
    // this signal is raised exactly once, for a single cycle, per request completing, and it
    // can be raised at any time after the LCE request sends out
    , input                                          cache_req_complete_i

    // Uncached Store request complete signal
    , input                                          uc_store_req_complete_i

    // LCE-CCE interface
    // Req: ready->valid
    , output logic [lce_req_header_width_lp-1:0]     lce_req_header_o
    , output logic [cce_block_width_p-1:0]           lce_req_data_o
    , output logic                                   lce_req_v_o
    , input                                          lce_req_ready_then_i
  );

  // parameter checks
  if (metadata_latency_p >= 2)
    $fatal(0,"metadata needs to arrive within one cycle of the request");

  `declare_bp_bedrock_lce_if(paddr_width_p, lce_id_width_p, cce_id_width_p, lce_assoc_p, lce);
  `declare_bp_cache_engine_if(paddr_width_p, ctag_width_p, sets_p, assoc_p, dword_width_gp, block_width_p, fill_width_p, cache);
  `bp_cast_o(bp_bedrock_lce_req_header_s, lce_req_header);
  `bp_cast_i(bp_cache_req_s, cache_req);

  // FSM states
  typedef enum logic [2:0] {
    e_reset
    ,e_ready
    ,e_send_cached_req
    ,e_send_uncached_req
  } lce_req_state_e;
  lce_req_state_e state_n, state_r;

  logic cache_req_v_r;
  bsg_dff_reset_set_clear
   #(.width_p(1))
   cache_req_v_reg
    (.clk_i(clk_i)
     ,.reset_i(reset_i)

     ,.set_i(cache_req_yumi_o)
     ,.clear_i(lce_req_v_o & lce_req_ready_then_i)
     ,.data_o(cache_req_v_r)
     );

  wire req_clk = (req_invert_clk_p ? ~clk_i : clk_i);
  bp_cache_req_s cache_req_r;
  bsg_dff_en
    #(.width_p($bits(bp_cache_req_s)))
    req_reg
     (.clk_i(req_clk)
      ,.en_i(cache_req_yumi_o)
      ,.data_i(cache_req_i)
      ,.data_o(cache_req_r)
      );

  logic cache_req_metadata_v_r;
  bsg_dff_reset_set_clear
   #(.width_p(1)
     ,.clear_over_set_p((metadata_latency_p == 1))
     )
   metadata_v_reg
    (.clk_i(clk_i)
     ,.reset_i(reset_i)

     ,.set_i(cache_req_metadata_v_i)
     ,.clear_i(cache_req_yumi_o)
     ,.data_o(cache_req_metadata_v_r)
     );

  bp_cache_req_metadata_s cache_req_metadata_r;
  bsg_dff_en
   #(.width_p($bits(bp_cache_req_metadata_s)))
   metadata_reg
    (.clk_i(req_clk)

     ,.en_i(cache_req_metadata_v_i)
     ,.data_i(cache_req_metadata_i)
     ,.data_o(cache_req_metadata_r)
     );

  // Outstanding request credit counter
  logic [`BSG_WIDTH(credits_p)-1:0] credit_count_lo;
  wire credit_v_li = cache_req_v_i;
  wire credit_ready_li = cache_req_yumi_o;
  wire credit_returned_li = cache_req_complete_i | uc_store_req_complete_i;
  bsg_flow_counter
    #(.els_p(credits_p))
    req_counter
      (.clk_i(clk_i)
      ,.reset_i(reset_i)
      ,.v_i(credit_v_li)
      ,.ready_i(credit_ready_li)
      ,.yumi_i(credit_returned_li)
      ,.count_o(credit_count_lo)
      );
  assign credits_full_o = (credit_count_lo == credits_p);
  assign credits_empty_o = (credit_count_lo == '0);

  // Request Address to CCE
  logic [cce_id_width_p-1:0] req_cce_id_lo;
  bp_me_addr_to_cce_id
   #(.bp_params_p(bp_params_p))
   req_map
    (.paddr_i(lce_req_header_cast_o.addr)
     ,.cce_id_o(req_cce_id_lo)
     );

  //synopsys translate_off
  always_ff @(negedge clk_i) begin
    if (~reset_i & cache_req_v_r & cache_req_yumi_o
                 & ~(lce_req_v_o & lce_req_ready_then_i)
       )
      $fatal("Cache request overwritten before sending");
  end
  //synopsys translate_on

  always_comb begin
    state_n = state_r;

    ready_o = 1'b0;
    cache_req_yumi_o = 1'b0;

    lce_req_v_o = 1'b0;

    // Request message defaults
    lce_req_header_cast_o = '0;
    lce_req_header_cast_o.payload.dst_id = req_cce_id_lo;
    lce_req_header_cast_o.payload.src_id = lce_id_i;
    lce_req_data_o = '0;

    unique case (state_r)

      e_reset: begin
        state_n = e_ready;
      end

      // Ready for new request
      e_ready: begin
        ready_o = lce_req_ready_then_i & ((lce_mode_i == e_lce_mode_uncached) || sync_done_i);

        // TODO: This could drop uncached stores, if we accept but lce is not ready
        //   in the next cycle
        // Send off a non-blocking request if we have one
        if (cache_req_v_r & (cache_req_r.msg_type == e_uc_store))
          begin
            lce_req_v_o = lce_req_ready_then_i & cache_req_v_r;

            lce_req_data_o[0+:dword_width_gp] = cache_req_r.data[0+:dword_width_gp];
            lce_req_header_cast_o.size = bp_bedrock_msg_size_e'(cache_req_r.size);
            lce_req_header_cast_o.addr = cache_req_r.addr;
            lce_req_header_cast_o.msg_type.req = e_bedrock_req_uc_wr;
          end

        cache_req_yumi_o = cache_req_v_i
          && ((~cache_req_v_r | lce_req_v_o)
              || (ready_o & cache_req_v_i & cache_req_cast_i.msg_type inside {e_uc_load})
              || (ready_o & cache_req_v_i & cache_req_cast_i.msg_type inside {e_miss_store, e_miss_load}
                  & (lce_mode_i inside {e_lce_mode_normal, e_lce_mode_nonspec})
                  & sync_done_i
                  )
              );

        state_n = (cache_req_yumi_o & cache_req_cast_i.msg_type inside {e_miss_store, e_miss_load})
          ? e_send_cached_req
          : (cache_req_yumi_o & cache_req_cast_i.msg_type inside {e_uc_load})
            ? e_send_uncached_req
            : e_ready;
      end

      // Cached Request
      e_send_cached_req: begin
        // valid cache request arrived last cycle (or earlier) and is held in cache_req_r

        // send when port is ready and metadata has arrived
        lce_req_v_o = lce_req_ready_then_i & cache_req_metadata_v_r;

        lce_req_header_cast_o.size = req_block_size_lp;
        lce_req_header_cast_o.addr = cache_req_r.addr;
        lce_req_header_cast_o.msg_type = (cache_req_r.msg_type == e_miss_load)
          ? e_bedrock_req_rd_miss
          : e_bedrock_req_wr_miss;

        lce_req_header_cast_o.payload.lru_way_id = lg_lce_assoc_lp'(cache_req_metadata_r.hit_or_repl_way);
        lce_req_header_cast_o.payload.non_exclusive = (cache_req_r.msg_type == e_miss_load)
          ? (non_excl_reads_p == 1)
            ? e_bedrock_req_non_excl
            : e_bedrock_req_excl
          : e_bedrock_req_excl;

        state_n = lce_req_v_o
          ? e_ready
          : e_send_cached_req;

      end

      // Uncached Request
      e_send_uncached_req: begin
        // valid cache request arrived last cycle (or earlier) and is held in cache_req_r

        // send when port is ready and metadata has arrived
        lce_req_v_o = lce_req_ready_then_i;

        lce_req_header_cast_o.size = bp_bedrock_msg_size_e'(cache_req_r.size);
        lce_req_header_cast_o.addr = cache_req_r.addr;
        lce_req_header_cast_o.msg_type = e_bedrock_req_uc_rd;

        state_n = lce_req_v_o
          ? e_ready
          : e_send_uncached_req;

      end

      default: begin
        state_n = e_reset;
      end
    endcase
  end

  // synopsys sync_set_reset "reset_i"
  always_ff @ (posedge clk_i) begin
    if (reset_i) begin
      state_r <= e_reset;
    end
    else begin
      state_r <= state_n;
    end
  end

endmodule

`BSG_ABSTRACT_MODULE(bp_lce_req)
