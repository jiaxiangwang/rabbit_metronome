{application, 'rabbitmq_metronome', [
	{description, "Embedded Rabbit Metronome"},
	{vsn, "3.6.13+8.gf600054"},
	{modules, ['rabbit_metronome','rabbit_metronome_sup','rabbit_metronome_worker']},
	{registered, [rabbitmq_metronome_sup]},
	{applications, [kernel,stdlib,rabbit_common,rabbit,amqp_client]},
	{mod, {rabbit_metronome, []}},
	{env, []}
]}.