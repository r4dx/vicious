*=$0801
.byte $0C,$08,$0A,$00,$9E,$20,$34,$30,$39,$36,$00,$00,$00
*=$1000

  .t_synth_init 0
  .t_sec_synth_init 1
  .t_bass_init 2

  .sid.setup_filter 300, 14, false, true, true, false, true
  .sid.set_volume 15

; TODO:
; 1. Notes duration into the engine (and syntax)
; 2. Ability to control the octave for the sheet (so relatives values for octaves in syntax)
; 3. Ability to detune the voice by specified amount (better if as effect)
; 4. Effects engine
  .sid.v1 "x x x x  x x x x  D# F F# x  x F C# x  2F# x x x  D# F F# x  x F C# x  A# x x G#  x x x D#  F F# x x  F C# 2G# x  x x F# x  x x D# F#  x x F x  x D# x x  x x", 3
  .sid.v2 "x x x x  x x x x  D# F F# x  x F C# x  1F# x x x  D# F F# x  x F C# x  A# x x G#  x x x D#  F F# x x  F C# 1G# x  x x F# x  x x D# F#  x x F x  x D# x x  x x", 2
  .sid.v3 "D# F x D#  x D# D# x  x x x x  x x x x  x x x x", 2

m_loop:
  lda #0
  sta 162
  ldy #70/4
m_wait:
  cpy 162
  bne m_wait
  lda str
  jsr sid.play_next_uses_xy
  jmp m_loop

m_done:
  jsr write_a_str_uses_x
  rts

write_a_str_uses_x:
  ldx #0
w_loop:
  lda str, x
  beq w_done
  sta $0400, x
  inx
  jmp w_loop
w_done:
  rts

sid .binclude "sid.asm"

t_synth_init .macro voice
  .sid.setup \voice, Pulse, 0, 0, 15, 10, $800 ; square
.endm

t_sec_synth_init .macro voice
  .sid.setup \voice, Sawtooth, 7, 5, 15, 10
.endm

t_bass_init .macro voice
  .sid.setup \voice, Noise, 0, 0, 15, 0
.endm

.enc "screen"
str .text "this is a string", 0
