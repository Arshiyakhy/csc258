################# CSC258 Assembly Final Project ###################
# This file contains our implementation of Magical Drop.
#
# Student 1: Arshiya Khayatzadeh, 1012253981
# Student 2: Mohammad Dadfar, 1012301108
#
# We assert that the code submitted here is entirely our own
# creation, and will indicate otherwise when it is not.
#
######################## Bitmap Display Configuration ########################
# - Unit width in pixels:       8
# - Unit height in pixels:      8
# - Display width in pixels:    256
# - Display height in pixels:   256
# - Base Address for Display:   0x10008000 ($gp)
##############################################################################
#
# The screen is 32 x 32 units. Each bubble is a 2 x 2 unit block.
#
#   x = 0        : left wall          x = 15      : right wall
#   x = 1..14    : 7 columns of the playing field (2 units each)
#   x = 17..31   : side panel (score, high score, next row, held bubbles)
#   y = 0        : top wall           y = 31      : bottom wall
#   y = 1..28    : 14 rows of the playing field (2 units each)
#   y = 29..30   : the character's row
#
# Controls:
#   1 / 2 / 3 : pick Easy / Medium / Hard on the start menu
#   a / d     : move left / right
#   s         : grab bubbles from the column above
#   w         : throw held bubbles into the column above
#   p         : pause / unpause
#   q         : quit
#   r         : retry (on the Game Over screen)
#
# Milestones reached: 1, 2, 3, 4, 5
#   Easy features: 1 (timed rows), 2 (rows speed up), 3 (difficulty select),
#                  4 (Game Over screen + retry), 5 (sound effects),
#                  6 (pause), 7 (high score), 9 (next row preview)
#   Hard features: 2 (flood fill), 3 (gravity), 4 (no match-3 in new rows),
#                  5 (chain reactions), 6 (flashing aim line),
#                  7 (score in pixels)
##############################################################################

    .data
##############################################################################
# Immutable Data
##############################################################################
# The address of the bitmap display. Don't forget to connect it!
ADDR_DSPL:
    .word 0x10008000
# The address of the keyboard. Don't forget to connect it!
ADDR_KBRD:
    .word 0xffff0000

# Bubble colours, indexed by colour number (0 = empty, 1..4 = bubble colours)
# 1 = red, 2 = green, 3 = blue, 4 = yellow
colours:
    .word 0x000000, 0xe8303a, 0x3cc84a, 0x3a78ff, 0xffd21f
# Darker shade of each colour, used for the bottom right unit of a bubble
shades:
    .word 0x000000, 0x9a1820, 0x1f7a2a, 0x1f45a8, 0xb08a00

# 3 x 5 pixel font, one word per character from '0' (48) to 'Z' (90).
# Bit 14 is the top left pixel, bit 0 is the bottom right pixel (row major).
font:
    .word 0x7b6f, 0x2c97, 0x73e7, 0x73cf, 0x5bc9, 0x79cf   # 0 1 2 3 4 5
    .word 0x79ef, 0x7249, 0x7bef, 0x7bcf, 0x0000, 0x0000   # 6 7 8 9 : ;
    .word 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x2bed   # < = > ? @ A
    .word 0x0000, 0x0000, 0x6b6e, 0x79a7, 0x0000, 0x796f   # B C D E F G
    .word 0x5bed, 0x7497, 0x0000, 0x0000, 0x0000, 0x5fed   # H I J K L M
    .word 0x7b6d, 0x2b6a, 0x6ba4, 0x7b79, 0x6bad, 0x388e   # N O P Q R S
    .word 0x7492, 0x5b6f, 0x5b6a, 0x0000, 0x5aad, 0x5a92   # T U V W X Y
    .word 0x0000                                           # Z

##############################################################################
# Mutable Data
##############################################################################
# The playing field: 14 rows x 7 columns, one word per cell, row major.
# Cell (row, col) is at grid + (row * 7 + col) * 4. Row 0 is the top row.
# 0 = empty, 1..4 = colour of the bubble in that cell.
grid:       .space 392
# One flag per cell, set to 1 when the cell is part of a match.
mark:       .space 392
# Stack of cell indices used by the flood fill.
ff_stack:   .space 392
# The next row of bubbles that will be pushed in (shown in the side panel).
next_row:   .space 28

player_col:   .word 3     # column the character stands under (0..6)
held_colour:  .word 0     # colour of the bubbles being held (0 = none)
held_count:   .word 0     # how many bubbles are being held
score:        .word 0     # current score (capped at 9999)
high_score:   .word 0     # best score since the program started
difficulty:   .word 1     # 1 = easy, 2 = medium, 3 = hard
row_interval: .word 600   # frames between automatic new rows
row_timer:    .word 0     # frames since the last automatic new row
key_count:    .word 0     # action keystrokes since the last new row
rows_pushed:  .word 0     # rows pushed in this game (used for speed up)
frame_count:  .word 0     # frames drawn in this game (used for flashing)

str_title:  .asciiz "DROP"
str_easy:   .asciiz "1 EASY"
str_med:    .asciiz "2 MED"
str_hard:   .asciiz "3 HARD"
str_pau:    .asciiz "PAU"
str_sed:    .asciiz "SED"
str_nxt:    .asciiz "NXT"
str_game:   .asciiz "GAME"
str_over:   .asciiz "OVER"
str_retry:  .asciiz "R RETRY"
str_quit:   .asciiz "Q QUIT"

##############################################################################
# Code
##############################################################################
	.text
	.globl main

# Register convention used in this file (standard MIPS):
#   functions may change $t, $a, $v registers; $s registers and $ra are
#   saved on the stack by any function that uses them.

    # Run the game.
