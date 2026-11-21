# Version-one architecture

Decision date: 2026-11-19. This is the initial implementation contract, not a
claim of working hardware. The UART RX milestone implements all 16 instructions
and the host commands described under Host loading and control.
Memory size, clock frequency and protocol rates remain subject to synthesis,
timing analysis and independent protocol tests. Change this document explicitly
if those measurements require a different contract.

## Decisions and rationale

| Item | Decision | Reason |
| --- | --- | --- |
| Architecture | One programmable pin engine; one protocol program at a time | Keeps the first implementation small and testable |
| Protocol logic | UART, SPI and I2C are programs, not fixed protocol peripherals | New protocols must remain possible after fabrication |
| Implementation | Verilog, one rising-edge system clock, clock enables | Matches the imported flow and avoids generated clock domains |
| System clock | Initially 20 MHz, 50 ns per cycle | Adequate cycle budget for the initial protocol targets |
| Program memory | 64 words x 24 bits, reloadable while stopped | 192 bytes; masks, immediates and bounded waits fit simple instructions |
| Memory technology | Synthesized registers and read mux for the first baseline | Establish a portable RTL baseline before custom SRAM or macros |
| Datapath | 6-bit PC, separate 8-bit TX/RX shifters, 8-bit loop counter, 16-bit delay/timeout counter | Enough for serial byte loops without a general-purpose CPU |
| Host access | Separate SPI target, mode 0, MSB first, initially at most 1 MHz | Loading/status never consumes the emulated protocol pins |
| Data buffering | Separate four-byte TX and RX FIFOs | Small bursts can run without a host transfer on every bit |
| Custom layout | Later repeated shift-register/counter macro experiment | Keep a verified standard-cell fallback |

These storage counts are budgets, not area estimates. Synthesize the complete
memory/read path and engine before increasing capacity. The nominal 8x4 tile
allocation is not proof that the design fits.

## Protocol scope

| Program | Initial supported behavior | Deferred behavior |
| --- | --- | --- |
| UART TX | 8N1, LSB first, 9600/19200/38400/57600/115200 baud | Parity, extra stop bits, hardware flow control |
| UART RX | Separate receive program, start-bit qualification, center sampling, stop-bit check, same rates | Simultaneous TX/RX and oversampling receiver |
| SPI controller | Modes 0-3, MSB first, 8-bit transfers, full-duplex shifting, one chip select, up to 1 MHz | SPI target, multiple chip selects, dual/quad I/O |
| I2C controller | 7-bit addressing, reads/writes, START/STOP/repeated START, ACK/NACK, at most 100/400 kHz, bounded clock-stretch waits | I2C target, multi-controller arbitration, 10-bit addresses |

UART transmit and receive are separate uses of the engine. SPI full duplex means
sampling MISO while producing MOSI in one controller program, not two engines.
Host SPI can operate while an engine program runs, subject to the access rules
below. Rate targets must be demonstrated with independent decoders; they are not
current supported capabilities.

At 20 MHz a 1 MHz SPI bit has 20 system cycles. A 100 kHz I2C bit has at least
200 cycles; a 400 kHz bit has at least 50. The assembler must budget instruction
cycles, synchronized-input latency and protocol-specific high/low/setup/hold
requirements, not just add a nominal half-period delay. Clock stretching and
input synchronization can lengthen I2C periods. For UART use a rounded integer
bit period and report its baud error; e.g. 174 cycles gives about 114943 baud
at an actual 20 MHz clock. Programs must be assembled for the clock actually used.

## Block responsibilities

The host SPI front end writes program memory and configuration, pushes TX bytes,
reads RX bytes and reports status. The engine fetches instructions and controls
eight output-value latches, eight output-enable latches, the shifters and counters.
The pin adapter applies open-drain masking and reset/enable safety. All serial
inputs, including host SCK/CS/MOSI and protocol pins, pass through two-flop
synchronizers before use; host SCK is not an internal clock. Constrain and review
these asynchronous inputs and synchronizers in the physical flow.

## Pin contract

