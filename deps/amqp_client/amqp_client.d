src/amqp_auth_mechanisms.erl:: include/amqp_client.hrl; @touch $@
src/amqp_channel.erl:: include/amqp_client.hrl include/amqp_client_internal.hrl; @touch $@
src/amqp_channel_sup.erl:: include/amqp_client.hrl include/amqp_client_internal.hrl; @touch $@
src/amqp_channel_sup_sup.erl:: include/amqp_client.hrl; @touch $@
src/amqp_channels_manager.erl:: include/amqp_client.hrl include/amqp_client_internal.hrl; @touch $@
src/amqp_connection.erl:: include/amqp_client.hrl include/amqp_client_internal.hrl; @touch $@
src/amqp_connection_sup.erl:: include/amqp_client.hrl; @touch $@
src/amqp_connection_type_sup.erl:: include/amqp_client.hrl include/amqp_client_internal.hrl; @touch $@
src/amqp_direct_connection.erl:: include/amqp_client.hrl include/amqp_client_internal.hrl src/amqp_gen_connection.erl; @touch $@
src/amqp_direct_consumer.erl:: include/amqp_client.hrl include/amqp_gen_consumer_spec.hrl src/amqp_gen_consumer.erl; @touch $@
src/amqp_gen_connection.erl:: include/amqp_client.hrl include/amqp_client_internal.hrl; @touch $@
src/amqp_gen_consumer.erl:: include/amqp_client.hrl; @touch $@
src/amqp_main_reader.erl:: include/amqp_client.hrl include/amqp_client_internal.hrl; @touch $@
src/amqp_network_connection.erl:: include/amqp_client.hrl include/amqp_client_internal.hrl src/amqp_gen_connection.erl; @touch $@
src/amqp_rpc_client.erl:: include/amqp_client.hrl; @touch $@
src/amqp_rpc_server.erl:: include/amqp_client.hrl; @touch $@
src/amqp_selective_consumer.erl:: include/amqp_client.hrl include/amqp_gen_consumer_spec.hrl src/amqp_gen_consumer.erl; @touch $@
src/amqp_sup.erl:: include/amqp_client.hrl; @touch $@
src/amqp_uri.erl:: include/amqp_client.hrl; @touch $@
src/rabbit_routing_util.erl:: include/amqp_client.hrl include/rabbit_routing_prefixes.hrl; @touch $@

COMPILE_FIRST += amqp_gen_consumer amqp_gen_connection