main:
    jal  show_menu              # pick difficulty
    jal  init_game              # reset all game state and draw the walls

game_loop:
    # 1. Check for keyboard input and process player actions
    jal  get_key
    beqz $v0, gl_timer
    move $a0, $v0
    jal  handle_key             # move / grab / throw (+ matching) / pause / quit

gl_timer:
    # 2. Row advancement with a timer
    lw   $t0, frame_count
    addi $t0, $t0, 1
    sw   $t0, frame_count
    lw   $t0, row_timer
    addi $t0, $t0, 1
    sw   $t0, row_timer
    lw   $t1, row_interval
    blt  $t0, $t1, gl_keys
    sw   $zero, row_timer
    jal  push_row
    bnez $v0, game_over
    jal  after_push

gl_keys:
    # 3. Row advancement after 10 action keystrokes
    lw   $t0, key_count
    li   $t1, 10
    blt  $t0, $t1, gl_draw
    sw   $zero, key_count
    jal  push_row
    bnez $v0, game_over
    jal  after_push

gl_draw:
    # 4. Redraw the screen
    jal  draw_frame
    # 5. Sleep (about 60 frames per second)
    li   $a0, 16
    jal  sleep_ms
    # 6. Go back to step 1
    j    game_loop

game_over:
    jal  draw_frame
    jal  game_over_screen       # returns only if the player chose retry
    j    main


##############################################################################
# Input
##############################################################################

# get_key() -> $v0 = ASCII code of the key pressed, or 0 if no key was pressed
get_key:
    lw   $t0, ADDR_KBRD
    lw   $t1, 0($t0)            # 1 if a key was pressed
    li   $v0, 0
    bne  $t1, 1, gk_done
    lw   $v0, 4($t0)            # ASCII code of the key
gk_done:
    jr   $ra

# handle_key($a0 = key)
handle_key:
    addi $sp, $sp, -4
    sw   $ra, 0($sp)
    beq  $a0, 0x61, hk_left     # a
    beq  $a0, 0x64, hk_right    # d
    beq  $a0, 0x73, hk_grab     # s
    beq  $a0, 0x77, hk_throw    # w
    beq  $a0, 0x70, hk_pause    # p
    beq  $a0, 0x71, hk_quit     # q
    j    hk_done
hk_left:
    lw   $t0, player_col
    blez $t0, hk_count          # already at the left edge
    addi $t0, $t0, -1
    sw   $t0, player_col
    j    hk_count
hk_right:
    lw   $t0, player_col
    li   $t1, 6
    bge  $t0, $t1, hk_count     # already at the right edge
    addi $t0, $t0, 1
    sw   $t0, player_col
    j    hk_count
hk_grab:
    jal  grab
    j    hk_count
hk_throw:
    jal  throw_bubbles
    j    hk_count
hk_pause:
    jal  pause_game
    j    hk_done
hk_quit:
    jal  quit_game
hk_count:
    lw   $t0, key_count
    addi $t0, $t0, 1
    sw   $t0, key_count
hk_done:
    lw   $ra, 0($sp)
    addi $sp, $sp, 4
    jr   $ra


##############################################################################
# Game logic
##############################################################################

# init_game(): reset all game state, fill the starting rows, draw the walls
init_game:
    addi $sp, $sp, -8
    sw   $ra, 4($sp)
    sw   $s0, 0($sp)
    la   $t0, grid
    li   $t1, 98
ig_clear:
    sw   $zero, 0($t0)
    addiu $t0, $t0, 4
    addi $t1, $t1, -1
    bgtz $t1, ig_clear
    sw   $zero, held_colour
    sw   $zero, held_count
    sw   $zero, score
    sw   $zero, key_count
    sw   $zero, row_timer
    sw   $zero, rows_pushed
    sw   $zero, frame_count
    li   $t0, 3
    sw   $t0, player_col
    jal  gen_next_row
    li   $s0, 5                 # start with 5 rows of bubbles
ig_rows:
    jal  push_row
    addi $s0, $s0, -1
    bgtz $s0, ig_rows
    jal  draw_walls
    lw   $s0, 0($sp)
    lw   $ra, 4($sp)
    addi $sp, $sp, 8
    jr   $ra

# col_height($a0 = column) -> $v0 = number of bubbles in that column.
# Bubbles always hang from the top (row 0) with no gaps, so the bubbles
# are in rows 0..$v0-1 and row $v0 is the first empty cell.
col_height:
    la   $t0, grid
    sll  $t1, $a0, 2
    addu $t0, $t0, $t1          # address of grid[0][col]
    li   $v0, 0
ch_loop:
    li   $t3, 14
    bge  $v0, $t3, ch_done
    lw   $t2, 0($t0)
    beqz $t2, ch_done
    addi $v0, $v0, 1
    addiu $t0, $t0, 28          # next row (7 words further)
    j    ch_loop
ch_done:
    jr   $ra

# grab(): pick up the bottom-most bubble in the player's column and every
# bubble of the same colour stacked directly above it. If the player is
# already holding bubbles, only bubbles of the held colour can be grabbed.
grab:
    addi $sp, $sp, -20
    sw   $ra, 16($sp)
    sw   $s0, 12($sp)
    sw   $s1, 8($sp)
    sw   $s2, 4($sp)
    sw   $s3, 0($sp)
    lw   $s0, player_col
    move $a0, $s0
    jal  col_height
    beqz $v0, gr_done           # empty column, nothing to grab
    addi $s1, $v0, -1           # s1 = row of the bottom-most bubble
    li   $t0, 7
    mul  $t1, $s1, $t0
    add  $t1, $t1, $s0
    sll  $t1, $t1, 2
    la   $t2, grid
    addu $s2, $t2, $t1          # s2 = address of that cell
    lw   $s3, 0($s2)            # s3 = its colour
    lw   $t0, held_count
    beqz $t0, gr_take
    lw   $t1, held_colour
    bne  $t1, $s3, gr_done      # different colour from what we hold
