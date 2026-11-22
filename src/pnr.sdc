# The UART layout added up to four antenna diodes to a signal net after
# fanout repair. Reserve those loads under the eight-load sign-off limit.
source $::env(FALLBACK_SDC)
set_max_fanout 4 [current_design]
