; ==============================================================
; FILE    : TRAFFIC.ASM
; COURSE  : CPE463 - Computer Architecture
; PROJECT : Final Project - Choice C: Time-Calibrated Traffic Controller
; TOOLING : Compatible with EMU8086 and TASM (Turbo Assembler)
;
; ──────────────────────────────────────────────────────────────
; PROGRAM DESCRIPTION
; ──────────────────────────────────────────────────────────────
; Simulates a real-world traffic light controller for a single
; intersection. The system cycles autonomously:
;
;       GREEN (~30 s) --> YELLOW (~20 s) --> RED (~30 s) --> repeat
;
; During every delay phase the keyboard buffer is polled
; non-destructively so the user can interrupt at any time:
;
;   [P] Emergency Override  - immediately force RED, flash ALERT,
;                             then prompt [C] Continue / [S] Shutdown
;   [Q] Graceful Shutdown   - exit the cycle and terminate
;
; ──────────────────────────────────────────────────────────────
; ARCHITECTURE PILLARS  (per CPE463 Final Project rubric)
; ──────────────────────────────────────────────────────────────
;   [1] "Until" Polling Loop
;           MAIN_LOOP is an infinite JMP-based cycle.
;           It only exits when POLLED_DELAY sets KEY_FLAG=2 ('Q').
;
;   [2] I/O via INT 21h
;           AH=09h  -> print '$'-terminated string (DX = offset)
;           AH=08h  -> read one char without echoing to screen
;           AH=4Ch  -> terminate program (return to DOS)
;
;   [3] State Management  (CMP / Jumps)
;           Three states: GREEN, YELLOW, RED.
;           After each delay, CMP KEY_FLAG + trampoline pattern
;           (JNE SKIP / JMP LABEL) handles quit and override.
;
;   [4] Nested Delay Loops
;           POLLED_DELAY:  outer BX counter  x  inner CX=0FFFFh LOOP
;           SHORT_DELAY:   same structure, no keyboard polling.
;
;   [5] CX / LOOP Sub-Loop  (Functional Sub-Loop)
;           FLASH_LOOP uses CX=8 + LOOP to blink ALERT 8 times.
;           AX/DX are used for inter-blink timing to keep CX clean.
;
;   [6] 'P' Priority Override
;           INT 16h AH=01h peeks the BIOS keyboard buffer each outer
;           POLLED_DELAY iteration.  ZF=0 means a key is waiting.
;           On 'P': KEY_FLAG=1 -> DO_OVERRIDE handler.
; ==============================================================

.MODEL SMALL
; .MODEL SMALL means:
;   - Code segment (CS) and Data segment (DS) are separate but each
;     fits within one 64 KB segment.
;   - Stack is its own segment (SS).
;   - All near CALLs are used (offsets only, no far segment changes).

.STACK 200h
; Reserve 512 bytes for the stack segment.
; Each PUSH uses 2 bytes.  Worst-case nesting here is:
;   CALL SHORT_DELAY  (2-byte ret addr)
;   inside FLASH_LOOP PUSH CX  (2 bytes)
;   inside CALL SET_RECT_COLOR PUSH AX/BX/CX/DX  (8 bytes)
; 512 bytes is more than sufficient.