gr_take:
    lw   $t3, held_count
gr_loop:
    bltz $s1, gr_store          # reached the top of the column
    lw   $t0, 0($s2)
    bne  $t0, $s3, gr_store     # chain of same colour ended
    sw   $zero, 0($s2)          # remove bubble from the field
    addi $t3, $t3, 1
    addi $s1, $s1, -1
    addiu $s2, $s2, -28         # one row up
    j    gr_loop
gr_store:
    sw   $s3, held_colour
    sw   $t3, held_count
    li   $a0, 72
    li   $a1, 120
    li   $a2, 13
    jal  play_sound
gr_done:
    lw   $s3, 0($sp)
    lw   $s2, 4($sp)
    lw   $s1, 8($sp)
    lw   $s0, 12($sp)
    lw   $ra, 16($sp)
    addi $sp, $sp, 20
    jr   $ra

# throw_bubbles(): stack all held bubbles under the existing bubbles of the
# player's column, then resolve any matches. The throw is ignored if the
# column does not have room for all of them.
throw_bubbles:
    addi $sp, $sp, -8
    sw   $ra, 4($sp)
    sw   $s0, 0($sp)
    lw   $s0, held_count
    beqz $s0, th_done           # nothing to throw
    lw   $a0, player_col
    jal  col_height             # v0 = first empty row
    add  $t0, $v0, $s0
    li   $t1, 14
    bgt  $t0, $t1, th_done      # not enough room
    li   $t0, 7
    mul  $t1, $v0, $t0
    lw   $t2, player_col
    add  $t1, $t1, $t2
    sll  $t1, $t1, 2
    la   $t3, grid
    addu $t3, $t3, $t1          # address of the landing cell
    lw   $t4, held_colour
th_loop:
    blez $s0, th_placed
    sw   $t4, 0($t3)
    addiu $t3, $t3, 28          # next row down
    addi $s0, $s0, -1
    j    th_loop
th_placed:
    sw   $zero, held_count
    sw   $zero, held_colour
    li   $a0, 60
    li   $a1, 120
    li   $a2, 13
    jal  play_sound
    jal  resolve_matches
th_done:
    lw   $s0, 0($sp)
    lw   $ra, 4($sp)
    addi $sp, $sp, 8
    jr   $ra

# resolve_matches(): repeat until nothing matches:
#   1. trigger:   mark every vertical run of 3+ same coloured bubbles
#   2. explosion: flood fill from the marked cells to all connected
#                 same coloured neighbours (up, down, left, right)
#   3. remove the marked bubbles and add to the score
#   4. gravity:   bubbles float up to fill the gaps
# Each pass is one more step of the chain reaction.
resolve_matches:
    addi $sp, $sp, -8
    sw   $ra, 4($sp)
    sw   $s0, 0($sp)
    li   $s0, 0                 # s0 = chain depth
rm_loop:
    jal  clear_marks
    jal  find_triggers
    beqz $v0, rm_done           # no match-3 anywhere, done
    addi $s0, $s0, 1
    jal  flood_fill
    jal  remove_marked          # v0 = number of bubbles removed
    # score += removed * chain depth * difficulty
    lw   $t0, difficulty
    mul  $t1, $v0, $s0
    mul  $t1, $t1, $t0
    lw   $t2, score
    add  $t2, $t2, $t1
    li   $t3, 9999
    ble  $t2, $t3, rm_score
    move $t2, $t3
rm_score:
    sw   $t2, score
    # higher note for every step of the chain
    sll  $t0, $s0, 2
    addi $a0, $t0, 72
    li   $a1, 200
    li   $a2, 9
    jal  play_sound
    jal  draw_frame             # show the cleared cells
    li   $a0, 150
    jal  sleep_ms
    jal  gravity
    jal  draw_frame             # show the bubbles after they float up
    li   $a0, 150
    jal  sleep_ms
    j    rm_loop
rm_done:
    lw   $s0, 0($sp)
    lw   $ra, 4($sp)
    addi $sp, $sp, 8
    jr   $ra

# clear_marks(): set every mark flag to 0
clear_marks:
    la   $t0, mark
    li   $t1, 98
cm_loop:
    sw   $zero, 0($t0)
    addiu $t0, $t0, 4
    addi $t1, $t1, -1
    bgtz $t1, cm_loop
    jr   $ra

# find_triggers() -> $v0 = 1 if at least one vertical match-3 was found.
# Marks every cell that is part of a vertical run of 3 or more.
find_triggers:
    li   $v0, 0
    li   $t0, 0                 # t0 = column
ft_col:
    li   $t9, 7
    bge  $t0, $t9, ft_done
    li   $t1, 0                 # t1 = row
ft_row:
    li   $t9, 12
    bge  $t1, $t9, ft_next_col  # rows 0..11 can start a run of 3
    li   $t2, 7
    mul  $t2, $t1, $t2
    add  $t2, $t2, $t0
    sll  $t2, $t2, 2            # t2 = byte offset of (row, col)
    la   $t3, grid
    addu $t3, $t3, $t2
    lw   $t4, 0($t3)            # colour of (row, col)
    beqz $t4, ft_next_row
    lw   $t5, 28($t3)           # colour of (row + 1, col)
    bne  $t5, $t4, ft_next_row
    lw   $t5, 56($t3)           # colour of (row + 2, col)
    bne  $t5, $t4, ft_next_row
    la   $t6, mark
    addu $t6, $t6, $t2
    li   $t7, 1
    sw   $t7, 0($t6)
    sw   $t7, 28($t6)
    sw   $t7, 56($t6)
    li   $v0, 1