The engine uses the host SPI and P0-P7 pin mapping below. TX_READY reports
space in the four-byte TX FIFO while selected and out of reset. RX_VALID
indicates at least one byte is available in the four-byte RX FIFO.

| Tiny Tapeout pin | Engine meaning |
| --- | --- |
| ui[0] | HOST_SCK, input |
| ui[1] | HOST_MOSI, input |
| ui[2] | HOST_CS_N, active-low input |
| ui[3:7] | Unused; not engine inputs in version one |
| uo[0] | HOST_MISO; driven zero outside host reads |
| uo[1] | RUNNING, including instruction stalls |
| uo[2] | Sticky FAULT |
| uo[3] | RX_VALID: RX FIFO is not empty |
| uo[4] | TX_READY: TX FIFO has free space |
| uo[5:7] | Unused; drive zero |
| uio[0] / P0 | General pin; SPI controller CS_N |
| uio[1] / P1 | General pin; SPI MOSI or UART TX |
| uio[2] / P2 | General pin; SPI MISO, UART RX or I2C SCL |
| uio[3] / P3 | General pin; SPI SCK or I2C SDA |
| uio[4:7] / P4-P7 | General programmable pins |

The protocol examples share the upper bidirectional Pmod row, following Tiny
Tapeout's recommended protocol pin positions. Only attach/enable the intended
protocol peripheral. The host interface deliberately uses separate dedicated
inputs/outputs. Its MISO is not tri-stated; do not tie it to another driver's MISO.

## Instruction and execution contract

Each word is opcode[23:20] plus operand[19:0]. The assembler zeros unused operand
bits; the model and RTL reject nonzero reserved bits as an illegal instruction.
P means pin index 0-7, L a logic level, A a word address 0-63, N a count and M an
eight-bit pin mask. The operand fields below are numbered within operand[19:0].

| Opcode | Instruction | Operand fields | Effect |
| --- | --- | --- | --- |
| 0x0 | HALT | All zero | Stop and release all protocol pins |
| 0x1 | OUT M,V | M[15:8], V[7:0] | Atomically replace selected output-value bits |
| 0x2 | OE M,V | M[15:8], V[7:0] | Atomically replace selected output-enable bits |
| 0x3 | DELAY N | N[15:0] | Occupy exactly N cycles; N=0 is illegal |
| 0x4 | WAIT P,L,N | P[19:17], L[16], N[15:0] | Wait for synchronized pin to equal L |
| 0x5 | JMP A | A[5:0] | Unconditional branch |
| 0x6 | LOOP N | N[7:0] | Load loop counter; N=0 is illegal |
| 0x7 | DJNZ A | A[5:0] | Fault if counter=0; otherwise decrement, branch if result is nonzero |
| 0x8 | GET_TX N | N[15:0] | Wait for TX FIFO byte and pop into TX shifter |
| 0x9 | TXBIT P,D | P[2:0], D[3] | Write current TX bit to output latch and shift TX; D=0 LSB first, D=1 MSB first |
| 0xA | RXBIT P,D | P[2:0], D[3] | Shift synchronized sample into RX; D=0 shift right/inject bit 7, D=1 shift left/inject bit 0 |
| 0xB | PUT_RX N | N[15:0] | Wait for RX FIFO space and push RX shifter |
| 0xC | LOAD_TX V | V[7:0] | Load literal TX byte |
| 0xD | BRPIN P,L,A | P[9:7], L[6], A[5:0] | Branch if synchronized pin equals L |
| 0xE | CLEAR_RX | All zero | Clear RX shifter |
| 0xF | TRAP V | V[7:0] | Stop, release pins and latch nonzero program fault code V |

Nonblocking instructions retire on one rising edge with no branch delay slot.
If OUT retires at edge k and the next instruction is OUT, the next write occurs
at k+1. If DELAY N is between them, the next write occurs at k+N+1. TXBIT shifts
zeros into the vacated end; it does not implicitly change OE or a clock pin.

