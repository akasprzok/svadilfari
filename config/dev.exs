import Config

config :logger, :backends, [:console, Svadilfari]

config :logger, :svadilfari,
  metadata: [:user_id, :bogons],
  max_buffer: 1,
  client: [
    url: "http://localhost:3100",
    opts: [
      org_id: "tenant1"
    ]
  ],
  labels: [
    {"service", "loki"},
    {"cluster", "us-east-1"}
  ]
