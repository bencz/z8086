# Retain explicit routing-capacity margin for detailed routing.  The compact
# seven-block floorplan needs slightly more channel capacity than the earlier
# mixed placement: reserve 45% on local metals and 20% on upper metals.
set_global_routing_layer_adjustment metal2-metal3 0.45
set_global_routing_layer_adjustment metal4-$::env(MAX_ROUTING_LAYER) 0.20

set_routing_layers -clock $::env(MIN_CLK_ROUTING_LAYER)-$::env(MAX_ROUTING_LAYER)
set_routing_layers -signal $::env(MIN_ROUTING_LAYER)-$::env(MAX_ROUTING_LAYER)
