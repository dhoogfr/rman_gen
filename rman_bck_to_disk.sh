#!/bin/bash
NB_ORA_PC_SCHED=$1 ; export NB_ORA_PC_SCHED
`dirname $0`/rman_bck.sh