; ==============================================================
; DATA SEGMENT
; All program text and variables live here.  DS is pointed at
; this segment at program start (MOV AX,@DATA / MOV DS,AX).
; ==============================================================
.DATA

    ; CRLF  (Carriage Return 13 + Line Feed 10)
    ; Used after any string that should end on its own line.
    ; INT 21h AH=09h stops at the '$' character.
    CRLF        DB  13, 10, '$'

    ; ──────────────────────────────────────────────────────────
    ; DASHBOARD BANNER  (drawn at top of every screen)
    ; Uses IBM Code Page 437 box-drawing characters:
    ;   201 = ╔   187 = ╗   200 = ╚   188 = ╝   205 = ═   186 = ║
    ; 41 DUP(205) repeats the horizontal bar character 41 times,
    ; making the box exactly 43 characters wide (║ + 41×═ + ║).
    ; ──────────────────────────────────────────────────────────
    BNR_TOP     DB  201, 41 DUP(205), 187, 13, 10, '$'   ; ╔═══...═══╗
    BNR_TIT     DB  186, '   CITY TRAFFIC MANAGEMENT SYSTEM v1.0   ', 186, 13, 10, '$'
    BNR_CTL     DB  186, '   [P] Emergency Override  [Q] Shutdown  ', 186, 13, 10, '$'
    BNR_BOT     DB  200, 41 DUP(205), 188, 13, 10, '$'   ; ╚═══...═══╝

    ; ──────────────────────────────────────────────────────────
    ; STARTUP / SHUTDOWN STRINGS
    ; Displayed once during boot and once during graceful exit.
    ; ──────────────────────────────────────────────────────────
    INIT_1      DB  '  >> SYSTEM INITIALIZING...               ', 13, 10, '$'
    INIT_2      DB  '  >> SENSOR ARRAY.............. [  OK  ]  ', 13, 10, '$'
    INIT_3      DB  '  >> SIGNAL MODULES............. [  OK  ]  ', 13, 10, '$'
    INIT_4      DB  '  >> ALL SYSTEMS NOMINAL.                  ', 13, 10, '$'
    PRESS_ANY   DB  '     Press any key to begin...            ', 13, 10, '$'
    QUIT_MSG    DB  '  >> [Q] RECEIVED. INITIATING SHUTDOWN... ', 13, 10, '$'
    BYE_MSG     DB  '  >> TRAFFIC SYSTEM SAFELY OFFLINE.       ', 13, 10, '$'
    BYE_MSG2    DB  '  >> GOODBYE.                             ', 13, 10, '$'

    ; ──────────────────────────────────────────────────────────
    ; STATE PANEL STRINGS  (5 lines per state)
    ; Each state has: top border, status line, duration line,
    ; bottom border, and an info ticker line below the box.
    ; The top border reuses the "[ INTERSECTION STATUS ]" label
    ; embedded between two runs of ═ characters.
    ; ──────────────────────────────────────────────────────────

    ; GREEN state strings
    G_TOP       DB  201, 11 DUP(205), '[ INTERSECTION STATUS ]', 7 DUP(205), 187, 13, 10, '$'
    G_MSG       DB  186, '  [  GREEN  ]  >>  Vehicles may proceed  ', 186, 13, 10, '$'
    G_SUB       DB  186, '  Signal Duration: ~30 seconds           ', 186, 13, 10, '$'
    G_BOT       DB  200, 41 DUP(205), 188, 13, 10, '$'
    G_INFO      DB  '  >> Monitoring intersection...           ', 13, 10, '$'

    ; YELLOW state strings
    Y_TOP       DB  201, 11 DUP(205), '[ INTERSECTION STATUS ]', 7 DUP(205), 187, 13, 10, '$'
    Y_MSG       DB  186, '  [ YELLOW ]  >>  Prepare to stop NOW!   ', 186, 13, 10, '$'
    Y_SUB       DB  186, '  Signal Duration: ~20 seconds           ', 186, 13, 10, '$'
    Y_BOT       DB  200, 41 DUP(205), 188, 13, 10, '$'
    Y_INFO      DB  '  >> Caution phase active...              ', 13, 10, '$'

    ; RED state strings
    R_TOP       DB  201, 11 DUP(205), '[ INTERSECTION STATUS ]', 7 DUP(205), 187, 13, 10, '$'
    R_MSG       DB  186, '  [  RED   ]  >>  ALL VEHICLES STOP!!    ', 186, 13, 10, '$'
    R_SUB       DB  186, '  Signal Duration: ~30 seconds           ', 186, 13, 10, '$'
    R_BOT       DB  200, 41 DUP(205), 188, 13, 10, '$'
    R_INFO      DB  '  >> Intersection cleared. Holding red... ', 13, 10, '$'

    ; ──────────────────────────────────────────────────────────
    ; OVERRIDE STRINGS
    ; Shown when 'P' is pressed.  OVR_HDR/MSG1/MSG2 form a
    ; bordered banner.  OVR_SWITCH confirms the transition.
    ; FLASH_MSG is the blinking alert line (printed 8 times).
    ; ──────────────────────────────────────────────────────────
    OVR_HDR     DB  201, 41 DUP(205), 187, 13, 10, '$'
    OVR_MSG1    DB  186, '  !! EMERGENCY OVERRIDE REQUESTED !!     ', 186, 13, 10, '$'
    OVR_MSG2    DB  200, 41 DUP(205), 188, 13, 10, '$'
    OVR_SWITCH  DB  '  >> [P] RECEIVED -- SWITCHING TO RED!   ', 13, 10, '$'
    FLASH_MSG   DB  '  ***  ALERT: EMERGENCY OVERRIDE ACTIVE  ***', 13, 10, '$'

    ; ──────────────────────────────────────────────────────────
    ; POST-OVERRIDE PROMPT STRINGS
    ; After the 8-blink flash sequence the user must explicitly
    ; choose what happens next:
    ;   [C] Continue  -> resumes the normal Green/Yellow/Red cycle
    ;   [S] Shutdown  -> routes to the DO_QUIT handler
    ; ──────────────────────────────────────────────────────────
    OVR_CONT_MSG   DB '  >> OVERRIDE COMPLETE. CHOOSE ACTION:   ', 13, 10, '$'
    OVR_PROMPT_MSG DB '     [C] CONTINUE TO NORMAL CYCLE        ', 13, 10, '$'
    OVR_QUIT_MSG   DB '     [S] SHUTDOWN SYSTEM                 ', 13, 10, '$'

    ; ──────────────────────────────────────────────────────────
    ; KEY_FLAG  (1-byte state variable)
    ; Written by POLLED_DELAY, read by MAIN_LOOP after each delay.
    ;   0 = no key pressed (normal timeout)
    ;   1 = 'P' was pressed  -> jump to DO_OVERRIDE
    ;   2 = 'Q' was pressed  -> jump to DO_QUIT
    ; Reset to 0 at the top of MAIN_LOOP each cycle.
    ; ──────────────────────────────────────────────────────────
    KEY_FLAG    DB  0

; ==============================================================
; CODE SEGMENT
; ==============================================================
.CODE