WAIT, GET_TX and PUT_RX check their condition on the first execution edge. Success
on that edge consumes one cycle. N=0 means an unbounded wait; N>0 allows exactly N
checks, one per edge, with success taking priority on the last permitted edge.
Timeout stops and releases pins and sets a distinct sticky fault code. Only a
host abort or reset can terminate an unbounded wait without satisfying it.
Advance PC after successful retirement; fetching beyond the loaded word count
faults rather than wrapping. A branch destination must be inside that count;
validate a conditional destination only when the branch is taken.

The host and engine service FIFOs on the system clock. For the initial model,
arbitrate a host access before an engine access on the same edge. A full/empty
host access returns an error without changing FIFO contents; an engine access
waits. Model this ordering explicitly so simultaneous accesses have one result.

## Host loading and control contract

The ASIC is an SPI target for the host only: CPOL=0/CPHA=0, MSB first, at most
1 MHz at a 20 MHz system clock. Keep CS high at least eight system cycles between
transactions and each SCK high/low at least eight system cycles. Drive MOSI on
falling edges and sample MISO on rising edges. Allow the same minimum settling
time after CS assertion before the first rising SCK edge.

Use one framed request per CS assertion: command byte, payload-length byte,
then that many payload bytes. Keep CS low and clock dummy bytes for the response:
status byte, response-length byte and response data. The ASIC outputs zero while
receiving a request. The falling edge after the last request bit launches the
first response bit. Snapshot response data when accepting a complete request;
commands commit once per complete request. Incomplete requests have no effect;
extra clocks after the response return zero until CS rises. The numeric status
and fault codes for the pulse engine are defined below.

| Command | Payload / response | Access rule |
| --- | --- | --- |
| 0x00 STATUS | No payload; return version=1, running/fault/FIFO flags, fault code, PC, TX count, RX count | Always readable |
| 0x01 STOP | No payload; abort and release pins | Any state; does not clear fault |
| 0x02 BEGIN_LOAD | One byte: word count 1-64; invalidate previous program and clear sequential load index | Stopped only |
| 0x03 WRITE_WORD | Three bytes: word[23:16], word[15:8], word[7:0]; append one word | Stopped, load in progress |
| 0x04 COMMIT_LOAD | No payload; mark valid only if exactly the declared word count was received | Stopped, load in progress |
| 0x05 CONFIG_OD | One-byte open-drain mask | Stopped only |
| 0x06 START | No payload; start valid program at PC=0 with cleared shifters/counters and released pins | Stopped, no fault; preserve FIFO data |
| 0x07 WRITE_TX | One byte to enqueue | May run concurrently with engine |
| 0x08 READ_RX | No payload; dequeue and return one byte if available | May run concurrently with engine |
| 0x09 CLEAR | No payload; clear fault, shifters/counters, FIFO contents and output/OE latches | Stopped only; preserve committed program and OD mask |

The RTL supports commands 0x00 through 0x09. The first response byte is 0
for accepted, 1 for unsupported command, 2 for wrong payload length, 3 for
invalid state, 4 for invalid word count, 5 for a full TX FIFO and 6 for an
empty RX FIFO. A successful READ_RX returns one byte. An empty read returns
status 6 even if PUT_RX enqueues on that edge. With a full FIFO, an accepted
read returns the oldest byte and frees its slot for a simultaneous PUT_RX. A full WRITE_TX is rejected even if GET_TX pops on that
edge. With an empty queue, GET_TX can consume a simultaneous WRITE_TX directly.
The next byte gives the response payload length. A successful STATUS returns six
bytes: version (1), flags (bit 0 RUNNING, bit 1 FAULT, bit 2 RX_VALID, bit 3 TX_READY, other bits zero),
fault code (0 clear, 1 illegal or unimplemented instruction, 2 PC out of range,
3 WAIT timeout, 4 TX timeout, 5 RX timeout, 6 loop underflow, or the TRAP immediate),
PC (including the diagnostic past-end value 64), TX count (0–4) and RX count (0-4).
Commands other than STATUS and READ_RX return zero payload bytes. STATUS snapshots the state just
before execution on the acceptance edge. START raises RUNNING on acceptance;
instruction edge 1 is the next system clock edge. Hold reset low across at
least one rising clock edge with ena high, then keep CS high for at least eight
clocks after releasing reset before beginning a transaction.