ft_next_row:
    addi $t1, $t1, 1
    j    ft_row
ft_next_col:
    addi $t0, $t0, 1
    j    ft_col
ft_done:
    jr   $ra

# flood_fill(): starting from every marked cell, mark all connected cells of
# the same colour (up, down, left, right). Uses ff_stack instead of recursion.
#   t0 = mark base, t1 = grid base, t2 = stack base, t3 = stack size
#   t4 = current cell index, t9 = its colour, a0 = row, a1 = col
#   a2 = neighbour index
flood_fill:
    la   $t0, mark
    la   $t1, grid
    la   $t2, ff_stack
    li   $t3, 0
    li   $t4, 0
ff_seed:                        # push every marked cell onto the stack
    li   $t5, 98
    bge  $t4, $t5, ff_work
    sll  $t5, $t4, 2
    addu $t6, $t0, $t5
    lw   $t7, 0($t6)
    beqz $t7, ff_seed_next
    sll  $t8, $t3, 2
    addu $t8, $t2, $t8
    sw   $t4, 0($t8)
    addi $t3, $t3, 1
ff_seed_next:
    addi $t4, $t4, 1
    j    ff_seed
ff_work:
    blez $t3, ff_done           # stack empty
    addi $t3, $t3, -1           # pop
    sll  $t8, $t3, 2
    addu $t8, $t2, $t8
    lw   $t4, 0($t8)            # t4 = cell index
    sll  $t5, $t4, 2
    addu $t6, $t1, $t5
    lw   $t9, 0($t6)            # t9 = colour of this cell
    li   $t5, 7
    div  $t4, $t5
    mflo $a0                    # a0 = row
    mfhi $a1                    # a1 = col

    # neighbour above
    blez $a0, ff_down
    addi $a2, $t4, -7
    sll  $t5, $a2, 2
    addu $t6, $t0, $t5
    lw   $t7, 0($t6)
    bnez $t7, ff_down           # already marked
    addu $t7, $t1, $t5
    lw   $t7, 0($t7)
    bne  $t7, $t9, ff_down      # different colour
    li   $t7, 1
    sw   $t7, 0($t6)
    sll  $t8, $t3, 2
    addu $t8, $t2, $t8
    sw   $a2, 0($t8)
    addi $t3, $t3, 1
ff_down:
    li   $t5, 13
    bge  $a0, $t5, ff_left
    addi $a2, $t4, 7
    sll  $t5, $a2, 2
    addu $t6, $t0, $t5
    lw   $t7, 0($t6)
    bnez $t7, ff_left
    addu $t7, $t1, $t5
    lw   $t7, 0($t7)
    bne  $t7, $t9, ff_left
    li   $t7, 1
    sw   $t7, 0($t6)
    sll  $t8, $t3, 2
    addu $t8, $t2, $t8
    sw   $a2, 0($t8)
    addi $t3, $t3, 1
ff_left:
    blez $a1, ff_right
    addi $a2, $t4, -1
    sll  $t5, $a2, 2
    addu $t6, $t0, $t5
    lw   $t7, 0($t6)
    bnez $t7, ff_right
    addu $t7, $t1, $t5
    lw   $t7, 0($t7)
    bne  $t7, $t9, ff_right
    li   $t7, 1
    sw   $t7, 0($t6)
    sll  $t8, $t3, 2
    addu $t8, $t2, $t8
    sw   $a2, 0($t8)
    addi $t3, $t3, 1
ff_right:
    li   $t5, 6
    bge  $a1, $t5, ff_work
    addi $a2, $t4, 1
    sll  $t5, $a2, 2
    addu $t6, $t0, $t5
    lw   $t7, 0($t6)
    bnez $t7, ff_work
    addu $t7, $t1, $t5
    lw   $t7, 0($t7)
    bne  $t7, $t9, ff_work
    li   $t7, 1
    sw   $t7, 0($t6)
    sll  $t8, $t3, 2
    addu $t8, $t2, $t8
    sw   $a2, 0($t8)
    addi $t3, $t3, 1
    j    ff_work
ff_done:
    jr   $ra

# remove_marked() -> $v0 = number of bubbles removed
remove_marked:
    la   $t0, mark
    la   $t1, grid
    li   $t2, 98
    li   $v0, 0
rmk_loop:
    lw   $t3, 0($t0)
    beqz $t3, rmk_next
    sw   $zero, 0($t1)
    addi $v0, $v0, 1
rmk_next:
    addiu $t0, $t0, 4
    addiu $t1, $t1, 4
    addi $t2, $t2, -1
    bgtz $t2, rmk_loop
    jr   $ra

# gravity(): in every column, move the bubbles up so they hang from row 0
# with no gaps (unsupported bubbles float upwards).
gravity:
    li   $t0, 0                 # column
gv_col:
    li   $t9, 7
    bge  $t0, $t9, gv_done
    la   $t1, grid
    sll  $t2, $t0, 2
    addu $t1, $t1, $t2          # t1 = read pointer (row 0)
    move $t3, $t1               # t3 = write pointer (next free spot)
    li   $t4, 0                 # row
gv_row:
    li   $t9, 14
    bge  $t4, $t9, gv_next
    lw   $t5, 0($t1)
    beqz $t5, gv_skip
    beq  $t1, $t3, gv_same
    sw   $t5, 0($t3)            # move bubble up
    sw   $zero, 0($t1)
gv_same:
    addiu $t3, $t3, 28