MAIN PROC
    ; ──────────────────────────────────────────────────────────
    ; SEGMENT REGISTER INITIALIZATION
    ; @DATA is a TASM/MASM assembler token that resolves to the
    ; paragraph address of the .DATA segment at link time.
    ; We load it into AX first because MOV DS,<immediate> is not
    ; a legal 8086 instruction — segment registers can only be
    ; loaded from another register or memory.
    ; ──────────────────────────────────────────────────────────
    MOV AX, @DATA
    MOV DS, AX              ; DS now addresses all .DATA labels

    ; ──────────────────────────────────────────────────────────
    ; INITIAL SCREEN SETUP
    ; Clear any garbage left by DOS before the program started,
    ; then draw the banner so the boot checklist appears inside
    ; a clean, branded frame.
    ; ──────────────────────────────────────────────────────────
    CALL CLEAR_SCREEN       ; Blank the full 80x25 console (BIOS INT 10h)
    CALL SHOW_BANNER        ; Paint the blue header bar (rows 0-3)

    ; ──────────────────────────────────────────────────────────
    ; BOOT CHECKLIST SEQUENCE
    ; Prints four status lines with SHORT_DELAY pauses between
    ; them to simulate a real system initializing.
    ; SHORT_DELAY BX=2 ≈ 1 second at 2994 cycles/ms.
    ; All prints use INT 21h AH=09h with LEA to load DX with
    ; the DS-relative address of each '$'-terminated string.
    ; ──────────────────────────────────────────────────────────
    LEA DX, CRLF            ; Print blank line for visual spacing
    MOV AH, 09h
    INT 21h

    LEA DX, INIT_1          ; ">> SYSTEM INITIALIZING..."
    MOV AH, 09h
    INT 21h
    MOV BX, 2               ; Pause ~1 s before next line
    CALL SHORT_DELAY

    LEA DX, INIT_2          ; ">> SENSOR ARRAY.......... [ OK ]"
    MOV AH, 09h
    INT 21h
    MOV BX, 2
    CALL SHORT_DELAY

    LEA DX, INIT_3          ; ">> SIGNAL MODULES........ [ OK ]"
    MOV AH, 09h
    INT 21h
    MOV BX, 2
    CALL SHORT_DELAY

    LEA DX, INIT_4          ; ">> ALL SYSTEMS NOMINAL."
    MOV AH, 09h
    INT 21h

    LEA DX, CRLF
    MOV AH, 09h
    INT 21h

    LEA DX, PRESS_ANY       ; "Press any key to begin..."
    MOV AH, 09h
    INT 21h

    ; ──────────────────────────────────────────────────────────
    ; GATE: WAIT FOR ANY KEY
    ; INT 21h AH=08h is a blocking read — the CPU halts here
    ; until the user presses something.  AL receives the ASCII
    ; code but we discard it (no CMP follows).
    ; AH=08h differs from AH=01h: it does NOT echo the char to
    ; the screen, keeping the display clean.
    ; ──────────────────────────────────────────────────────────
    MOV AH, 08h
    INT 21h                 ; AL = key pressed (ignored — any key advances)

; ==============================================================
; MAIN TRAFFIC CYCLE  ("Until" Polling Loop — Pillar [1])
;
; Structure:
;   MAIN_LOOP:
;     Clear KEY_FLAG
;     [GREEN  state] -> POLLED_DELAY(BX=60) -> check KEY_FLAG
;     [YELLOW state] -> POLLED_DELAY(BX=40) -> check KEY_FLAG
;     [RED    state] -> POLLED_DELAY(BX=60) -> check KEY_FLAG
;     JMP MAIN_LOOP    <- unconditional restart
;
; The loop never exits through JMP MAIN_LOOP.
; The only exits are JMP DO_QUIT (Q pressed)
; and JMP DO_OVERRIDE (P pressed).
; ==============================================================
MAIN_LOOP:
    ; Reset KEY_FLAG at the start of every full cycle.
    ; Without this, a 'P' press during RED would carry over
    ; into the next GREEN phase and trigger a false override.
    MOV BYTE PTR [KEY_FLAG], 0

    ; ──────────────────────────────────────────────────────────
    ; STATE 1 : GREEN LIGHT
    ; ──────────────────────────────────────────────────────────

    CALL CLEAR_SCREEN
    CALL SHOW_BANNER

    ; Apply Green color theme to the status panel region
    ; (rows 6-10, full width).
    ; Color attribute 2Fh = White text on Dark Green background.
    ; SET_RECT_COLOR calls INT 10h AH=06h (scroll) with AL=0,
    ; which fills the rectangle with the given attribute without
    ; scrolling any content — it just recolors and clears.
    MOV CH, 6               ; Top-left row
    MOV CL, 0               ; Top-left column
    MOV DH, 10              ; Bottom-right row
    MOV DL, 79              ; Bottom-right column (full width)
    MOV BH, 2Fh             ; Color: White on Dark Green
    CALL SET_RECT_COLOR

    ; Move the cursor to row 6, col 0 so the box strings print
    ; inside the colored region we just painted.
    MOV DH, 6
    MOV DL, 0
    CALL SET_CURSOR

    ; Print the 5-line GREEN status panel
    LEA DX, G_TOP           ; ╔══[ INTERSECTION STATUS ]══╗
    MOV AH, 09h
    INT 21h
    LEA DX, G_MSG           ; ║  [  GREEN  ] >> Vehicles may proceed  ║
    MOV AH, 09h
    INT 21h
    LEA DX, G_SUB           ; ║  Signal Duration: ~30 seconds  ║
    MOV AH, 09h
    INT 21h
    LEA DX, G_BOT           ; ╚═══════════════════════════╝
    MOV AH, 09h
    INT 21h
    LEA DX, G_INFO          ; >> Monitoring intersection...
    MOV AH, 09h
    INT 21h

    ; ── GREEN POLLED DELAY ──────────────────────────────────
    ; BX=60 outer iterations.
    ; Each outer pass = one INT 16h poll + CX=0FFFFh inner loop.
    ; At ~2994 cycles/ms: BX=60 ≈ 30 seconds.
    ; POLLED_DELAY will set KEY_FLAG=1 (P) or KEY_FLAG=2 (Q)
    ; and return immediately if either key is detected.
    MOV BX, 120
    CALL POLLED_DELAY

    ; ── KEY FLAG CHECK (Trampoline Pattern) ─────────────────
    ; A direct JE DO_QUIT would be a short jump (±127 bytes).
    ; DO_QUIT and DO_OVERRIDE are further than 127 bytes away,
    ; so TASM would raise a "relative jump out of range" error.
    ; Fix: invert the condition (JNE SKIP), then use a near JMP
    ; which has a full 16-bit offset and can reach anywhere.
    CMP BYTE PTR [KEY_FLAG], 2  ; Was Q pressed?
    JNE SKIP_QUIT_G             ; No -> skip the jump
    JMP DO_QUIT                 ; Yes -> near jump to shutdown
