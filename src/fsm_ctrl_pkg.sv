/*
 * 128-bit programmable RX/TX state format
 * --------------------------------------
 * Decision inputs:
 *    7:0  synchronized pad levels
 *   15:8  pad rising-edge pulses
 *   23:16 pad falling-edge pulses
 *   31:24 fixed misc vector; see fsm_misc_pkg
 *
 * LUT indexing:
 *   truth[{input2, input1, input0}]
 *   input0 is selected by lutN_addr[0].
 *
 * Branch priority and next state:
 *   A1: LUT1 true                 -> jump_target1
 *   A2: LUT1 false, LUT2 true     -> jump_target2
 *   A3: both false               -> hold, or increment if default_advance
 *
 * action[i] = {A1[i], A2[i], A3[i]}.
 * Select one branch column to obtain one 23-bit RX or TX action.
 * Actions execute on every enabled system-clock edge, including self-loops.
 * Toggles, events, and transfer requests therefore need event qualification.
 *
 * RX:
 *   capture requests a pad snapshot.
 *   Accepted serialized bits feed the receive assembler and matcher.
 *   commit publishes a pending assembled receive unit, including a partial
 *   unit if supported. It is NOT packet validation or CRC-based filtering.
 *   Accepted commit consumes that pending unit exactly once.
 *   reset_data cancels unpublished RX data; it does not flush the host FIFO.
 *
 * Matcher:
 *   Three setup-configured patterns have values, masks, and lengths.
 *   A shared rolling window advances on accepted serialized RX bits,
 *   independently of commit. Match is false until enough bits are valid.
 *   match_sel updates a REGISTER on the action edge; its effect is visible
 *   afterward. Never derive the current LUT condition combinationally from
 *   the branch-selected match_sel action.
 *   Changing match_sel does not clear the window.
 *   match_clear clears its window/valid history and overrides a same-edge
 *   matcher shift. Pattern match reflects the current window, not a sticky
 *   success. RX bit count and matcher must track the same processed bits.
 *
 * TX:
 *   load permits internal payload prefetch/assembly. Holding it high allows
 *   automatic filling while internal staging has capacity.
 *   advance requests a protocol-timed payload launch/consumption.
 *   Prefetch must not change the currently driven data group.
 *   DATA_TX holds the last launched group until another accepted advance.
 *   reset_data cancels unpublished TX staging; it does not flush the FIFO
 *   or change the currently driven group.
 *
 * Actual transfers require request && ready/valid acceptance. The RTL must
 * not advance a transaction as though a rejected transfer succeeded.
 * Externally clocked capture events cannot simply be retried later.
 *
 * Counter limits and the cycle preset are host-configured before execution.
 * Actions never rewrite limits. Cycle LOAD_PRESET loads the COUNT.
 * Limit conditions mean count >= limit; zero limits are therefore true.
 * Cycle/aux INCREMENT adds one on the action edge.
 * RX bit count advances on processed RX bits; TX bit count advances on
 * accepted payload launches, adding the number of payload bits launched.
 * bit_clear overrides same-edge bit-count increments.
 * reset_data overrides same-edge data capture/load/commit/advance.
 *
 * Each FSM owns flag0 and flag1:
 *   flag0 = local working flag, visible in its own misc vector.
 *   flag1 = outgoing handshake flag, visible in its partner's misc vector.
 *
 * Pad maps, masks, open-drain enables, clock/control drive enables, pattern
 * configuration, and counters are outside this state word.
 * Clock/control outputs are independent of data_mode. On open-drain pads,
 * logical HIGH means release. Data and control mappings must not conflict.
 *
 * CRC controls are reserved for future RX CRC hardware. Write them zero
 * until implemented; MATCH_CRC must report false while CRC is unavailable.
 * Future crc_gate eligibility must remain associated with queued RX bits.
 * There is no TX CRC generation defined by this format.
 *
 * Reserved action bits must be written zero and ignored by the RTL.
 *
 * Packed state layout:
 *   127:113 lut1_addr       112:98 lut2_addr
 *    97:90  lut1_truth       89:82 lut2_truth
 *    81:76  jump_target1     75:70 jump_target2
 *       69  default_advance  68:0 action
 *
 * This package defines an interface; it does not implement the datapath,
 * handshakes, synchronizers, or synchronous state-memory fetch timing.
 */

package fsm_ctrl_pkg;

// 128b state word supporting 64 FSM states
localparam int unsigned COND_SEL_W       = 5;
localparam int unsigned ACTION_W         = 23;
localparam int unsigned BRANCH_COUNT     = 3;