gv_skip:
    addiu $t1, $t1, 28
    addi $t4, $t4, 1
    j    gv_row
gv_next:
    addi $t0, $t0, 1
    j    gv_col
gv_done:
    jr   $ra

# push_row() -> $v0 = 1 if the game is over, 0 otherwise.
# Pushes every bubble down one row and puts next_row in row 0. If a bubble
# is already in the bottom row (row 13), it would be pushed into the
# character's row, so the game is over.
push_row:
    addi $sp, $sp, -16
    sw   $ra, 12($sp)
    sw   $s0, 8($sp)
    sw   $s1, 4($sp)
    sw   $s2, 0($sp)
    la   $t0, grid
    addiu $t0, $t0, 364         # grid[13][0] (index 91)
    li   $t1, 0
pr_check:
    li   $t3, 7
    bge  $t1, $t3, pr_shift
    lw   $t2, 0($t0)
    bnez $t2, pr_over
    addiu $t0, $t0, 4
    addi $t1, $t1, 1
    j    pr_check
pr_shift:                       # grid[i] = grid[i - 7] for i = 97 down to 7
    la   $t0, grid
    addiu $t0, $t0, 388         # index 97
    li   $t1, 91
pr_shift_loop:
    blez $t1, pr_new
    lw   $t2, -28($t0)
    sw   $t2, 0($t0)
    addiu $t0, $t0, -4
    addi $t1, $t1, -1
    j    pr_shift_loop
pr_new:
    li   $s0, 0                 # column
pr_new_loop:
    li   $t0, 7
    bge  $s0, $t0, pr_new_done
    la   $t0, next_row
    sll  $t1, $s0, 2
    addu $t0, $t0, $t1
    lw   $s1, 0($t0)            # s1 = colour from the preview
    la   $t0, grid
    addu $s2, $t0, $t1          # s2 = address of grid[0][col]
pr_try:
    # Do not let the new bubble create a match-3 with the two below it.
    lw   $t2, 28($s2)
    beqz $t2, pr_ok
    lw   $t3, 56($s2)
    bne  $t2, $t3, pr_ok
    bne  $s1, $t2, pr_ok
    jal  rand_colour            # would make a match-3: pick another colour
    move $s1, $v0
    j    pr_try
pr_ok:
    sw   $s1, 0($s2)
    addi $s0, $s0, 1
    j    pr_new_loop
pr_new_done:
    jal  gen_next_row
    li   $v0, 0
    j    pr_ret
pr_over:
    li   $v0, 1
pr_ret:
    lw   $s2, 0($sp)
    lw   $s1, 4($sp)
    lw   $s0, 8($sp)
    lw   $ra, 12($sp)
    addi $sp, $sp, 16
    jr   $ra

# after_push(): sound for a new row, and every 5 rows the rows come
# 1/8 faster (never faster than once every 120 frames).
after_push:
    addi $sp, $sp, -4
    sw   $ra, 0($sp)
    lw   $t0, rows_pushed
    addi $t0, $t0, 1
    sw   $t0, rows_pushed
    li   $t1, 5
    div  $t0, $t1
    mfhi $t2
    bnez $t2, ap_sound
    lw   $t0, row_interval
    srl  $t1, $t0, 3
    sub  $t0, $t0, $t1
    li   $t1, 120
    bge  $t0, $t1, ap_set
    move $t0, $t1
ap_set:
    sw   $t0, row_interval
ap_sound:
    li   $a0, 45
    li   $a1, 80
    li   $a2, 115
    jal  play_sound
    lw   $ra, 0($sp)
    addi $sp, $sp, 4
    jr   $ra

# rand_colour() -> $v0 = random colour 1..4
rand_colour:
    li   $v0, 42
    li   $a0, 0
    li   $a1, 4
    syscall
    addi $v0, $a0, 1
    jr   $ra

# gen_next_row(): fill next_row with 7 random colours
gen_next_row:
    addi $sp, $sp, -8
    sw   $ra, 4($sp)
    sw   $s0, 0($sp)
    li   $s0, 0
gn_loop:
    jal  rand_colour
    la   $t0, next_row
    sll  $t1, $s0, 2
    addu $t0, $t0, $t1
    sw   $v0, 0($t0)
    addi $s0, $s0, 1
    li   $t2, 7
    blt  $s0, $t2, gn_loop
    lw   $s0, 0($sp)
    lw   $ra, 4($sp)
    addi $sp, $sp, 8
    jr   $ra


##############################################################################
# Screens: menu, pause, game over
##############################################################################

# show_menu(): draw the difficulty menu and wait for 1, 2 or 3
show_menu:
    addi $sp, $sp, -4
    sw   $ra, 0($sp)
    li   $a0, 0
    li   $a1, 0
    li   $a2, 32
    li   $a3, 32
    li   $v1, 0x000000
    jal  draw_rect
    la   $a0, str_title
    li   $a1, 9
    li   $a2, 2
    li   $a3, 0xffd21f
    jal  draw_string
    la   $a0, str_easy
    li   $a1, 4
    li   $a2, 10
    li   $a3, 0x3cc84a
    jal  draw_string
    la   $a0, str_med
    li   $a1, 4
    li   $a2, 17
    li   $a3, 0xffd21f
    jal  draw_string
    la   $a0, str_hard
    li   $a1, 4
    li   $a2, 24
    li   $a3, 0xe8303a
    jal  draw_string
sm_wait:
    jal  get_key
    beq  $v0, 0x31, sm_easy
    beq  $v0, 0x32, sm_med
    beq  $v0, 0x33, sm_hard
    bne  $v0, 0x71, sm_sleep
    jal  quit_game
sm_sleep:
    li   $a0, 16
    jal  sleep_ms
    j    sm_wait
