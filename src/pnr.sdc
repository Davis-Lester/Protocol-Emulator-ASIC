# Use the flow's timing and I/O constraints. The routed baseline added up to
# three antenna diodes to an eight-load signal net after fanout repair.
source $::env(FALLBACK_SDC)
set_max_fanout 5 [current_design]