SKIP_QUIT_G:
    CMP BYTE PTR [KEY_FLAG], 1  ; Was P pressed?
    JNE SKIP_OVR_G              ; No -> skip the jump
    JMP DO_OVERRIDE             ; Yes -> near jump to override
SKIP_OVR_G:
    ; Neither key was pressed (normal timeout).
    ; Brief pause so the user sees the end of the GREEN panel
    ; before the screen clears for YELLOW.
    ; BX=3 ≈ 1.5 seconds of non-polled hold.
    MOV BX, 3
    CALL SHORT_DELAY

    ; ──────────────────────────────────────────────────────────
    ; STATE 2 : YELLOW LIGHT
    ; ──────────────────────────────────────────────────────────

    CALL CLEAR_SCREEN
    CALL SHOW_BANNER

    ; Color attribute 60h = Black text on Dark Yellow background.
    ; Same rectangle region as GREEN (rows 6-10, full width).
    MOV CH, 6
    MOV CL, 0
    MOV DH, 10
    MOV DL, 79
    MOV BH, 60h             ; Color: Black on Dark Yellow
    CALL SET_RECT_COLOR

    MOV DH, 6
    MOV DL, 0
    CALL SET_CURSOR

    LEA DX, Y_TOP
    MOV AH, 09h
    INT 21h
    LEA DX, Y_MSG           ; ║  [ YELLOW ] >> Prepare to stop NOW!  ║
    MOV AH, 09h
    INT 21h
    LEA DX, Y_SUB           ; ║  Signal Duration: ~20 seconds  ║
    MOV AH, 09h
    INT 21h
    LEA DX, Y_BOT
    MOV AH, 09h
    INT 21h
    LEA DX, Y_INFO          ; >> Caution phase active...
    MOV AH, 09h
    INT 21h

    ; BX=40 ≈ 20 seconds.
    ; Yellow is longer than the standard 4-second clearance
    ; to make the simulation more observable on screen.
    MOV BX, 40
    CALL POLLED_DELAY

    ; Same trampoline check pattern as GREEN state.
    CMP BYTE PTR [KEY_FLAG], 2
    JNE SKIP_QUIT_Y
    JMP DO_QUIT
SKIP_QUIT_Y:
    CMP BYTE PTR [KEY_FLAG], 1
    JNE SKIP_OVR_Y
    JMP DO_OVERRIDE
SKIP_OVR_Y:
    MOV BX, 3               ; Transition pause before RED
    CALL SHORT_DELAY

    ; ──────────────────────────────────────────────────────────
    ; STATE 3 : RED LIGHT
    ; ──────────────────────────────────────────────────────────

    CALL CLEAR_SCREEN
    CALL SHOW_BANNER

    ; Color attribute 4Fh = White text on Dark Red background.
    MOV CH, 6
    MOV CL, 0
    MOV DH, 10
    MOV DL, 79
    MOV BH, 4Fh             ; Color: White on Dark Red
    CALL SET_RECT_COLOR

    MOV DH, 6
    MOV DL, 0
    CALL SET_CURSOR

    LEA DX, R_TOP
    MOV AH, 09h
    INT 21h
    LEA DX, R_MSG           ; ║  [  RED  ] >> ALL VEHICLES STOP!!  ║
    MOV AH, 09h
    INT 21h
    LEA DX, R_SUB           ; ║  Signal Duration: ~30 seconds  ║
    MOV AH, 09h
    INT 21h
    LEA DX, R_BOT
    MOV AH, 09h
    INT 21h
    LEA DX, R_INFO          ; >> Intersection cleared. Holding red...
    MOV AH, 09h
    INT 21h

    ; BX=60 ≈ 30 seconds.
    MOV BX, 240
    CALL POLLED_DELAY

    CMP BYTE PTR [KEY_FLAG], 2
    JNE SKIP_QUIT_R
    JMP DO_QUIT
SKIP_QUIT_R:
    ; Note: pressing P during RED is intentionally ignored.
    ; The signal is already red, so no override action is needed.
    MOV BX, 3               ; Transition pause before restarting cycle
    CALL SHORT_DELAY

    JMP MAIN_LOOP           ; Unconditional restart -> back to GREEN