sm_easy:
    li   $t0, 1
    li   $t1, 600               # new row every ~10 s
    j    sm_set
sm_med:
    li   $t0, 2
    li   $t1, 420               # new row every ~7 s
    j    sm_set
sm_hard:
    li   $t0, 3
    li   $t1, 270               # new row every ~4.5 s
sm_set:
    sw   $t0, difficulty
    sw   $t1, row_interval
    lw   $ra, 0($sp)
    addi $sp, $sp, 4
    jr   $ra

# pause_game(): show "PAUSED" over the field until p is pressed again
pause_game:
    addi $sp, $sp, -4
    sw   $ra, 0($sp)
    li   $a0, 2
    li   $a1, 10
    li   $a2, 13
    li   $a3, 13
    li   $v1, 0x000000
    jal  draw_rect
    la   $a0, str_pau
    li   $a1, 3
    li   $a2, 11
    li   $a3, 0xffffff
    jal  draw_string
    la   $a0, str_sed
    li   $a1, 3
    li   $a2, 17
    li   $a3, 0xffffff
    jal  draw_string
pg_wait:
    jal  get_key
    beq  $v0, 0x70, pg_done     # p again: resume
    bne  $v0, 0x71, pg_sleep
    jal  quit_game
pg_sleep:
    li   $a0, 50
    jal  sleep_ms
    j    pg_wait
pg_done:
    lw   $ra, 0($sp)
    addi $sp, $sp, 4
    jr   $ra

# game_over_screen(): update the high score, show the Game Over screen and
# wait for r (retry, returns) or q (quit)
game_over_screen:
    addi $sp, $sp, -4
    sw   $ra, 0($sp)
    li   $a0, 40
    li   $a1, 900
    li   $a2, 57
    jal  play_sound
    lw   $t0, score
    lw   $t1, high_score
    ble  $t0, $t1, go_draw
    sw   $t0, high_score
go_draw:
    li   $a0, 0
    li   $a1, 0
    li   $a2, 32
    li   $a3, 32
    li   $v1, 0x3a0010
    jal  draw_rect
    la   $a0, str_game
    li   $a1, 9
    li   $a2, 2
    li   $a3, 0xffffff
    jal  draw_string
    la   $a0, str_over
    li   $a1, 9
    li   $a2, 8
    li   $a3, 0xffffff
    jal  draw_string
    lw   $a0, score
    li   $a1, 9
    li   $a2, 14
    li   $a3, 0xffd21f
    jal  draw_number
    la   $a0, str_retry
    li   $a1, 3
    li   $a2, 20
    li   $a3, 0x3cc84a
    jal  draw_string
    la   $a0, str_quit
    li   $a1, 5
    li   $a2, 26
    li   $a3, 0x9090a0
    jal  draw_string
go_wait:
    jal  get_key
    beq  $v0, 0x72, go_done     # r: retry
    bne  $v0, 0x71, go_sleep
    jal  quit_game
go_sleep:
    li   $a0, 50
    jal  sleep_ms
    j    go_wait
go_done:
    lw   $ra, 0($sp)
    addi $sp, $sp, 4
    jr   $ra

# quit_game(): end the program
quit_game:
    li   $v0, 10
    syscall


##############################################################################
# Drawing
##############################################################################

# draw_frame(): redraw the field, the character row and the side panel
draw_frame:
    addi $sp, $sp, -4
    sw   $ra, 0($sp)
    jal  draw_field
    jal  draw_player_row
    jal  draw_panel
    lw   $ra, 0($sp)
    addi $sp, $sp, 4
    jr   $ra

# draw_walls(): clear the screen and draw the grey walls around the field
draw_walls:
    addi $sp, $sp, -4
    sw   $ra, 0($sp)
    li   $a0, 0
    li   $a1, 0
    li   $a2, 32
    li   $a3, 32
    li   $v1, 0x000000
    jal  draw_rect
    li   $v1, 0x606070
    li   $a0, 0                 # top wall
    li   $a1, 0
    li   $a2, 16
    li   $a3, 1
    jal  draw_rect
    li   $a0, 0                 # bottom wall
    li   $a1, 31
    li   $a2, 16
    li   $a3, 1
    jal  draw_rect
    li   $a0, 0                 # left wall
    li   $a1, 0
    li   $a2, 1
    li   $a3, 32
    jal  draw_rect
    li   $a0, 15                # right wall
    li   $a1, 0
    li   $a2, 1
    li   $a3, 32
    jal  draw_rect
    lw   $ra, 0($sp)
    addi $sp, $sp, 4
    jr   $ra

# draw_field(): draw every cell of the grid, then the flashing aim line
draw_field:
    addi $sp, $sp, -16
    sw   $ra, 12($sp)
    sw   $s0, 8($sp)
    sw   $s1, 4($sp)
    sw   $s2, 0($sp)
    la   $s2, grid
    li   $s0, 0                 # row
df_row:
    li   $s1, 0                 # col
df_col:
    lw   $a2, 0($s2)
    sll  $a0, $s1, 1
    addi $a0, $a0, 1            # x = 1 + 2 * col
    sll  $a1, $s0, 1
    addi $a1, $a1, 1            # y = 1 + 2 * row
    bnez $a2, df_bubble
    # empty cell: checkerboard so the 7 x 14 grid is visible
    add  $t0, $s0, $s1
    andi $t0, $t0, 1
    li   $v1, 0x14141e
    beqz $t0, df_empty
    li   $v1, 0x1e1e2e
df_empty:
    li   $a2, 2
    li   $a3, 2
    jal  draw_rect
    j    df_next
df_bubble:
    jal  draw_bubble
