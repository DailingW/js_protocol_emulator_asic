/*
 * Fixed eight-bit misc vector; no programmable routing crossbar.
 *
 * Bit  RX FSM                         TX FSM
 * ---  -----------------------------  -------------------------------
 *  0   own RX bit count >= limit       own TX bit count >= limit
 *  1   own cycle count >= limit        own cycle count >= limit
 *  2   selected RX pattern/CRC match   selected RX pattern/CRC match
 *  3   own aux0 count >= limit         own aux0 count >= limit
 *  4   own aux1 count >= limit         own aux1 count >= limit
 *  5   RX capacity available           complete next TX group available
 *  6   own flag0                      own flag0
 *  7   partner's flag1                partner's flag1
 *
 * RX ready must include serializer/staging capacity and reserved FIFO
 * capacity for the next configured receive unit. It is not merely !full.
 * TX ready means staged data is usable at the next payload launch.
 *
 * Both FSMs see the SAME RX selected-match result:
 *   pattern: enough valid bits && masked window equals masked pattern.
 *   CRC:     CRC hardware enabled && result valid && CRC matched.
 * Until CRC is implemented, selecting CRC must produce zero.
 * Match affects protocol decisions; it does not filter host-bound data.
 *
 * Every FSM owns two flag registers:
 *   flag0 is local working storage.
 *   flag1 is exported to its partner for persistent request/ack handshakes.
 * The misc field named flag1 therefore reads the PARTNER's register.
 *
 * Counter limits remain fixed during execution. Zero limits are true.
 * Overflow/underrun/conflict diagnostics belong in host-readable status.
 *
 * IMPORTANT: packed struct fields are declared MSB first.
 * Declaring bit_count_lim last places it at bit 0.
 *
 * Decision-bus wiring:
 *   conditions = {misc_vector, falling_edges, rising_edges, pad_levels};
 * Each component above is eight bits.
 */
package fsm_misc_pkg;

    localparam int unsigned MISC_W = 8;

    typedef logic [MISC_W-1:0] misc_vector_t;

    // Values are BIT INDICES, not selectable status-source encodings.
    typedef enum logic [2:0] {
        MISC_BIT_COUNT_LIM = 3'd0,
        MISC_CYC_COUNT_LIM = 3'd1,
        MISC_PATTERN_MATCH = 3'd2,
        MISC_AUX0_LIM      = 3'd3,
        MISC_AUX1_LIM      = 3'd4,
        MISC_READY         = 3'd5,
        MISC_FLAG0         = 3'd6,
        MISC_FLAG1         = 3'd7
    } misc_index_e;

    typedef struct packed {
        logic flag1;          // 7: partner's outgoing flag1
        logic flag0;          // 6: own local flag0
        logic ready;          // 5: direction-specific datapath readiness
        logic aux1_lim;       // 4
        logic aux0_lim;       // 3
        logic pattern_match;  // 2: selected RX pattern or future CRC
        logic cyc_count_lim;  // 1
        logic bit_count_lim;  // 0
    } misc_t;

endpackage