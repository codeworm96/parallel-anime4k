/* Adapted from file instrument.h in 15-418 code repository */

#ifndef INSTRUMENT_H

#include <stdio.h>

#define TRACK 1

/*
 This code keeps track of how time gets used, both on a per-thread basis,
 and globally (as measured by thread 0).

 The programmer should wrap the code for major activities with calls to
 START_ACTIVITY(s),
 and (possibly) a FINISH_LOCAL_ACTIVITY(a),
 and then a FINISH_ACTIVITY(a),
 where 'a' is one of the designated activity types.
 With OMP:
   The call to START_ACTIVITY should take occur before the parallel activity begins
   The call to FINISH_LOCAL_ACTIVITY should occur before the global synchronization point (if it exists)
   and the call to FINISH_ACTIVITY should occur after the parallel activity ends
*/

/* Categories of activities */

typedef enum {
    ACTIVITY_OVERHEAD, ACTIVITY_DECODE, ACTIVITY_LINEAR, ACTIVITY_LUM,
    ACTIVITY_THINLINES, ACTIVITY_GRADIENT, ACTIVITY_REFINE,
    ACTIVITY_COUNT
} activity_t;

void track_activity(bool enable);
void start_activity(activity_t a);
void finish_local_activity(activity_t a);
void finish_activity(activity_t a);
void show_activity(FILE *f, bool enable);

#if TRACK
#define START_ACTIVITY(a) start_activity(a)
#define FINISH_LOCAL_ACTIVITY(a) finish_local_activity(a)
#define FINISH_ACTIVITY(a) finish_activity(a)
#define SHOW_ACTIVITY(f,e) show_activity(f,e)
#else
#define TRACK_ACTIVITY(e)  /* Optimized out */
#define START_ACTIVITY(a)   /* Optimized out */
#define FINISH_LOCAL_ACTIVITY(a)  /* Optimized out */
#define FINISH_ACTIVITY(a)  /* Optimized out */
#define SHOW_ACTIVITY(f,e)  /* Optimized out */
#endif

#define INSTRUMENT_H
#endif