df_next:
    addiu $s2, $s2, 4
    addi $s1, $s1, 1
    li   $t0, 7
    blt  $s1, $t0, df_col
    addi $s0, $s0, 1
    li   $t0, 14
    blt  $s0, $t0, df_row

    # aim line: dashed line in the empty cells of the player's column,
    # flashing on and off every 16 frames
    lw   $t0, frame_count
    andi $t0, $t0, 16
    beqz $t0, df_done
    lw   $a0, player_col
    jal  col_height
    move $s0, $v0               # first empty row
    lw   $s1, player_col
    sll  $s1, $s1, 1
    addi $s1, $s1, 1            # x of the column
df_aim:
    li   $t0, 14
    bge  $s0, $t0, df_done
    move $a0, $s1
    sll  $a1, $s0, 1
    addi $a1, $a1, 1
    li   $a2, 0x9090a0
    jal  set_unit
    addi $a0, $s1, 1
    sll  $a1, $s0, 1
    addi $a1, $a1, 1
    li   $a2, 0x9090a0
    jal  set_unit
    addi $s0, $s0, 1
    j    df_aim
df_done:
    lw   $s2, 0($sp)
    lw   $s1, 4($sp)
    lw   $s0, 8($sp)
    lw   $ra, 12($sp)
    addi $sp, $sp, 16
    jr   $ra

# draw_player_row(): draw the character under its column. The top half
# shows the colour of the held bubbles (white when holding nothing).
draw_player_row:
    addi $sp, $sp, -12
    sw   $ra, 8($sp)
    sw   $s0, 4($sp)
    sw   $s1, 0($sp)
    li   $a0, 1
    li   $a1, 29
    li   $a2, 14
    li   $a3, 2
    li   $v1, 0x000000
    jal  draw_rect
    lw   $s0, player_col
    sll  $s0, $s0, 1
    addi $s0, $s0, 1            # x of the character
    li   $s1, 0xffffff
    lw   $t0, held_count
    beqz $t0, dp_head
    lw   $t1, held_colour
    sll  $t1, $t1, 2
    la   $t2, colours
    addu $t2, $t2, $t1
    lw   $s1, 0($t2)
dp_head:
    move $a0, $s0
    li   $a1, 29
    move $a2, $s1
    jal  set_unit
    addi $a0, $s0, 1
    li   $a1, 29
    move $a2, $s1
    jal  set_unit
    move $a0, $s0
    li   $a1, 30
    li   $a2, 0xc070ff
    jal  set_unit
    addi $a0, $s0, 1
    li   $a1, 30
    li   $a2, 0xc070ff
    jal  set_unit
    lw   $s1, 0($sp)
    lw   $s0, 4($sp)
    lw   $ra, 8($sp)
    addi $sp, $sp, 12
    jr   $ra

# draw_panel(): score (white), high score (gold), next row preview,
# and the held bubble with how many are held
draw_panel:
    addi $sp, $sp, -8
    sw   $ra, 4($sp)
    sw   $s0, 0($sp)
    li   $a0, 17                # score
    li   $a1, 1
    li   $a2, 15
    li   $a3, 5
    li   $v1, 0x000000
    jal  draw_rect
    lw   $a0, score
    li   $a1, 17
    li   $a2, 1
    li   $a3, 0xffffff
    jal  draw_number
    li   $a0, 17                # high score
    li   $a1, 7
    li   $a2, 15
    li   $a3, 5
    li   $v1, 0x000000
    jal  draw_rect
    lw   $a0, high_score
    li   $a1, 17
    li   $a2, 7
    li   $a3, 0xffd21f
    jal  draw_number
    la   $a0, str_nxt           # next row label
    li   $a1, 17
    li   $a2, 13
    li   $a3, 0x9090a0
    jal  draw_string
    li   $s0, 0                 # next row preview
dpn_loop:
    sll  $a0, $s0, 1
    addi $a0, $a0, 17
    li   $a1, 19
    la   $t0, next_row
    sll  $t1, $s0, 2
    addu $t0, $t0, $t1
    lw   $a2, 0($t0)
    jal  draw_bubble
    addi $s0, $s0, 1
    li   $t0, 7
    blt  $s0, $t0, dpn_loop
    li   $a0, 17                # held bubbles
    li   $a1, 23
    li   $a2, 15
    li   $a3, 5
    li   $v1, 0x000000
    jal  draw_rect
    lw   $t0, held_count
    beqz $t0, dpn_done
    li   $a0, 17
    li   $a1, 24
    lw   $a2, held_colour
    jal  draw_bubble
    lw   $t0, held_count
    li   $t1, 9
    ble  $t0, $t1, dpn_digit
    move $t0, $t1
dpn_digit:
    sll  $t0, $t0, 2
    la   $t1, font
    addu $t1, $t1, $t0
    lw   $a2, 0($t1)
    li   $a0, 21
    li   $a1, 23
    li   $a3, 0xffffff
    jal  draw_glyph
dpn_done:
    lw   $s0, 0($sp)
    lw   $ra, 4($sp)
    addi $sp, $sp, 8
    jr   $ra


##############################################################################
# Drawing primitives
##############################################################################

# set_unit($a0 = x, $a1 = y, $a2 = colour): colour one unit
set_unit:
    lw   $t0, ADDR_DSPL
    sll  $t1, $a1, 5            # y * 32
    addu $t1, $t1, $a0          # + x
    sll  $t1, $t1, 2            # * 4 bytes
    addu $t0, $t0, $t1
    sw   $a2, 0($t0)
    jr   $ra