; ==============================================================
; HANDLER: DO_OVERRIDE
; Reached when POLLED_DELAY detects 'P' and KEY_FLAG is set to 1.
;
; Execution order:
;   1. Clear screen, draw banner.
;   2. Paint orange header box and print override text.
;   3. FLASH_LOOP (Pillar [5]): blink an ALERT rectangle 8 times.
;      - CX=8 is the blink counter; the LOOP instruction decrements
;        it and jumps back while CX != 0.
;      - AX/DX handle inter-blink timing to avoid touching CX.
;      - Keyboard is polled mid-blink so any keypress can skip
;        the remaining flashes and jump straight to OVR_PROMPT.
;   4. OVR_PROMPT: draw a blue choice box and block-wait for
;      [C] Continue or [S] Shutdown.
; ==============================================================
DO_OVERRIDE:
    CALL CLEAR_SCREEN
    CALL SHOW_BANNER

    ; Paint the override header region orange (rows 5-8).
    ; Color 60h = Black on Dark Yellow (visible "orange" on CGA).
    MOV CH, 5
    MOV CL, 0
    MOV DH, 8
    MOV DL, 79
    MOV BH, 60h
    CALL SET_RECT_COLOR

    ; Position cursor at row 5 to print override banner strings
    ; inside the colored rectangle.
    MOV DH, 5
    MOV DL, 0
    CALL SET_CURSOR

    LEA DX, OVR_HDR         ; ╔═══...═══╗
    MOV AH, 09h
    INT 21h
    LEA DX, OVR_MSG1        ; ║  !! EMERGENCY OVERRIDE REQUESTED !!  ║
    MOV AH, 09h
    INT 21h
    LEA DX, OVR_MSG2        ; ╚═══...═══╝
    MOV AH, 09h
    INT 21h
    LEA DX, OVR_SWITCH      ; >> [P] RECEIVED -- SWITCHING TO RED!
    MOV AH, 09h
    INT 21h

    ; ──────────────────────────────────────────────────────────
    ; FLASH LOOP  (CX / LOOP Sub-Loop — Pillar [5])
    ;
    ; CX = 8: the LOOP instruction decrements CX and jumps back
    ; to FLASH_LOOP while CX is not zero.  This gives exactly
    ; 8 blink iterations.
    ;
    ; Each iteration alternates between:
    ;   Odd  CX (8,6,4,2) -> "bright ON"  frame (red rectangle)
    ;   Even CX (7,5,3,1) -> "dark OFF"   frame (gray rectangle)
    ;
    ; WHY AX/DX FOR TIMING (not SHORT_DELAY):
    ;   SHORT_DELAY internally uses CX (MOV CX,0FFFFh).
    ;   If we CALL SHORT_DELAY here we would need PUSH CX / POP CX
    ;   to protect the flash counter.  Instead, we use AX as the
    ;   inner countdown and DX as the outer pass counter — neither
    ;   interferes with CX, which stays reserved for LOOP.
    ; ──────────────────────────────────────────────────────────
    MOV CX, 8               ; 8 blink iterations total

FLASH_LOOP:
    ; PUSH CX first so that the INT 10h and INT 16h calls below
    ; cannot accidentally clobber the flash counter.
    ; Every code path below this point must POP CX before LOOP.
    PUSH CX

    ; TEST CX,1 performs a bitwise AND of CX with 1.
    ; It does NOT modify CX — it only updates FLAGS.
    ; ZF=0 means bit 0 is set (CX is odd)  -> bright frame
    ; ZF=1 means bit 0 is clear (CX is even) -> dark frame
    TEST CX, 1
    JZ  FL_DARK             ; Even iteration -> dark (off) frame

FL_BRIGHT:
    ; ── Bright (ON) frame ────────────────────────────────────
    ; INT 10h AH=06h with AL=0 fills a screen rectangle with
    ; the given color attribute without any scrolling.
    ; Coordinates: rows 12-14, cols 5-74 (centered alert band).
    ; Color 4Fh = White text on Dark Red.
    MOV AH, 06h
    MOV AL, 0               ; AL=0 means "clear/fill" (no scroll)
    MOV BH, 4Fh             ; White on Dark Red
    MOV CH, 12              ; Top-left row
    MOV CL, 5               ; Top-left column
    MOV DH, 14              ; Bottom-right row
    MOV DL, 74              ; Bottom-right column
    INT 10h                 ; Fill the rectangle red

    ; Reposition cursor inside the red rectangle and print ALERT.
    ; We call INT 10h AH=02h directly here (inline) rather than
    ; via SET_CURSOR because SET_CURSOR would PUSH/POP BX and we
    ; want to keep this path lean inside the tight flash loop.
    MOV AH, 02h
    MOV BH, 0               ; Video page 0
    MOV DH, 13              ; Row 13 (middle of the red band)
    MOV DL, 10              ; Col 10 (left-aligned inside band)
    INT 10h

    LEA DX, FLASH_MSG       ; "***  ALERT: EMERGENCY OVERRIDE ACTIVE  ***"
    MOV AH, 09h
    INT 21h
    JMP FL_DELAY            ; Skip FL_DARK, go to timing section

FL_DARK:
    ; ── Dark (OFF) frame ─────────────────────────────────────
    ; Same INT 10h call, same rectangle, but color 07h = Light
    ; Gray on Black — the "off" state that gives the blink effect.
    MOV AH, 06h
    MOV AL, 0
    MOV BH, 07h             ; Light Gray on Black (normal/off)
    MOV CH, 12
    MOV CL, 5
    MOV DH, 14
    MOV DL, 74
    INT 10h

FL_DELAY:
    ; ── Inter-blink timing delay (~1.25 s per frame) ─────────
    ; Outer loop:  DX counts down from 18
    ; Inner loop:  AX counts down from 0FFFFh (65535)
    ; Total spins: 18 * 65535 = 1,179,630 iterations.
    ; At ~2994 cycles/ms this gives roughly 1.25 seconds per
    ; blink frame — slow enough for the user to clearly see each
    ; flash without the loop feeling sluggish overall.
    ;
    ; The keyboard is polled after each full AX inner pass so
    ; that pressing any key can skip the remaining blinks and
    ; jump directly to OVR_PROMPT.
    MOV DX, 18              ; Outer pass count
FL_WAIT_OUTER:
    MOV AX, 0FFFFh          ; Inner countdown start
FL_WAIT:
    DEC AX                  ; Decrement inner counter
    JNZ FL_WAIT             ; Loop until AX reaches 0

    ; ── Mid-blink keyboard poll ───────────────────────────────
    ; INT 16h AH=01h: peek at BIOS keyboard buffer.
    ; ZF=0 means a key is waiting (buffer NOT empty).
    ; ZF=1 means no key (buffer empty) -> continue timing loop.
    ; We PUSH DX / POP DX because INT 16h may use DX internally
    ; on some BIOS implementations, and we need DX intact for the
    ; outer pass counter.
    PUSH DX
    MOV AH, 01h
    INT 16h                 ; Peek: ZF=0 if key waiting
    POP DX
    JNZ FL_BREAK            ; Key detected -> exit flash early

    DEC DX                  ; One outer pass done
    JNZ FL_WAIT_OUTER       ; Repeat if more outer passes remain

    ; ── End of one full blink cycle ──────────────────────────
    POP CX                  ; Restore flash counter (saved at top of FLASH_LOOP)
    LOOP FLASH_LOOP         ; DEC CX; if CX != 0, jump back to FLASH_LOOP
    JMP OVR_PROMPT          ; All 8 blinks done -> show choice prompt

