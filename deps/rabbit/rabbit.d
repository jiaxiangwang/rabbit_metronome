src/rabbit_cli.erl:: include/rabbit_cli.hrl; @touch $@
src/rabbit_control_main.erl:: include/rabbit_cli.hrl; @touch $@
src/rabbit_credential_validator_accept_everything.erl:: src/rabbit_credential_validator.erl; @touch $@
src/rabbit_credential_validator_min_password_length.erl:: src/rabbit_credential_validator.erl; @touch $@
src/rabbit_credential_validator_password_regexp.erl:: src/rabbit_credential_validator.erl; @touch $@
src/rabbit_error_logger.erl:: src/rabbit_error_logger_file_h.erl; @touch $@
src/rabbit_mirror_queue_coordinator.erl:: include/gm_specs.hrl src/gm.erl; @touch $@
src/rabbit_mirror_queue_mode_all.erl:: src/rabbit_mirror_queue_mode.erl; @touch $@
src/rabbit_mirror_queue_mode_exactly.erl:: src/rabbit_mirror_queue_mode.erl; @touch $@
src/rabbit_mirror_queue_mode_nodes.erl:: src/rabbit_mirror_queue_mode.erl; @touch $@
src/rabbit_mirror_queue_slave.erl:: include/gm_specs.hrl src/gm.erl; @touch $@
src/rabbit_plugins_main.erl:: include/rabbit_cli.hrl; @touch $@
src/rabbit_sasl_report_file_h.erl:: src/rabbit_error_logger_file_h.erl; @touch $@

COMPILE_FIRST += rabbit_mirror_queue_mode rabbit_credential_validator rabbit_error_logger_file_h gm
