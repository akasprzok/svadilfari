import Config

config :logger, :backends, [:console, Svadilfari]

config :logger, :svadilfari,
  metadata: [:user_id, :bogons],
  max_buffer: 10,
  client: [
    url: System.get_env("LOKI_URL", "http://localhost:3100"),
    opts: [
      org_id: "tenant1"
    ]
  ],
  labels: [
    {"service", "svadilfari"},
    {"env", "dev"}
  ]
