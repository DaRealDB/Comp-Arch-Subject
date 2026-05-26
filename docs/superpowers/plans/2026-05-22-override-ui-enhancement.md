# Emergency Override UI Enhancement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enhance the Emergency Override UI by adding color to the header and improving the flashing alert logic.

**Architecture:** Use existing `SET_RECT_COLOR` and `SET_CURSOR` procedures for UI styling. Implement a bit-test on the loop counter to toggle between flashing and solid red attributes.

**Tech Stack:** 8086 Assembly (TASM/EMU8086 compatible).

---

### Task 1: Color the Override Header

**Files:**
- Modify: `C:\Users\Daryl Bacusmo\Downloads\Comp arch\Proj.asm`

- [ ] **Step 1: Locate `DO_OVERRIDE` and add header coloring**

Find `DO_OVERRIDE:` label and insert the coloring logic before printing `OVR_HDR`.

```assembly
DO_OVERRIDE:
    CALL CLEAR_SCREEN
    CALL SHOW_BANNER

    ; --- NEW: Color the Override Header Panel (Dark Yellow: 60h) ---
    MOV CH, 5               ; Top Row 5
    MOV CL, 0               ; Left Col 0
    MOV DH, 9               ; Bottom Row 9
    MOV DL, 79              ; Right Col 79
    MOV BH, 60h             ; Attribute: Black on Dark Yellow
    CALL SET_RECT_COLOR

    ; --- Position cursor to start of colored block ---
    MOV DH, 5
    MOV DL, 0
    CALL SET_CURSOR

    LEA DX, OVR_HDR             ; Print override header panel
    MOV AH, 09h
    INT 21h
    ; ... (rest of existing print calls)
```

- [ ] **Step 2: Commit changes**

```bash
# Since this is a direct edit, we'll verify in the next task.
```

---

### Task 2: Improve Flashing Logic

**Files:**
- Modify: `C:\Users\Daryl Bacusmo\Downloads\Comp arch\Proj.asm`

- [ ] **Step 1: Update `FLASH_LOOP` with alternating attributes**

Modify `FLASH_LOOP` to check the `CX` register (loop counter) and switch between `0CFh` (Flashing Red) and `4Fh` (Solid Dark Red).

```assembly
FLASH_LOOP:
    ; --- Improved Flashing Logic: Toggle between flashing and solid red ---
    MOV BH, 0CFh            ; Default: White on Flashing Red
    TEST CX, 1              ; Is CX odd?
    JZ USE_SOLID            ; If even, use solid red for alternating frames
    JMP APPLY_COLOR
USE_SOLID:
    MOV BH, 4Fh             ; Solid Dark Red (for environments without blink)
APPLY_COLOR:
    MOV CH, 12              ; Top Row 12
    MOV CL, 10              ; Left Col 10
    MOV DH, 14              ; Bottom Row 14
    MOV DL, 70              ; Right Col 70
    CALL SET_RECT_COLOR

    ; --- Position cursor for centered message ---
    MOV DH, 13              ; Center Row 13
    MOV DL, 18              ; Center Col 18
    CALL SET_CURSOR

    LEA DX, FLASH_MSG           ; Print the ALERT line
    MOV AH, 09h
    INT 21h

    PUSH CX                     ; Save flash counter before delay call
    MOV BX, 4                   ; Pause between each flash
    CALL SHORT_DELAY            ; Non-polled delay
    POP CX                      ; Restore flash counter

    LOOP FLASH_LOOP             ; DEC CX, JNZ FLASH_LOOP
```

- [ ] **Step 2: Verify logic and consistency**

Ensure `SET_RECT_COLOR` and `SET_CURSOR` are used correctly and that no other logic is disturbed.

- [ ] **Step 3: Commit final changes**