FL_BREAK:
    ; A key was pressed mid-blink.
    ; Read and discard it from the BIOS buffer with AH=00h so it
    ; doesn't "bleed" into the OVR_PROMPT blocking read below.
    MOV AH, 00h
    INT 16h                 ; Consume the key (AL = char, AH = scan code)
    POP CX                  ; Clean up the PUSH CX at top of FLASH_LOOP
    JMP OVR_PROMPT          ; Skip remaining blinks, show prompt immediately

; ──────────────────────────────────────────────────────────────
; OVR_PROMPT  (Post-override choice screen)
;
; Draws a blue box and presents two choices:
;   [C] Continue -> JMP MAIN_LOOP (resumes normal cycle at GREEN)
;   [S] Shutdown -> JMP DO_QUIT   (graceful shutdown sequence)
;
; INT 21h AH=08h blocks here — the program will not advance
; until a recognized key is pressed.  Any unrecognized key
; simply loops back to WAIT_FOR_CHOICE.
; ──────────────────────────────────────────────────────────────
OVR_PROMPT:
    CALL CLEAR_SCREEN
    CALL SHOW_BANNER

    ; Paint the choice panel blue (rows 6-12).
    ; Color 1Fh = White text on Dark Blue background.
    MOV CH, 6
    MOV CL, 0
    MOV DH, 12
    MOV DL, 79
    MOV BH, 1Fh             ; White on Dark Blue
    CALL SET_RECT_COLOR

    MOV DH, 6
    MOV DL, 0
    CALL SET_CURSOR

    ; Print the three prompt lines inside the blue box.
    LEA DX, OVR_CONT_MSG    ; ">> OVERRIDE COMPLETE. CHOOSE ACTION:"
    MOV AH, 09h
    INT 21h
    LEA DX, CRLF
    MOV AH, 09h
    INT 21h
    LEA DX, OVR_PROMPT_MSG  ; "   [C] CONTINUE TO NORMAL CYCLE"
    MOV AH, 09h
    INT 21h
    LEA DX, CRLF
    MOV AH, 09h
    INT 21h
    LEA DX, OVR_QUIT_MSG    ; "   [S] SHUTDOWN SYSTEM"
    MOV AH, 09h
    INT 21h

WAIT_FOR_CHOICE:
    ; INT 21h AH=08h: blocking read, no echo.
    ; CPU halts here until a key is pressed.
    MOV AH, 08h
    INT 21h                 ; AL = ASCII code of key pressed

    ; Check for 'C' or 'c' -> resume normal traffic cycle
    CMP AL, 'C'
    JE  DO_CONTINUE
    CMP AL, 'c'
    JE  DO_CONTINUE

    ; Check for 'S' or 's' -> initiate shutdown
    CMP AL, 'S'
    JE  DO_SHUTDOWN
    CMP AL, 's'
    JE  DO_SHUTDOWN

    ; Unrecognized key: loop back and wait again
    JMP WAIT_FOR_CHOICE

DO_CONTINUE:
    JMP MAIN_LOOP           ; Resume at GREEN state

DO_SHUTDOWN:
    JMP DO_QUIT             ; Fall through to shutdown handler

; ==============================================================
; HANDLER: DO_QUIT
; Reached via:
;   - POLLED_DELAY detecting 'Q' (KEY_FLAG=2) during any state
;   - [S] choice at OVR_PROMPT
;
; Displays a shutdown acknowledgement, waits ~1.5 s,
; prints a farewell panel, then terminates via INT 21h AH=4Ch.
; AH=4Ch returns control to DOS with an exit code in AL.
; AL=0 means success (no error).
; ==============================================================
DO_QUIT:
    CALL CLEAR_SCREEN
    CALL SHOW_BANNER

    LEA DX, CRLF
    MOV AH, 09h
    INT 21h

    LEA DX, QUIT_MSG        ; ">> [Q] RECEIVED. INITIATING SHUTDOWN..."
    MOV AH, 09h
    INT 21h

    MOV BX, 3               ; Brief dramatic pause (~1.5 s) before farewell
    CALL SHORT_DELAY

    ; Print a clean farewell panel reusing the banner borders.
    LEA DX, BNR_TOP
    MOV AH, 09h
    INT 21h
    LEA DX, BYE_MSG         ; ">> TRAFFIC SYSTEM SAFELY OFFLINE."
    MOV AH, 09h
    INT 21h
    LEA DX, BYE_MSG2        ; ">> GOODBYE."
    MOV AH, 09h
    INT 21h
    LEA DX, BNR_BOT
    MOV AH, 09h
    INT 21h

    ; ── Terminate the program ─────────────────────────────────
    ; INT 21h AH=4Ch is the standard DOS "Exit Process" function.
    ; AL=0 is the return code passed back to the parent shell.
    ; After this interrupt the CPU never returns to our code.
    MOV AH, 4Ch
    MOV AL, 0
    INT 21h

MAIN ENDP

