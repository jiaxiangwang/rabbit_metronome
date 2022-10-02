src/delegate.erl:: src/gen_server2.erl; @touch $@
src/file_handle_cache.erl:: src/gen_server2.erl; @touch $@
src/rabbit_auth_backend_dummy.erl:: include/old_builtin_types.hrl include/rabbit.hrl src/rabbit_authn_backend.erl src/rabbit_authz_backend.erl; @touch $@
src/rabbit_authn_backend.erl:: include/old_builtin_types.hrl include/rabbit.hrl; @touch $@
src/rabbit_authz_backend.erl:: include/old_builtin_types.hrl include/rabbit.hrl; @touch $@
src/rabbit_basic_common.erl:: include/old_builtin_types.hrl include/rabbit.hrl; @touch $@
src/rabbit_binary_generator.erl:: include/old_builtin_types.hrl include/rabbit.hrl include/rabbit_framing.hrl; @touch $@
src/rabbit_binary_parser.erl:: include/old_builtin_types.hrl include/rabbit.hrl; @touch $@
src/rabbit_command_assembler.erl:: include/old_builtin_types.hrl include/rabbit.hrl include/rabbit_framing.hrl; @touch $@
src/rabbit_core_metrics.erl:: include/rabbit_core_metrics.hrl; @touch $@
src/rabbit_event.erl:: include/old_builtin_types.hrl include/rabbit.hrl; @touch $@
src/rabbit_framing_amqp_0_8.erl:: include/rabbit_framing.hrl; @touch $@
src/rabbit_framing_amqp_0_9_1.erl:: include/rabbit_framing.hrl; @touch $@
src/rabbit_heartbeat.erl:: include/old_builtin_types.hrl include/rabbit.hrl; @touch $@
src/rabbit_misc.erl:: include/old_builtin_types.hrl include/rabbit.hrl include/rabbit_framing.hrl include/rabbit_misc.hrl; @touch $@
src/rabbit_msg_store_index.erl:: include/old_builtin_types.hrl include/rabbit.hrl include/rabbit_msg_store.hrl; @touch $@
src/rabbit_net.erl:: include/old_builtin_types.hrl include/rabbit.hrl; @touch $@
src/rabbit_password_hashing.erl:: include/old_builtin_types.hrl include/rabbit.hrl; @touch $@
src/rabbit_types.erl:: include/old_builtin_types.hrl include/rabbit.hrl; @touch $@
src/rabbit_writer.erl:: include/old_builtin_types.hrl include/rabbit.hrl include/rabbit_framing.hrl; @touch $@
src/vm_memory_monitor.erl:: include/rabbit_memory.hrl; @touch $@
src/worker_pool.erl:: src/gen_server2.erl; @touch $@
src/worker_pool_worker.erl:: src/gen_server2.erl; @touch $@

COMPILE_FIRST += gen_server2 rabbit_authz_backend rabbit_authn_backend
