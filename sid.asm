Voice1 = $d400
Voice2 = $d407
Voice3 = $d40e

VOICE_REGS = [Voice1, Voice2, Voice3]

FilterCutOffFreqLo = $d415
FilterCutOffFreqHi = $d416
FilterResonanceAndRouting = $d417
FilterModeVolumeControl = $d418

FreqLo = 0
FreqHi = 1
PulseWaveDutyCycleLo = 2
PulseWaveDutyCycleHi = 3
ControlReg = 4
AttackDecay = 5
SustainRelease = 6

Noise = %10000000
Pulse = %01000000
Sawtooth = %00100000
Triangle = %00010000
Gate = %00000001
Sync = %00000010

st .macro addr, val
  lda \val
  sta \addr
.endm

.comment
Notes:
  N=[0-7]{C,D,E,F,G,A,B,x}[#,b]
  Octaves - default 4
  x note  - means skip

Slide:
  N-N

Bend:
  N-1
  N-.5

Rythm control:
  measure - TBD, default 1/4
  BPM - TBD, default 90 
.endc

NOTES = {"C":0,"C#":1,"Db":1,"D":2, "D#":3, "Eb":3,"E":4,"F":5,"F#":6,"Gb":6,"G":7,"G#":8,"Ab":8,"A":9,"A#":10,"Bb":10,"B":11,"x":12}
SKIP_NOTE = $ff
encode .macro sheet, default_octave
  DELIMITERS = [" "]
  last := ""
  .for i := 0, i < len(\sheet), i += 1
    sym := \sheet[i]
    .if !(sym in DELIMITERS)
      last ..= sym
      .if i != len(\sheet) - 1
        .continue
      .endif
    .endif
    .if len(last) == 0
      .continue
    .endif
    octave := \default_octave
    note_idx := 0
    .if len(last) <= 3
      .if last in NOTES
        note_idx := NOTES[last]
      .else
        octave := last[0] - '0'
        note_idx := NOTES[last[1:]]
      .endif
    .else
      .error "Note should be defined by <= 3 symbols: " .. repr(last) 
    .endif
    .if octave > 7 || octave < 0
      .error "Incorrect octave in note: " .. repr(last)       
    .endif
;    .warn repr(last) .. " = octave: " .. repr(octave) .. " note: " .. repr(note_idx)
    .pack octave, note_idx
    last := ""
  .endfor
.endm

pack .macro octave, note
  .if \note == NOTES["x"]
    .byte SKIP_NOTE
  .else
    .byte \octave * 12 + \note
  .endif
.endm

setup .macro voice, waveform, attack, decay, sustain, release, pulse_duty_cycle=0
  pha
  voice_reg = VOICE_REGS[\voice]
  .st voice_reg + PulseWaveDutyCycleLo, #(\pulse_duty_cycle & $00ff)
  .st voice_reg + PulseWaveDutyCycleHi, #(\pulse_duty_cycle>>8 & $000f)
  .set_ctr_reg \voice, \waveform
  .st voice_reg + AttackDecay, #(\attack << 4 | \decay)
  .st voice_reg + SustainRelease, #(\sustain << 4 | \release)
  pla
.endm

setup_filter .macro cutOffFreq, resonance, v1=false, v2=false, v3=false, hi_pass=false, lo_pass=false, band_pass=false, mute_v3=false
  .set_cutoff \cutOffFreq
  voice_mask := 0
  .if \v1
    voice_mask |= %00000001
  .endif
  .if \v2
    voice_mask |= %00000010
  .endif
  .if \v3
    voice_mask |= %00000100
  .endif
  .st FilterResonanceAndRouting, #(\resonance << 4 | voice_mask)
  mode := 0
  .if \mute_v3
    mode |= %10000000
  .endif
  .if \hi_pass
    mode |= %01000000
  .endif
  .if \band_pass
    mode |= %00100000
  .endif
  .if \lo_pass
    mode |= %00010000
  .endif
  lda sid.filter_mode_vol
  ora #mode
  sta sid.filter_mode_vol
  sta FilterModeVolumeControl
.endm

set_cutoff .macro cutOffFreq
  .if \cutOffFreq > 2047 | \cutOffFreq < 0
    .err "Freq out of bounds: " .. repr(\cutOffFreq)
  .endif
  .st FilterCutOffFreqLo, #(\cutOffFreq & %0000000000000111)
  .st FilterCutOffFreqHi, #(\cutOffFreq>>3) 
.endm

set_volume .macro level
  lda sid.filter_mode_vol
  and #$f0
  ora #\level
  sta sid.filter_mode_vol
  sta FilterModeVolumeControl
.endm

set_ctr_reg .macro voice, waveform
  voice_reg = VOICE_REGS[\voice]
  ; SID registers are write-only, so store in memory too to control the gate
  lda #(\waveform | Gate)
  sta sid.voice_to_waveform + \voice
  sta voice_reg + ControlReg
.endm

disable_gate .macro voice
  voice_reg = VOICE_REGS[\voice]
  lda sid.voice_to_waveform + \voice
  and #~Gate
  sta sid.voice_to_waveform + \voice
  sta voice_reg + ControlReg
.endm

enable_gate .macro voice
  voice_reg = VOICE_REGS[\voice]
  lda sid.voice_to_waveform + \voice
  ora #Gate
  sta sid.voice_to_waveform + \voice
  sta voice_reg + ControlReg
.endm 

v1 .segment sheet, octave=4
  jmp sid__v1_bytes_end
sid__v1_bytes:	
  .encode \sheet, \octave
sid__v1_bytes_end:
.endm

v2 .segment sheet, octave=4
  jmp sid__v2_bytes_end
sid__v2_bytes:	
  .encode \sheet, \octave
sid__v2_bytes_end:
.endm

v3 .segment sheet, octave=4
  jmp sid__v3_bytes_end
sid__v3_bytes:	
  .encode \sheet, \octave
sid__v3_bytes_end:
.endm
              
play_next_uses_xy:
  lda sid.voice_to_waveform
  beq _v2
  .play_next 0
_v2:
  lda sid.voice_to_waveform+1
  beq _v3
  .play_next 1
_v3:
  lda sid.voice_to_waveform+2
  beq _exit
  .play_next 2
_exit:
  rts

play_next .macro voice
  pha
  voice_ip = [sid.v1_ip, sid.v2_ip, sid.v3_ip]
  voice_bytes_start = [sid__v1_bytes, sid__v2_bytes, sid__v3_bytes]
  voice_bytes_end = [sid__v1_bytes_end, sid__v2_bytes_end, sid__v3_bytes_end]
  voice_reg = VOICE_REGS[\voice]
  ldx voice_ip[\voice]
  cpx #(voice_bytes_end[\voice] - voice_bytes_start[\voice])
  bne pn_nonloop
  .st voice_ip[\voice], #0
  jmp pn_exit
pn_nonloop:
  inc voice_ip[\voice]
  ldy voice_bytes_start[\voice], x
  cpy #SKIP_NOTE
  bne pn_nonskip
  .disable_gate \voice
  jmp pn_exit  
pn_nonskip:
  .st voice_reg + FreqLo, FreqTablePalLo + y
  .st voice_reg + FreqHi, FreqTablePalHi + y
  .enable_gate \voice
pn_exit:
  pla
.endm
        
v1_ip .word 0
v2_ip .word 0
v3_ip .word 0
voice_to_waveform .byte 0,0,0
filter_mode_vol .byte 0

FreqTablePalLo:
  ;      C   C#  D   D#  E   F   F#  G   G#  A   A#  B
  .byte $17,$27,$39,$4b,$5f,$74,$8a,$a1,$ba,$d4,$f0,$0e  ; 0
  .byte $2d,$4e,$71,$96,$be,$e8,$14,$43,$74,$a9,$e1,$1c  ; 1
  .byte $5a,$9c,$e2,$2d,$7c,$cf,$28,$85,$e8,$52,$c1,$37  ; 2
  .byte $b4,$39,$c5,$5a,$f7,$9e,$4f,$0a,$d1,$a3,$82,$6e  ; 3
  .byte $68,$71,$8a,$b3,$ee,$3c,$9e,$15,$a2,$46,$04,$dc  ; 4
  .byte $d0,$e2,$14,$67,$dd,$79,$3c,$29,$44,$8d,$08,$b8  ; 5
  .byte $a1,$c5,$28,$cd,$ba,$f1,$78,$53,$87,$1a,$10,$71  ; 6
  .byte $42,$89,$4f,$9b,$74,$e2,$f0,$a6,$0e,$33,$20,$ff  ; 7

FreqTablePalHi:
  ;      C   C#  D   D#  E   F   F#  G   G#  A   A#  B
  .byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$02  ; 0
  .byte $02,$02,$02,$02,$02,$02,$03,$03,$03,$03,$03,$04  ; 1
  .byte $04,$04,$04,$05,$05,$05,$06,$06,$06,$07,$07,$08  ; 2
  .byte $08,$09,$09,$0a,$0a,$0b,$0c,$0d,$0d,$0e,$0f,$10  ; 3
  .byte $11,$12,$13,$14,$15,$17,$18,$1a,$1b,$1d,$1f,$20  ; 4
  .byte $22,$24,$27,$29,$2b,$2e,$31,$34,$37,$3a,$3e,$41  ; 5
  .byte $45,$49,$4e,$52,$57,$5c,$62,$68,$6e,$75,$7c,$83  ; 6
  .byte $8b,$93,$9c,$a5,$af,$b9,$c4,$d0,$dd,$ea,$f8,$ff  ; 7