; ==============================================================
; PROCEDURE : SHOW_BANNER
; PURPOSE   : Paints the 4-row dashboard header at the top of
;             the screen using a blue background, then prints
;             the four box-border strings into it.
;
; HOW IT WORKS:
;   1. SET_RECT_COLOR fills rows 0-3 (full width) with color 1Fh
;      (White on Dark Blue) using INT 10h AH=06h AL=0.
;   2. SET_CURSOR moves the cursor to row 0, col 0.
;   3. Five INT 21h AH=09h calls print the banner lines.
;      The last print is a blank CRLF for spacing.
;
; REGISTERS: AH, DX, CH, CL, DH, DL, BH (all via SET_RECT_COLOR
;            and SET_CURSOR which save/restore AX and BX).
; ==============================================================
SHOW_BANNER PROC
    ; Fill the top 4 rows with White-on-Blue color attribute.
    MOV CH, 0               ; Top-left row  = 0
    MOV CL, 0               ; Top-left col  = 0
    MOV DH, 3               ; Bottom-right row  = 3
    MOV DL, 79              ; Bottom-right col  = 79 (full width)
    MOV BH, 1Fh             ; Color: White text on Dark Blue
    CALL SET_RECT_COLOR

    ; Position cursor at top-left so banner strings print correctly.
    MOV DH, 0
    MOV DL, 0
    CALL SET_CURSOR

    ; Print all four banner lines plus trailing newline.
    LEA DX, BNR_TOP         ; ╔═══...═══╗
    MOV AH, 09h
    INT 21h
    LEA DX, BNR_TIT         ; ║   CITY TRAFFIC MANAGEMENT SYSTEM v1.0   ║
    MOV AH, 09h
    INT 21h
    LEA DX, BNR_CTL         ; ║   [P] Emergency Override  [Q] Shutdown  ║
    MOV AH, 09h
    INT 21h
    LEA DX, BNR_BOT         ; ╚═══...═══╝
    MOV AH, 09h
    INT 21h
    LEA DX, CRLF            ; Blank line separating banner from content
    MOV AH, 09h
    INT 21h
    RET
SHOW_BANNER ENDP

; ==============================================================
; PROCEDURE : CLEAR_SCREEN
; PURPOSE   : Blanks the entire 80x25 console and homes the cursor.
;
; HOW IT WORKS:
;   INT 10h AH=06h is the BIOS "Scroll Window Up" function.
;   When AL=0 the entire defined rectangle is cleared (not scrolled).
;   BH=07h sets the fill attribute: Light Gray text on Black.
;   CH/CL=0,0 and DH/DL=24,79 define the full 80x25 screen area.
;
;   After clearing, INT 10h AH=02h moves the cursor to row 0, col 0
;   on video page 0 (BH=0) so subsequent prints start at the top.
;
;   Using BIOS INT 10h (not DOS) ensures this works in all
;   emulators including EMU8086, DOSBox, and JS-DOS.
;
; REGISTERS MODIFIED: AX, BX, CX, DX
; ==============================================================
CLEAR_SCREEN PROC
    MOV AH, 06h             ; BIOS function: Scroll Window Up
    MOV AL, 0               ; AL=0: clear entire window (no scroll)
    MOV BH, 07h             ; Fill attribute: Light Gray on Black
    MOV CH, 0               ; Top-left row    = 0
    MOV CL, 0               ; Top-left col    = 0
    MOV DH, 24              ; Bottom-right row = 24 (row 25 = index 24)
    MOV DL, 79              ; Bottom-right col = 79 (col 80 = index 79)
    INT 10h                 ; Execute clear

    MOV AH, 02h             ; BIOS function: Set Cursor Position
    MOV BH, 0               ; Video page 0 (standard text mode)
    MOV DH, 0               ; Cursor row = 0 (top)
    MOV DL, 0               ; Cursor col = 0 (left)
    INT 10h                 ; Move cursor to home position
    RET
CLEAR_SCREEN ENDP

; ==============================================================
; PROCEDURE : POLLED_DELAY
; PURPOSE   : Timed busy-wait with non-blocking keyboard polling.
;             The delay lasts BX outer iterations, but returns
;             early if P or Q is pressed.
;
; INPUT  : BX = outer loop count.
;              Each outer pass = 1 poll + 65535 inner spins.
;              Calibrated at ~2994 cycles/ms:
;                BX=60 ≈ 30 s,  BX=40 ≈ 20 s,  BX=8 ≈ 4 s
;
; OUTPUT : KEY_FLAG (memory) = 1 if P pressed, 2 if Q pressed.
;          Returns immediately on P or Q (early exit).
;          Returns normally (RET at bottom) if BX reaches 0.
;
; HOW THE NESTED LOOP WORKS:
;   OUTER (BX): each iteration does one keyboard check then runs
;               the full inner loop before decrementing BX.
;   INNER (CX): MOV CX,0FFFFh loads 65535; LOOP POLL_INNER
;               decrements CX and jumps back while CX != 0.
;               This is the "inner busy-wait" (Pillar [4]).
;
; WHY PUSH/POP CX:
;   CX may already hold a value from the calling context (e.g.,
;   the flash counter in FLASH_LOOP when SHORT_DELAY is called).
;   PUSH CX saves the caller's value on the stack before the
;   inner loop overwrites it; POP CX restores it afterward.
;
; WHY INT 16h INSTEAD OF INT 21h AH=0Bh:
;   INT 21h AH=0Bh checks the DOS stdin buffer.  In JS-DOS and
;   some emulators this buffer is not reliably updated during
;   busy-wait loops.  INT 16h reads the BIOS hardware keyboard
;   ring buffer directly and works correctly in all emulators.
;
; REGISTERS MODIFIED: AX, BX, CX (CX saved/restored around LOOP)
; ==============================================================
POLLED_DELAY PROC