# draw_rect($a0 = x, $a1 = y, $a2 = width, $a3 = height, $v1 = colour)
draw_rect:
    lw   $t0, ADDR_DSPL
    sll  $t1, $a1, 5
    addu $t1, $t1, $a0
    sll  $t1, $t1, 2
    addu $t0, $t0, $t1          # address of the top left unit
    move $t2, $a3               # rows left
dr_row:
    blez $t2, dr_done
    move $t3, $t0
    move $t4, $a2               # units left in this row
dr_col:
    blez $t4, dr_next
    sw   $v1, 0($t3)
    addiu $t3, $t3, 4
    addi $t4, $t4, -1
    j    dr_col
dr_next:
    addiu $t0, $t0, 128         # next row of the display (32 units * 4)
    addi $t2, $t2, -1
    j    dr_row
dr_done:
    jr   $ra

# draw_bubble($a0 = x, $a1 = y, $a2 = colour number 0..4): draw a 2 x 2
# bubble with a darker bottom right unit
draw_bubble:
    lw   $t0, ADDR_DSPL
    sll  $t1, $a1, 5
    addu $t1, $t1, $a0
    sll  $t1, $t1, 2
    addu $t0, $t0, $t1
    sll  $t2, $a2, 2
    la   $t3, colours
    addu $t3, $t3, $t2
    lw   $t4, 0($t3)            # main colour
    la   $t3, shades
    addu $t3, $t3, $t2
    lw   $t5, 0($t3)            # shade
    sw   $t4, 0($t0)
    sw   $t4, 4($t0)
    sw   $t4, 128($t0)
    sw   $t5, 132($t0)
    jr   $ra

# draw_glyph($a0 = x, $a1 = y, $a2 = 15 bit font mask, $a3 = colour)
draw_glyph:
    lw   $t0, ADDR_DSPL
    sll  $t1, $a1, 5
    addu $t1, $t1, $a0
    sll  $t1, $t1, 2
    addu $t0, $t0, $t1          # address of the top left pixel
    li   $t1, 14                # bit to test
    li   $t2, 0                 # row
dg_row:
    li   $t3, 0                 # col
    move $t4, $t0
dg_col:
    srlv $t5, $a2, $t1
    andi $t5, $t5, 1
    beqz $t5, dg_skip
    sw   $a3, 0($t4)
dg_skip:
    addiu $t4, $t4, 4
    addi $t1, $t1, -1
    addi $t3, $t3, 1
    li   $t6, 3
    blt  $t3, $t6, dg_col
    addiu $t0, $t0, 128
    addi $t2, $t2, 1
    li   $t6, 5
    blt  $t2, $t6, dg_row
    jr   $ra

# draw_string($a0 = address of string, $a1 = x, $a2 = y, $a3 = colour)
# Supports 0-9, A-Z and spaces. Each character is 4 units wide.
draw_string:
    addi $sp, $sp, -20
    sw   $ra, 16($sp)
    sw   $s0, 12($sp)
    sw   $s1, 8($sp)
    sw   $s2, 4($sp)
    sw   $s3, 0($sp)
    move $s0, $a0
    move $s1, $a1
    move $s2, $a2
    move $s3, $a3
ds_loop:
    lb   $t0, 0($s0)
    beqz $t0, ds_done
    blt  $t0, 48, ds_next       # space or other: leave blank
    bgt  $t0, 90, ds_next
    addi $t0, $t0, -48
    sll  $t0, $t0, 2
    la   $t1, font
    addu $t1, $t1, $t0
    lw   $a2, 0($t1)
    move $a0, $s1
    move $a1, $s2
    move $a3, $s3
    jal  draw_glyph
ds_next:
    addi $s0, $s0, 1
    addi $s1, $s1, 4
    j    ds_loop
ds_done:
    lw   $s3, 0($sp)
    lw   $s2, 4($sp)
    lw   $s1, 8($sp)
    lw   $s0, 12($sp)
    lw   $ra, 16($sp)
    addi $sp, $sp, 20
    jr   $ra

# draw_number($a0 = value 0..9999, $a1 = x, $a2 = y, $a3 = colour)
# Draws 4 digits with leading zeros (15 units wide).
draw_number:
    addi $sp, $sp, -24
    sw   $ra, 20($sp)
    sw   $s0, 16($sp)
    sw   $s1, 12($sp)
    sw   $s2, 8($sp)
    sw   $s3, 4($sp)
    sw   $s4, 0($sp)
    move $s0, $a0
    addi $s1, $a1, 12           # start with the rightmost digit
    move $s2, $a2
    move $s3, $a3
    li   $s4, 4
dn_loop:
    li   $t0, 10
    div  $s0, $t0
    mfhi $t1                    # digit
    mflo $s0                    # rest of the number
    sll  $t1, $t1, 2
    la   $t2, font
    addu $t2, $t2, $t1
    lw   $a2, 0($t2)
    move $a0, $s1
    move $a1, $s2
    move $a3, $s3
    jal  draw_glyph
    addi $s1, $s1, -4
    addi $s4, $s4, -1
    bgtz $s4, dn_loop
    lw   $s4, 0($sp)
    lw   $s3, 4($sp)
    lw   $s2, 8($sp)
    lw   $s1, 12($sp)
    lw   $s0, 16($sp)
    lw   $ra, 20($sp)
    addi $sp, $sp, 24
    jr   $ra


##############################################################################
# System call helpers
##############################################################################

# sleep_ms($a0 = milliseconds)
sleep_ms:
    li   $v0, 32
    syscall
    jr   $ra

# play_sound($a0 = pitch, $a1 = duration in ms, $a2 = instrument)
play_sound:
    li   $a3, 100               # volume
    li   $v0, 31                # MIDI out (does not wait for the note)
    syscall
    jr   $ra
