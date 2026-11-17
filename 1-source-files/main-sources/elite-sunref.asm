\ ******************************************************************************
\
\ elite-sunref.asm - the Model B reference's fourth patch: the port's
\ sun-parking routines, assembled for the released disc Elite (Stairway to
\ Hell) so that the gate's reference runs the same game logic as the port
\ (2-build-files/sunref.py, which writes 3-assembled-output/sunref-syms.asm,
\ binding every name the routines use to the release's address for it, and
\ assembles this with PASSIVE 0 and 1; 6-harness/blib.mjs applies it)
\
\ The routines are elite-source-flight.asm's blocks tagged "Area: ..., again",
\ in the second emission that streams.py writes
\ (3-assembled-output/elite-flight-again.asm: their labels, and the targets of
\ their JSRs and JMPs, named A_<name>). The release has no free main RAM for
\ them, so they are assembled for &8000 and the harness puts them in a
\ sideways RAM slot that the release never uses (SR_SLOT, sunref.py), paged in
\ (ROMSEL and its copy at &F4) whenever the flight program runs; after them
\ comes the space station's own line heap, SR_HEAP (the sun keeps LSO, as the
\ station and the parked sun are now both drawn; NWSPS's two immediates point
\ the station there). The parked sun itself, SUNPK and SUNPF, is in main RAM,
\ in WP's tail (&0FD3-&0FF8) after CPIR, at the port's address: free in the
\ release, which does no disc command in flight and reloads the catalogue
\ there (CATD) before it loads the docked code.
\
\ PASSIVE = 1: the passive variant, whose part 14 and TT110 sites call the
\ release's own WPLS and NWSPS (P_SUNUP, P_SUNLAU), so that the sun is never
\ parked: it must run exactly as the release (6-harness/bsunref.mjs).
\
\ ******************************************************************************

 INCLUDE "3-assembled-output/sunref-syms.asm"

 ORG SR_ORG

.SR_START

 INCLUDE "3-assembled-output/elite-flight-again.asm"

IF PASSIVE

.P_SUNUP

 JMP A_WPLS

.P_SUNLAU

 JMP A_NWSPS

ENDIF

.SR_HEAP                \ the space station's line heap, at most 101 bytes (the
                        \ Dodo's: 4 * 25 + 1)

 SKIP 101

.SR_END

 ASSERT SR_END <= &C000

 SAVE "3-assembled-output/sunref.bin", SR_START, SR_HEAP