POLL_OUTER:
    ; ── Non-blocking keyboard peek (BIOS INT 16h AH=01h) ─────
    ; This does NOT remove the key from the buffer.
    ; Result: ZF=1 if buffer empty (no key), ZF=0 if key waiting.
    MOV AH, 01h
    INT 16h
    JZ  POLL_NO_KEY         ; ZF=1 -> buffer empty, skip to inner delay

    ; ── Read and remove the key from the buffer ───────────────
    ; INT 16h AH=00h: destructive read.
    ; AH = keyboard scan code, AL = ASCII character.
    MOV AH, 00h
    INT 16h                 ; AL = ASCII of pressed key

    ; ── Identify the key via CMP chain ────────────────────────
    ; Each CMP sets flags; JE jumps if Equal (ZF=1).
    ; Both upper and lower case are handled.
    CMP AL, 'P'
    JE  POLL_SET_OVERRIDE
    CMP AL, 'p'
    JE  POLL_SET_OVERRIDE
    CMP AL, 'Q'
    JE  POLL_SET_QUIT
    CMP AL, 'q'
    JE  POLL_SET_QUIT
    ; Any unrecognized key falls through to POLL_NO_KEY
    ; and the delay simply continues.

POLL_NO_KEY:
    ; ── Inner busy-wait loop (CX = 0FFFFh = 65,535 spins) ────
    ; PUSH CX protects any outer CX value before we overwrite it.
    PUSH CX
    MOV CX, 0FFFFh          ; Inner spin count
POLL_INNER:
    LOOP POLL_INNER         ; DEC CX; JNZ POLL_INNER
    POP CX                  ; Restore caller's CX

    ; ── Outer counter decrement and loop back ─────────────────
    DEC BX
    JNZ POLL_OUTER          ; BX != 0 -> do another outer pass
    RET                     ; BX reached 0 -> delay complete, return normally

POLL_SET_OVERRIDE:
    MOV BYTE PTR [KEY_FLAG], 1  ; Signal: P was pressed
    RET                         ; Return early; caller checks KEY_FLAG

POLL_SET_QUIT:
    MOV BYTE PTR [KEY_FLAG], 2  ; Signal: Q was pressed
    RET                         ; Return early; caller checks KEY_FLAG

POLLED_DELAY ENDP

; ==============================================================
; PROCEDURE : SHORT_DELAY
; PURPOSE   : Simple non-polled busy-wait.  Identical loop
;             structure to POLLED_DELAY but without any keyboard
;             checking.  The delay cannot be interrupted.
;
; INPUT  : BX = outer iteration count.
;              BX=2 ≈ 1 s,  BX=3 ≈ 1.5 s,  BX=5 ≈ 2.5 s
;
; USED FOR:
;   - Boot checklist pauses (BX=2 between each INIT line)
;   - State-transition hold (BX=3 after each POLLED_DELAY)
;   - Override header hold  (BX=5 so user can read the message)
;   - Post-flash hold       (BX=6 to let alert log settle)
;
; REGISTERS MODIFIED: BX, CX (CX saved/restored)
; ==============================================================
SHORT_DELAY PROC

SD_OUTER:
    PUSH CX                 ; Protect caller's CX
    MOV CX, 0FFFFh          ; 65,535 inner spins per outer pass
SD_INNER:
    LOOP SD_INNER           ; DEC CX; JNZ SD_INNER
    POP CX                  ; Restore caller's CX

    DEC BX
    JNZ SD_OUTER            ; Repeat while BX != 0
    RET

SHORT_DELAY ENDP

; ==============================================================
; PROCEDURE : SET_RECT_COLOR
; PURPOSE   : Fills a rectangular region of the screen with a
;             given color attribute using BIOS INT 10h AH=06h.
;
; HOW IT WORKS:
;   INT 10h AH=06h is "Scroll Active Page Up."
;   When AL=0 (scroll count = 0) the BIOS interprets this as
;   "clear the window" rather than scrolling.  The cleared area
;   is filled with the BH attribute (color byte).
;   This gives us a fast hardware-accelerated rectangle fill
;   without manually printing spaces or changing text color.
;
; INPUT  : CH = top-left row
;          CL = top-left column
;          DH = bottom-right row
;          DL = bottom-right column
;          BH = color attribute byte
;               Upper nibble = background color (0-7)
;               Lower nibble = foreground/text color (0-F)
;               Example: 2Fh = 0010 0000 | 0000 1111
;                              ^Dark Green ^White text
;
; REGISTERS: All modified registers are saved on the stack
;            (PUSH AX/BX/CX/DX) and fully restored (POP) before
;            RET, so the caller's registers are never disturbed.
; ==============================================================
SET_RECT_COLOR PROC
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX

    MOV AH, 06h             ; BIOS: Scroll Window Up
    MOV AL, 0               ; AL=0 -> clear (fill) mode
    INT 10h                 ; Fill CH/CL -> DH/DL with color BH

    POP DX
    POP CX
    POP BX
    POP AX
    RET
SET_RECT_COLOR ENDP

; ==============================================================
; PROCEDURE : SET_CURSOR
; PURPOSE   : Moves the text cursor to a specific row/column.
;
; HOW IT WORKS:
;   INT 10h AH=02h is the BIOS "Set Cursor Position" function.
;   BH=0 selects video page 0 (the visible page in text mode).
;   DH and DL are the row and column coordinates (0-based).
;
; INPUT  : DH = row    (0 = top of screen,  24 = bottom)
;          DL = column (0 = left of screen, 79 = right)
;
; REGISTERS: AX and BX are saved/restored via PUSH/POP.
;            DH and DL are read but not modified.
; ==============================================================
SET_CURSOR PROC
    PUSH AX
    PUSH BX
    MOV AH, 02h             ; BIOS: Set Cursor Position
    MOV BH, 0               ; Video page 0
    INT 10h                 ; Move cursor to DH:DL
    POP BX
    POP AX
    RET
SET_CURSOR ENDP

END MAIN
; ==============================================================
; END OF FILE : TRAFFIC.ASM
; ==============================================================