Response status reports command acceptance, not engine completion. START never
implicitly clears faults. Reject writes to program/configuration while running.
Reject excess WRITE_WORD requests without altering memory or the load index.
COMMIT_LOAD checks transfer completeness; it is not a checksum or an instruction
validator. Fetch/decode validates instructions at execution. READ_RX pops once at
complete-request acceptance; if its response is interrupted, that byte is consumed
and cannot be recovered by retry. Use STATUS to poll before data transfers.

## Reset, pin safety and external hardware

Assert reset asynchronously and synchronize its release to clk. Mask protocol
OE off during reset and while ena is low. Reset clears control state, OD mask,
output/OE latches, FIFO valid/count state and the program-valid flag; memory
contents need not be reset and must never execute before a complete load/commit.
After selection or power loss, apply reset and reload the program. No nonvolatile
program storage is assumed. Require reset after reselecting the design.

STOP, HALT and any fault release all protocol pins and clear output-value/OE
latches. Programs establish safe idle values with OUT before enabling outputs
with OE. With OD mask bit=1, the physical output value is always zero and physical
OE is requested_OE AND NOT requested_value. Logical one releases the line;
logical zero with OE set pulls it low. This prevents push-pull high drive in
I2C mode. Configure OD mask=0x0C for SCL/SDA before an I2C program; UART/SPI
examples use mask=0. Inactive protocol pins remain inputs.

Use external pull-ups on I2C SCL/SDA, and a pull-up on SPI CS_N if release must
leave the peripheral deselected. UART TX should have a pull-up if idle-high is
required while stopped/reset. Choose pull-up values and any level shifting for
the actual board and bus loading; these are external hardware requirements.

## Implementation order and acceptance gates

### Executable software baseline

The assembler and cycle-level model now implement this ISA. Use
`python scripts/workflow.py test-model` and `python scripts/workflow.py demo`.
Model host operations are atomic calls at the engine boundary, not SPI waveforms.
Reset input is already conditioned; wrapper reset-release synchronization and
physical metastability are outside this model. Protocol inputs do use two
modeled synchronizer stages: a value first sampled on edge 1 is first available
to instruction execution on edge 3. See model/README.md for exact API boundaries.

Sequential fall-through past the final loaded word faults on the next fetch
edge, without wrapping the PC. HALT/TRAP retain the current PC for diagnostics.
CLEAR cancels an in-progress load (which BEGIN_LOAD has already made invalid)
while preserving a previously committed program if no new load has begun.
Program TRAP code zero is illegal. These details are now explicit model contracts
for future RTL comparison. They are not evidence of working hardware.

1. Preserve the original imported commit as a reference and obtain template
   simulation/GDS/precheck results before implementing the engine. The metadata
   change sets the intended 20 MHz constraint; no result is claimed here.
2. Build the cycle model and assembler around this ISA. Prove instruction
   encodings, exact delay/branch cycles, reset, load validity and wait timeouts.
3. Implement host loading, minimal engine and pin safety. Load OUT/DELAY/HALT and
   compare the observed waveform against the model, including pin release.
4. Synthesize the complete register-memory baseline early. Measure mapped area
   and timing; revise this contract if the 8x4 budget or 20 MHz target fails.
5. Add UART TX, then RX, SPI modes 0-3 and I2C with independent protocol checkers,
   error cases, FIFO starvation/overflow, clock stretching and timeout tests.
6. Prove a small custom-macro integration separately before replacing a verified
   engine block. USB, Ethernet, more engines and larger memories stay deferred.

## Sources and provenance

- [Competition architecture, CMOS5L and board requirements](https://tinytapeout.com/competitions/jane-street-tt-protocol-emulator/), checked 2026-11-19.
- [Tiny Tapeout recommended protocol pinouts](https://tinytapeout.com/specs/pinouts/), checked 2026-11-19.
- Imported template commit: 4b1204ab387b5ab94db1d57067051d8d89a2f83c.