// [RX/TX] Cycle counter controls
typedef enum logic [1:0] {
    CYCLE_HOLD        = 2'b00,
    CYCLE_INCREMENT   = 2'b01,
    CYCLE_CLEAR       = 2'b10,
    CYCLE_LOAD_PRESET = 2'b11
} cycle_cmd_e;

// [RX/TX] Auxiliary counter controls
typedef enum logic [1:0] {
    AUX_HOLD      = 2'b00,
    AUX_INCREMENT = 2'b01,
    AUX_CLEAR     = 2'b10,
    AUX_RESERVED  = 2'b11  // Treat as HOLD; does not load a limit.
} aux_cmd_e;

// [RX/TX] Auxiliary flag controls
typedef enum logic [1:0] {
    FLAG_HOLD     = 2'b00,
    FLAG_CLEAR    = 2'b01,
    FLAG_SET      = 2'b10,
    FLAG_TOGGLE   = 2'b11 
} flag_cmd_e;

// [RX] Selects what user defined pattern RX should match against (START, STOP, ADDR, etc)
typedef enum logic [1:0] {
    MATCH_PATTERN1     = 2'b00,
    MATCH_PATTERN2     = 2'b01,
    MATCH_PATTERN3     = 2'b10,
    MATCH_CRC          = 2'b11      // CRC needs to be enabled for this to be valid
} match_sel_e;

// [TX] Controls designated clock pad if it exists
typedef enum logic [1:0] {
    CLOCK_HOLD   = 2'b00,
    CLOCK_LOW    = 2'b01,
    CLOCK_HIGH   = 2'b10,
    CLOCK_TOGGLE = 2'b11
} clock_cmd_e;

// [TX] Controls the bus direction for the designated data pad(s) if they are bidirectional
typedef enum logic [1:0] {
    DATA_RELEASE = 2'b00,   // uio_oe = 0 (treat as input for high impedance)
    DATA_TX      = 2'b01,
    DATA_ZERO    = 2'b10,
    DATA_ONE     = 2'b11
} data_mode_e;

// Packed views of ONE selected action. Field order matches the indices.
typedef struct packed {
    logic       reserved1;    // 22
    logic       reserved0;    // 21
    logic       host_event;   // 20
    logic       crc_gate;     // 19: eligibility, qualified by accepted RX bit
    logic       crc_init;     // 18: takes priority over CRC update
    match_sel_e match_sel;    // 17:16 pattern selection
    flag_cmd_e  flag1_cmd;    // 15:14 outgoing handshake flag
    flag_cmd_e  flag0_cmd;    // 13:12 local working flag
    logic [1:0] reserved2;    // 11:10 may put a match_gate here?
    aux_cmd_e   aux1_cmd;     // 9:8
    aux_cmd_e   aux0_cmd;     // 7:6
    cycle_cmd_e cycle_cmd;    // 5:4
    logic       bit_clear;    // 3: overrides automatic bit-count increment
    logic       reset_data;   // 2: cancel pending RX data; not a FIFO flush
    logic       commit;       // 1: downstream RX-buffer commit request
    logic       capture;      // 0: request a pad snapshot if RX is ready
} rx_action_t;

typedef struct packed {
    logic        reserved0;    // 22
    logic        host_event;   // 21
    data_mode_e  data_mode;    // 20:19
    logic        control_level;// 18: direct level, not a toggle or pad index
    clock_cmd_e  clock_cmd;    // 17:16 clock output control
    flag_cmd_e   flag1_cmd;    // 15:14 outgoing handshake flag
    flag_cmd_e   flag0_cmd;    // 13:12 local working flag
    logic [1:0] reserved2;     // 11:10
    aux_cmd_e    aux1_cmd;     // 9:8
    aux_cmd_e    aux0_cmd;     // 7:6
    cycle_cmd_e  cycle_cmd;    // 5:4
    logic        bit_clear;    // 3: overrides automatic bit-count increment
    logic        reset_data;   // 2: cancel pending TX data; not a FIFO flush
    logic        advance;      // 1: accepted payload advance request
    logic        load;         // 0: load payload if available
} tx_action_t;

// Shared physical word; RX and TX interpret its action field differently.
typedef struct packed {
    logic [2:0][COND_SEL_W-1:0] lut1_addr;
    logic [2:0][COND_SEL_W-1:0] lut2_addr;
    logic [7:0]                 lut1_truth;
    logic [7:0]                 lut2_truth;
    state_t                     jump_target1;
    state_t                     jump_target2;
    logic                       default_advance;
    logic [ACTION_W-1:0][BRANCH_COUNT-1:0] action;
} cfg_word;

typedef cfg_word cfg_word_t;  // Preserve the original name and a _t alias.

endpackage